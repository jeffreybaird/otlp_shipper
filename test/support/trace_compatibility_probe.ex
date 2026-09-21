defmodule OtlpShipper.TraceProbeExporter do
  @moduledoc false
  @behaviour :otel_exporter_traces

  @impl true
  # Capture whether the consumer-owned Finch pool exists before exporter init.
  def init(state) do
    send(state.owner, {state.ref, :initialized, self(), Process.whereis(state.finch)})
    {:ok, state}
  end

  @impl true
  # Capture the borrowed SDK batch and optionally block until the probe releases it.
  def export(table, resource, state) do
    tid = :ets.whereis(table)
    spans = :ets.tab2list(table)
    terminating = self() == Process.whereis(state.processor)
    child = if state.mode == :child and spans != [] and not terminating, do: spawn_link(&wait/0)

    send(
      state.owner,
      {state.ref, :export,
       %{
         worker: self(),
         table: tid,
         owner: :ets.info(tid, :owner),
         spans: spans,
         resource: resource,
         terminating: terminating,
         child: child
       }}
    )

    if spans == [] or terminating do
      :ok
    else
      receive do
        {ref, :return, result} when ref == state.ref -> result
      after
        5_000 -> :failed_not_retryable
      end
    end
  end

  @impl true
  # Record callback invocation independently from process supervision.
  def shutdown(state) do
    send(state.owner, {state.ref, :shutdown})
    :ok
  end

  # Keep a linked child alive until cancelled by its SDK export worker.
  defp wait do
    receive do
      :stop -> :ok
    end
  end
end

defmodule OtlpShipper.TraceCompatibilityProbe do
  @moduledoc false
  alias OtlpShipper.TraceProbeExporter
  alias OtlpShipper.TraceRecordEvidence

  require Record

  Record.defrecordp(
    :sdk_span,
    :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  @names %{
    batch_lifetime: {TraceProbeLifetime, TraceProbeLifetimeFinch},
    cancellation: {TraceProbeCancellation, TraceProbeCancellationFinch},
    retry_result: {TraceProbeRetry, TraceProbeRetryFinch},
    flush_shutdown: {TraceProbeShutdown, TraceProbeShutdownFinch},
    queue_bound: {TraceProbeQueue, TraceProbeQueueFinch},
    owned_lifecycle: {TraceProbeOwned, TraceProbeOwnedFinch},
    record_fidelity: {TraceProbeRecord, TraceProbeRecordFinch}
  }

  @doc false
  @spec run(atom()) :: {:ok, map()}
  # Observe two independent supervision trees and a bounded linked-work lifetime.
  def run(:owned_lifecycle) do
    first = start_instance(:owned_lifecycle)
    second = start_instance(:batch_lifetime)

    try do
      ready = first.initial_pool == first.pool and second.initial_pool == second.pool
      first_down = stop_pool(first)
      second_alive = Process.alive?(second.pool)
      second_down = stop_pool(second)
      deadline = observe_deadline()

      {:ok,
       Map.merge(deadline, %{
         initial_pools_ready: ready,
         first_pool_down_reason: first_down,
         second_pool_alive: second_alive,
         second_pool_down_reason: second_down
       })}
    after
      stop_instance(first)
      stop_instance(second)
    end
  end

  # Observe dependent SDK restarts after the first Finch subtree is killed.
  def run(:pool_restart) do
    first = start_instance(:owned_lifecycle)
    second = start_instance(:batch_lifetime)

    try do
      {:ok, observe_restart(first, second)}
    after
      stop_instance(first)
      stop_instance(second)
    end
  end

  # Run one SDK observation and always tear down its supervision tree.
  def run(scenario) do
    instance = start_instance(scenario)

    try do
      {:ok, observe(scenario, instance)}
    after
      stop_instance(instance)
    end
  end

  # Start Finch before a uniquely named SDK provider and its batch processor.
  defp start_instance(scenario) do
    {name, finch} = Map.fetch!(@names, scenario)
    processor = :"otel_batch_processor_#{name}"
    ref = make_ref()
    resource = :otel_resource.create(%{"service.name" => "trace-probe"}, "https://probe/resource")

    exporter = %{
      owner: self(),
      ref: ref,
      finch: finch,
      processor: processor,
      mode: if(scenario == :cancellation, do: :child, else: :hold)
    }

    batch = %{
      name: name,
      resource: resource,
      exporter: {TraceProbeExporter, exporter},
      max_queue_size: 1,
      scheduled_delay_ms: 60_000,
      check_table_size_ms: if(scenario == :queue_bound, do: 20, else: 60_000),
      exporting_timeout_ms: if(scenario == :cancellation, do: 500, else: 2_000)
    }

    opts = %{
      id_generator: :otel_id_generator,
      sampler: :always_on,
      processors: [{:otel_batch_processor, batch}],
      deny_list: []
    }

    children = [
      %{
        id: finch,
        start: {OtlpShipper.Pool, :start_link, [finch, :atomics.new(1, [])]},
        type: :supervisor
      },
      %{
        id: name,
        start: {:otel_tracer_server_sup, :start_link, [name, resource, opts]},
        type: :supervisor
      }
    ]

    {:ok, supervisor} = Supervisor.start_link(children, strategy: :rest_for_one)

    initial_pool =
      receive do
        {^ref, :initialized, _pid, pool} -> pool
      after
        1_000 -> raise "probe exporter did not initialize"
      end

    tracer = :otel_tracer_provider.get_tracer(name, :trace_probe, "1.0", "https://probe/scope")

    %{
      supervisor: supervisor,
      name: name,
      finch: finch,
      pool: Process.whereis(finch),
      processor: processor,
      ref: ref,
      tracer: tracer,
      initial_pool: initial_pool
    }
  end

  # Observe borrowed-table ownership and destruction after callback completion.
  defp observe(:batch_lifetime, instance) do
    emit(instance, "lifetime")
    flush = :otel_tracer_provider.force_flush(instance.name)
    export = await_export(instance.ref)
    complete(instance, export, :ok)

    %{
      flush_result: flush,
      callback_worker: export.worker,
      table_owner: export.owner,
      span_count: length(export.spans),
      table_after: :ets.info(export.table)
    }
  end

  # Observe the SDK killing a blocked export worker and its linked child.
  defp observe(:cancellation, instance) do
    emit(instance, "cancel")
    :otel_tracer_provider.force_flush(instance.name)
    export = await_export(instance.ref)
    worker_ref = Process.monitor(export.worker)
    child_ref = Process.monitor(export.child)

    %{
      worker_down_reason: await_down(worker_ref),
      linked_child_down_reason: await_down(child_ref),
      table_after: :ets.info(export.table)
    }
  end

  # Flush a second span to distinguish fresh export from replay of the first batch.
  defp observe(:retry_result, instance) do
    emit(instance, "original")
    :otel_tracer_provider.force_flush(instance.name)
    first = await_export(instance.ref)
    complete(instance, first, :failed_retryable)
    emit(instance, "marker")
    :otel_tracer_provider.force_flush(instance.name)
    second = await_export(instance.ref)
    complete(instance, second, :ok)

    %{
      first_export_count: length(first.spans),
      replay_count: Enum.count(second.spans, &(&1 in first.spans)),
      table_after: :ets.info(first.table)
    }
  end

  # Separate asynchronous flush completion from termination export and shutdown callbacks.
  defp observe(:flush_shutdown, instance) do
    emit(instance, "flush")
    flush = :otel_tracer_provider.force_flush(instance.name)
    first = await_export(instance.ref)
    blocked = Process.alive?(first.worker) and :ets.info(first.table) != :undefined
    complete(instance, first, :ok)
    emit(instance, "final")
    Supervisor.stop(instance.supervisor)
    final = await_export(instance.ref)

    %{
      flush_result: flush,
      worker_blocked_after_flush: blocked,
      final_export_count: length(final.spans),
      shutdown_callback_count: shutdown_count(instance.ref)
    }
  end

  # Pause periodic checks while admitting a burst, then observe disabled admission.
  defp observe(:queue_bound, instance) do
    :sys.suspend(instance.processor)
    accepted = Enum.count(1..3, fn index -> enqueue_span(instance, "burst-#{index}") == true end)
    :sys.resume(instance.processor)
    wait_for_disabled(instance.processor, System.monotonic_time(:millisecond) + 1_000)

    %{
      configured_limit: 1,
      accepted_before_check: accepted,
      admission_after_check: enqueue_span(instance, "overflow")
    }
  end

  # Capture a rich real SDK span before translating its records to evidence.
  defp observe(:record_fidelity, instance) do
    limits = TraceRecordEvidence.emit(instance.tracer)
    :otel_tracer_provider.force_flush(instance.name)
    export = await_export(instance.ref)
    [span] = export.spans
    evidence = TraceRecordEvidence.describe(span, export.resource, limits)
    complete(instance, export, :ok)
    evidence
  end

  # Kill only the first Finch supervisor and compare both instances after restart.
  defp observe_restart(first, second) do
    old_pool = child_pid(first.supervisor, first.finch)
    old_provider = Process.whereis(:"otel_tracer_provider_#{first.name}")
    old_processor = Process.whereis(first.processor)
    second_provider = Process.whereis(:"otel_tracer_provider_#{second.name}")
    monitor = Process.monitor(old_pool)
    Process.exit(old_pool, :kill)
    reason = await_down(monitor)
    ref = first.ref

    receive do
      {^ref, :initialized, _processor, _pool} -> :ok
    after
      3_000 -> raise "replacement exporter did not initialize"
    end

    # The parent replies only after the complete rest-for-one restart finishes.
    new_pool = child_pid(first.supervisor, first.finch)
    discard_events(first.ref)

    tracer =
      :otel_tracer_provider.get_tracer(first.name, :trace_probe, "1.0", "https://probe/scope")

    first_names = export_names(%{first | tracer: tracer}, "after-restart")
    second_names = export_names(second, "unaffected")

    %{
      old_pool_down_reason: reason,
      old_pool: old_pool,
      new_pool: new_pool,
      old_provider: old_provider,
      new_provider: Process.whereis(:"otel_tracer_provider_#{first.name}"),
      old_processor: old_processor,
      new_processor: Process.whereis(first.processor),
      second_provider_before: second_provider,
      second_provider_after: Process.whereis(:"otel_tracer_provider_#{second.name}"),
      first_exported_names: first_names,
      second_exported_names: second_names
    }
  end

  # Read the actual supervised subtree PID rather than Finch's registry PID.
  defp child_pid(supervisor, id) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn {child_id, pid, _, _} -> if child_id == id, do: pid end)
  end

  # Flush one API-created span and report the names seen by the real callback.
  defp export_names(instance, name) do
    emit(instance, name)
    :otel_tracer_provider.force_flush(instance.name)
    export = await_export(instance.ref)
    names = Enum.map(export.spans, &sdk_span(&1, :name))
    complete(instance, export, :ok)
    names
  end

  # Create and finish a real span through the tracing API.
  defp emit(instance, name) do
    instance.tracer |> :otel_tracer.start_span(name, %{}) |> :otel_span.end_span()
  end

  # The API end_span returns a context; the SDK callback exposes admission status.
  defp enqueue_span(instance, name) do
    instance.tracer |> :otel_tracer.start_span(name, %{}) |> :otel_span_ets.end_span()
  end

  # Wait for this probe instance to report a callback snapshot.
  defp await_export(ref) do
    receive do
      {^ref, :export, observation} -> observation
    after
      3_000 -> raise "probe export did not arrive"
    end
  end

  # Release a callback and wait for its worker to exit before probing the next batch.
  defp complete(instance, export, result) do
    monitor = Process.monitor(export.worker)
    send(export.worker, {instance.ref, :return, result})
    :normal = await_down(monitor)
    :sys.get_state(instance.processor)
  end

  # Read one monitored process exit with a bounded wait.
  defp await_down(ref) do
    receive do
      {:DOWN, ^ref, :process, _pid, reason} -> reason
    after
      3_000 -> raise "probe process did not terminate"
    end
  end

  # Poll the SDK admission flag until its periodic check observes overflow.
  defp wait_for_disabled(processor, deadline) do
    cond do
      :persistent_term.get({:otel_batch_processor, :enabled_key, processor}) == false ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "queue check did not disable admission"

      true ->
        Process.sleep(1)
        wait_for_disabled(processor, deadline)
    end
  end

  # Stop the consumer supervision tree and observe its Finch pool exit.
  defp stop_pool(instance) do
    monitor = Process.monitor(instance.pool)
    Supervisor.stop(instance.supervisor)
    await_down(monitor)
  end

  # Clean up an instance and drain only its own callback messages.
  defp stop_instance(instance) do
    if Process.alive?(instance.supervisor), do: Supervisor.stop(instance.supervisor)
    discard_events(instance.ref)
  end

  # Drain this instance's callback observations without touching other messages.
  defp discard_events(ref) do
    receive do
      {^ref, _, _} -> discard_events(ref)
      {^ref, _, _, _} -> discard_events(ref)
      {^ref, :shutdown} -> discard_events(ref)
    after
      0 -> :ok
    end
  end

  # Count observed shutdown callbacks already delivered by the stopped instance.
  defp shutdown_count(ref, count \\ 0) do
    receive do
      {^ref, :shutdown} -> shutdown_count(ref, count + 1)
    after
      0 -> count
    end
  end

  # Prototype one total deadline for blocked conversion with a linked retry child.
  defp observe_deadline do
    owner = self()
    ref = make_ref()
    timeout = 100
    started = System.monotonic_time(:millisecond)

    task =
      Task.async(fn ->
        child = spawn_link(fn -> Process.sleep(:infinity) end)
        send(owner, {ref, :deadline_child, child})
        Process.sleep(:infinity)
      end)

    child =
      receive do
        {^ref, :deadline_child, child} -> child
      after
        1_000 -> raise "deadline child did not start"
      end

    task_monitor = Process.monitor(task.pid)
    child_monitor = Process.monitor(child)
    remaining = max(started + timeout - System.monotonic_time(:millisecond), 0)
    Task.yield(task, remaining) || Task.shutdown(task, :brutal_kill)
    conversion_reason = await_down(task_monitor)
    retry_reason = await_down(child_monitor)

    %{
      timeout_ms: timeout,
      elapsed_ms: System.monotonic_time(:millisecond) - started,
      conversion_down_reason: conversion_reason,
      retry_child_down_reason: retry_reason
    }
  end
end
