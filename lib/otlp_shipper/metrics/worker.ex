defmodule OtlpShipper.Metrics.Worker do
  @moduledoc false
  use GenServer
  alias OtlpShipper.Buffer
  alias OtlpShipper.Metrics.Aggregation

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    Logger.metadata(domain: [:otlp_shipper])
    [{:buffer, buffer}] = :ets.lookup(opts[:handles], :buffer)
    credits = :atomics.new(2, [])

    ingress = %{
      owner: self(),
      credits: credits,
      max_pending: opts[:settings][:max_pending],
      max_tag_bytes: opts[:settings][:max_tag_bytes],
      finch_name: opts[:settings][:finch_name]
    }

    :ets.insert(opts[:handles], {:ingress, ingress})
    config = opts[:config]
    definitions = Map.new(opts[:definitions], &{&1.name, &1})
    timer = schedule_interval(config.flush_ms)

    {:ok,
     %{
       buffer: buffer,
       ingress: ingress,
       series: %{},
       nonmonotonic: MapSet.new(),
       definitions: definitions,
       config: config,
       max_series: opts[:settings][:max_series],
       started: System.os_time(:nanosecond),
       timer: timer
     }}
  end

  @impl true
  def handle_info({:sample, name, attributes, value, observed}, state) do
    :atomics.sub(state.ingress.credits, 1, 1)
    {:noreply, aggregate(state, name, attributes, value, observed)}
  end

  def handle_info({:interval, token}, %{timer: {_, token}} = state) do
    state = snapshot(state)
    timer = schedule_interval(state.config.flush_ms)
    {:noreply, %{state | timer: timer}}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def handle_call(:flush, _, state) do
    Process.cancel_timer(elem(state.timer, 0))
    state = snapshot(state)
    timer = schedule_interval(state.config.flush_ms)
    {:reply, :ok, %{state | timer: timer}}
  end

  @impl true
  def terminate(_, state) do
    :atomics.put(state.ingress.credits, 2, 1)
    Process.cancel_timer(elem(state.timer, 0))
    # The registration child stops first. Drain already-reserved messages within
    # the configured budget; racing callbacks can still be lost during shutdown.
    deadline = System.monotonic_time(:millisecond) + state.config.shutdown_ms
    state |> drain_pending(deadline) |> snapshot()
    :ok
  end

  defp schedule_interval(interval) do
    token = make_ref()
    {Process.send_after(self(), {:interval, token}, interval), token}
  end

  defp drain_pending(state, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      dropped(:shutdown, :atomics.get(state.ingress.credits, 1))
      state
    else
      receive do
        {:sample, name, attributes, value, observed} ->
          :atomics.sub(state.ingress.credits, 1, 1)
          state |> aggregate(name, attributes, value, observed) |> drain_pending(deadline)
      after
        0 -> state
      end
    end
  end

  defp aggregate(state, name, attributes, value, observed) do
    key = {name, attributes}
    previous = Map.get(state.series, key)

    if is_nil(previous) and map_size(state.series) >= state.max_series do
      dropped(:series_limit, 1)
      state
    else
      definition = Map.fetch!(state.definitions, name)

      case Aggregation.add(definition.kind, previous, value, definition.bounds, observed) do
        {:ok, next} ->
          negative = definition.kind == :sum and value < 0

          nonmonotonic =
            if negative, do: MapSet.put(state.nonmonotonic, name), else: state.nonmonotonic

          %{state | series: Map.put(state.series, key, next), nonmonotonic: nonmonotonic}

        {:error, reason} ->
          dropped(reason, 1)
          state
      end
    end
  end

  defp snapshot(state) do
    ended = max(System.os_time(:nanosecond), state.started + 1)

    state.series
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.each(fn {{name, attributes}, aggregate} ->
      definition = Map.fetch!(state.definitions, name)

      metric =
        Aggregation.metric(
          definition,
          aggregate,
          attributes,
          state.started,
          ended,
          not MapSet.member?(state.nonmonotonic, name)
        )

      if Buffer.enqueue(state.buffer, metric) == {:error, :closed}, do: dropped(:unavailable, 1)
    end)

    Buffer.flush(state.buffer)
    %{state | series: %{}, started: ended}
  end

  defp dropped(_, 0), do: :ok

  defp dropped(reason, count),
    do:
      :telemetry.execute([:otlp_shipper, :dropped], %{count: count}, %{
        signal: :metrics,
        reason: reason
      })
end
