defmodule OtlpShipper.Buffer do
  @moduledoc """
  A supervised, fixed-capacity ingress ring and single batch worker.

  Producers obtain a handle once with `handle/1`, then call `enqueue/2` without
  sending a message per item. Ring slots replace older entries under overload.
  Only one wakeup is pending at a time; export runs outside the GenServer.

  One queued ring plus one in-flight batch bounds retained work. Items must fit
  `max_item_bytes` measured using Erlang external size. Batches also respect
  `max_batch_bytes`. Overflow drops old queued records, never in-flight records.
  Concurrent producer order is best effort. A handle is invalid after restart;
  adapters must acquire the replacement handle. There is no disk persistence.

  The export callback receives a list and returns `:ok`, `{:ok, :partial, count}`,
  or a tagged error. Transport owns normal export/drop diagnostics; this module
  records ingress drops and crashed/timed-out callbacks. A callback is never
  allowed to run longer than the configured export timeout.
  """
  use GenServer
  alias OtlpShipper.Config

  defmodule Handle do
    @moduledoc "Opaque producer handle for one buffer process incarnation. Obtain it through `OtlpShipper.Buffer.handle/1`."
    @enforce_keys [:table, :sequence, :wake, :owner, :config]
    defstruct @enforce_keys

    @opaque t :: %__MODULE__{
              table: :ets.tid(),
              sequence: :atomics.atomics_ref(),
              wake: :atomics.atomics_ref(),
              owner: pid(),
              config: Config.t()
            }
  end

  @doc "Starts a buffer under the consumer's supervisor; requires `:config` and `:export`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    case {Keyword.get(opts, :config), Keyword.get(opts, :export)} do
      {%Config{}, export} when is_function(export, 1) ->
        GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

      _ ->
        {:error, {:error, :invalid_buffer_options}}
    end
  end

  @doc false
  def child_spec(opts) do
    config = Keyword.get(opts, :config, %Config{})

    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      shutdown: config.shutdown_ms + 1000
    }
  end

  @doc "Obtains the producer handle for this process incarnation."
  @spec handle(GenServer.server()) :: Handle.t()
  def handle(server), do: GenServer.call(server, :handle)

  @doc """
  Enqueues an item without waiting for export.

  `:ok` means queued, not delivered. Oversized items and handles whose owner has
  stopped return errors. Overflow replaces the oldest slot and emits drop counts.
  """
  @spec enqueue(Handle.t(), term()) :: :ok | {:error, :closed | :item_too_large}
  def enqueue(%Handle{} = handle, item) do
    size = :erlang.external_size(item)

    cond do
      not Process.alive?(handle.owner) or :atomics.get(handle.sequence, 2) == 1 ->
        {:error, :closed}

      size > handle.config.max_item_bytes ->
        dropped(handle.config.signal, 1, :item_too_large)
        {:error, :item_too_large}

      true ->
        sequence = :atomics.add_get(handle.sequence, 1, 1)
        slot = rem(sequence, handle.config.max_queue)
        entry = {slot, sequence, item, size}
        store_entry(handle, entry)
        if :ets.info(handle.table, :size) >= handle.config.max_batch, do: wake(handle)
        :ok
    end
  rescue
    ArgumentError -> {:error, :closed}
  end

  @doc "Returns the current queued item count; in-flight items are excluded."
  @spec size(Handle.t()) :: non_neg_integer()
  def size(%Handle{} = handle) do
    case :ets.info(handle.table, :size) do
      :undefined -> 0
      count -> count
    end
  end

  @doc "Requests a batch flush without blocking the caller or promising delivery."
  @spec flush(Handle.t()) :: :ok
  def flush(%Handle{} = handle), do: wake(handle)

  @impl true
  def init(opts) do
    case {Keyword.get(opts, :config), Keyword.get(opts, :export)} do
      {%Config{} = config, export} when is_function(export, 1) ->
        Process.flag(:trap_exit, true)
        table = :ets.new(__MODULE__, [:set, :public, write_concurrency: true])

        handle = %Handle{
          table: table,
          sequence: :atomics.new(2, []),
          wake: :atomics.new(1, []),
          owner: self(),
          config: config
        }

        timer = Process.send_after(self(), :tick, config.flush_ms)

        {:ok,
         %{handle: handle, export: export, worker: nil, timer: timer, flush_requested: false}}

      _ ->
        {:stop, {:error, :invalid_buffer_options}}
    end
  end

  @impl true
  def handle_call(:handle, _from, state), do: {:reply, state.handle, state}

  @impl true
  def handle_info(:ready, state) do
    :atomics.put(state.handle.wake, 1, 0)
    {:noreply, maybe_export(%{state | flush_requested: true})}
  end

  def handle_info(:tick, state) do
    timer = Process.send_after(self(), :tick, state.handle.config.flush_ms)
    {:noreply, maybe_export(%{state | timer: timer, flush_requested: true})}
  end

  def handle_info({ref, result}, %{worker: %{task: %Task{ref: ref}}} = state) do
    Process.demonitor(ref, [:flush])

    if result == {:buffer_failure, :callback_failed},
      do: dropped(state.handle.config.signal, state.worker.count, :export_failed)

    Process.cancel_timer(state.worker.timer)
    {:noreply, maybe_export(%{state | worker: nil})}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{worker: %{task: %Task{ref: ref}}} = state
      ) do
    Process.cancel_timer(state.worker.timer)
    dropped(state.handle.config.signal, state.worker.count, :export_failed)
    {:noreply, maybe_export(%{state | worker: nil})}
  end

  def handle_info({:worker_timeout, ref}, %{worker: %{task: %Task{ref: ref}}} = state) do
    Task.shutdown(state.worker.task, :brutal_kill)
    dropped(state.handle.config.signal, state.worker.count, :export_failed)
    {:noreply, maybe_export(%{state | worker: nil})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    :atomics.put(state.handle.sequence, 2, 1)
    Process.cancel_timer(state.timer)
    deadline = System.monotonic_time(:millisecond) + state.handle.config.shutdown_ms
    finish_worker(state.worker, state.handle.config.signal, deadline)
    drain_shutdown(state, deadline)
    :ok
  end

  defp store_entry(handle, {slot, sequence, _, _} = entry) do
    unless :ets.insert_new(handle.table, entry) do
      replaced =
        :ets.select_replace(handle.table, [
          {{slot, :"$1", :"$2", :"$3"}, [{:<, :"$1", sequence}], [{:const, entry}]}
        ])

      if replaced == 0 and :ets.insert_new(handle.table, entry) do
        :ok
      else
        dropped(handle.config.signal, 1, :queue_full)
      end
    end
  end

  defp wake(handle) do
    if :atomics.compare_exchange(handle.wake, 1, 0, 1) == :ok, do: send(handle.owner, :ready)
    :ok
  end

  defp maybe_export(%{worker: nil} = state) do
    if state.flush_requested or size(state.handle) >= state.handle.config.max_batch do
      case take_batch(state.handle) do
        [] ->
          %{state | flush_requested: false}

        items ->
          task = start_export(state.export, items)

          timer =
            Process.send_after(self(), {:worker_timeout, task.ref}, state.handle.config.timeout)

          %{
            state
            | worker: %{task: task, count: length(items), timer: timer},
              flush_requested: false
          }
      end
    else
      state
    end
  end

  defp maybe_export(state), do: state

  defp take_batch(handle) do
    handle.table
    |> :ets.tab2list()
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.reduce_while({[], 0, 0}, fn {slot, sequence, item, size}, {items, count, bytes} ->
      if count >= handle.config.max_batch or bytes + size > handle.config.max_batch_bytes do
        {:halt, {items, count, bytes}}
      else
        take_entry(handle.table, {slot, sequence, item, size}, {items, count, bytes})
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp take_entry(table, {slot, sequence, item, size}, {items, count, bytes}) do
    deleted = :ets.select_delete(table, [{{slot, sequence, :"$1", :"$2"}, [], [true]}])

    if deleted == 1,
      do: {:cont, {[item | items], count + 1, bytes + size}},
      else: {:cont, {items, count, bytes}}
  end

  defp start_export(export, items) do
    Task.async(fn ->
      try do
        export.(items)
      rescue
        _ -> {:buffer_failure, :callback_failed}
      catch
        _, _ -> {:buffer_failure, :callback_failed}
      end
    end)
  end

  defp finish_worker(nil, _signal, _deadline), do: :ok

  defp finish_worker(worker, signal, deadline) do
    Process.cancel_timer(worker.timer)
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    case Task.yield(worker.task, remaining) || Task.shutdown(worker.task, :brutal_kill) do
      {:ok, {:buffer_failure, :callback_failed}} -> dropped(signal, worker.count, :export_failed)
      {:ok, _} -> :ok
      _ -> dropped(signal, worker.count, :export_failed)
    end
  end

  defp drain_shutdown(state, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      dropped(state.handle.config.signal, size(state.handle), :shutdown)
    else
      drain_batch(state, deadline, take_batch(state.handle))
    end
  end

  defp drain_batch(_state, _deadline, []), do: :ok

  defp drain_batch(state, deadline, items) do
    task = start_export(state.export, items)
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    case Task.yield(task, remaining) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:buffer_failure, :callback_failed}} ->
        dropped(state.handle.config.signal, length(items), :export_failed)

      {:ok, _} ->
        :ok

      _ ->
        dropped(state.handle.config.signal, length(items), :export_failed)
    end

    drain_shutdown(state, deadline)
  end

  defp dropped(_signal, 0, _reason), do: :ok

  defp dropped(signal, count, reason),
    do:
      :telemetry.execute([:otlp_shipper, :dropped], %{count: count}, %{
        signal: signal,
        reason: reason
      })
end
