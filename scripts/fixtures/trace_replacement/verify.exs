Code.require_file("collector.exs", __DIR__)

defmodule ReplacementProof do
  @moduledoc false

  # Run only against a built release; no Mix or canonical exporter is used at runtime.
  def run do
    isolate_environment()
    started = System.monotonic_time(:millisecond)
    {:ok, _} = Application.ensure_all_started(:replacement_consumer)
    ~c"1.7.0" = Application.spec(:opentelemetry, :vsn)
    ~c"1.5.0" = Application.spec(:opentelemetry_api, :vsn)
    ~c"0.2.0" = Application.spec(:opentelemetry_finch, :vsn)
    :non_existing = :code.which(:opentelemetry_exporter)
    :non_existing = :code.which(:gpb_compile)
    false = Enum.any?(Application.started_applications(), &(elem(&1, 0) == :opentelemetry))
    before_memory = :erlang.memory(:total)
    {collector, listener, endpoint} = ReplacementCollector.start_link()

    try do
      requests = exercise(collector, endpoint)
      evidence = verify(requests)
      report = Map.merge(evidence, inventory(started, before_memory))
      publish(report)
    after
      ReplacementCollector.stop(collector, listener)
    end
  end

  # Host OTEL settings must not override this disposable consumer's test configuration.
  defp isolate_environment do
    System.get_env()
    |> Map.keys()
    |> Enum.filter(&String.starts_with?(&1, "OTEL_"))
    |> Enum.each(&System.delete_env/1)
  end

  # Configure the included SDK before starting its consumer-owned supervisor.
  defp start_sdk(endpoint) do
    Application.put_all_env(
      opentelemetry: [
        resource: %{
          service: %{name: "replacement-consumer", instance: %{id: "replacement-instance-1"}}
        },
        resource_detectors: [:otel_resource_app_env],
        sampler: {OtlpShipper.TraceSampler, :always_on},
        traces_exporter:
          {OtlpShipper.TraceExporter,
           [pool: ReplacementFinch, endpoint: endpoint <> "/v1/traces"]},
        bsp_scheduled_delay_ms: 60_000,
        bsp_exporting_timeout_ms: 12_000
      ]
    )

    children = [
      OtlpShipper.TraceExporter.pool_child_spec(ReplacementFinch),
      %{
        id: :included_opentelemetry,
        type: :supervisor,
        shutdown: :infinity,
        start: {:opentelemetry_app, :start, [:normal, []]}
      }
    ]

    Supervisor.start_link(children, strategy: :rest_for_one)
  end

  # Ordinary instrumentation uses the SDK-created global application tracer cache.
  defp exercise(collector, endpoint) do
    {:ok, owner} = start_sdk(endpoint)
    restart_owned_sdk(owner)
    provider = Process.whereis(:otel_tracer_provider_global)
    true = is_pid(provider)
    :ok = OpentelemetryFinch.setup()

    :ok =
      :telemetry.attach_many(
        :replacement_diagnostics,
        [
          [:otlp_shipper, :dropped],
          [:otlp_shipper, :export, :stop],
          [:otlp_shipper, :export, :exception]
        ],
        &__MODULE__.diagnostic/4,
        self()
      )

    {:ok, logs} =
      OtlpShipper.LogHandler.start_link(
        service_name: "replacement-consumer",
        service_instance_id: "replacement-instance-1",
        endpoint: endpoint <> "/v1/logs",
        max_batch: 1
      )

    {:ok, metrics} =
      OtlpShipper.MetricsReporter.start_link(
        service_name: "replacement-consumer",
        service_instance_id: "replacement-instance-1",
        endpoint: endpoint <> "/v1/metrics",
        metrics: [Telemetry.Metrics.counter("replacement.events.count")]
      )

    try do
      emit_operation(endpoint)
      :logger.log(:notice, "replacement outside context")
      :telemetry.execute([:replacement, :events], %{count: 1})
      :ok = OtlpShipper.MetricsReporter.flush(metrics)
      :ok = :otel_tracer_provider.force_flush()
      await_signals(collector, System.monotonic_time(:millisecond) + 5000)
      :ok = :otel_tracer_provider.force_flush()
    after
      Supervisor.stop(metrics)
      Supervisor.stop(logs)
      # Provider termination drains queued spans while Finch is still available.
      Supervisor.stop(owner)
      :telemetry.detach({OpentelemetryFinch, :request_stop})
      :telemetry.detach(:replacement_diagnostics)
    end

    nil = Process.whereis(ReplacementFinch)
    false = Process.alive?(provider)
    nil = Process.whereis(:otel_tracer_provider_global)
    ReplacementCollector.snapshot(collector)
  end

  # Retain bounded, payload-free trace diagnostics when a release assertion fails.
  def diagnostic(event, measurements, %{signal: :traces} = metadata, owner),
    do:
      send(
        owner,
        {:trace_diagnostic, event, Map.take(measurements, [:count]),
         Map.take(metadata, [:status, :reason])}
      )

  def diagnostic(_, _, _, _), do: :ok

  # Bound failure reporting even if many attempts generated diagnostic messages.
  defp diagnostics(remaining \\ 10)
  defp diagnostics(0), do: []

  defp diagnostics(remaining) do
    receive do
      {:trace_diagnostic, event, measurements, metadata} ->
        [{event, measurements, metadata} | diagnostics(remaining - 1)]
    after
      0 -> []
    end
  end

  # A pool crash must replace the dependent global SDK before application work resumes.
  defp restart_owned_sdk(owner) do
    old_provider = Process.whereis(:otel_tracer_provider_global)
    old_sdk = Process.whereis(:opentelemetry_sup)
    true = is_pid(old_provider) and is_pid(old_sdk)
    monitor = Process.monitor(old_provider)

    {ReplacementFinch, pool, :supervisor, _} =
      Enum.find(Supervisor.which_children(owner), &(elem(&1, 0) == ReplacementFinch))

    Process.exit(pool, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^old_provider, _} -> :ok
    after
      5000 -> raise "pool crash did not stop the dependent SDK provider"
    end

    # The supervisor call waits until the complete ordered restart has finished.
    children = Supervisor.which_children(owner)

    {:included_opentelemetry, new_sdk, :supervisor, _} =
      Enum.find(children, &(elem(&1, 0) == :included_opentelemetry))

    true = is_pid(new_sdk) and new_sdk != old_sdk
    new_provider = Process.whereis(:otel_tracer_provider_global)
    true = is_pid(new_provider) and new_provider != old_provider
  end

  # Attach a real SDK parent so the HTTP instrumentation and Logger share identity.
  defp emit_operation(endpoint) do
    tracer =
      :otel_tracer_provider.get_tracer(
        :replacement_operation,
        "1",
        "https://scope.example"
      )

    span =
      :otel_tracer.start_span(:otel_ctx.new(), tracer, "replacement operation", %{kind: :server})

    true = :otel_span.is_recording(span)

    token = :otel_ctx.attach(:otel_tracer.set_current_span(:otel_ctx.new(), span))

    try do
      :logger.log(:notice, "replacement inside context")

      {:ok, %{status: 200}} =
        Finch.request(Finch.build(:get, endpoint <> "/ordinary"), ReplacementFinch)
    after
      :otel_ctx.detach(token)
      :otel_span.end_span(span)
    end
  end

  # Observe decoded delivery rather than treating SDK force_flush as an acknowledgement.
  defp await_signals(collector, deadline) do
    requests = ReplacementCollector.snapshot(collector)
    counts = counts(requests)

    cond do
      counts.logs >= 2 and counts.metrics >= 1 and counts.traces >= 2 ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "three-signal delivery timed out: #{inspect(counts)}; #{inspect(diagnostics())}"

      true ->
        Process.sleep(10)
        await_signals(collector, deadline)
    end
  end

  # Flatten only generated signal envelopes; preserve every record for exact assertions.
  defp entries(requests, path, outer, scopes, records) do
    for {^path, request} <- requests,
        resource <- Map.fetch!(request, outer),
        scope <- Map.fetch!(resource, scopes),
        record <- Map.fetch!(scope, records),
        do: {resource, scope, record}
  end

  # These counts describe decoded records, not HTTP requests or flush initiations.
  defp counts(requests) do
    %{
      logs: length(entries(requests, "/v1/logs", :resource_logs, :scope_logs, :log_records)),
      metrics:
        length(entries(requests, "/v1/metrics", :resource_metrics, :scope_metrics, :metrics)),
      traces: length(entries(requests, "/v1/traces", :resource_spans, :scope_spans, :spans))
    }
  end

  # Assert cross-signal identity, real instrumentation, typed metric data, and no feedback.
  defp verify(requests) do
    logs = entries(requests, "/v1/logs", :resource_logs, :scope_logs, :log_records)
    metrics = entries(requests, "/v1/metrics", :resource_metrics, :scope_metrics, :metrics)
    traces = entries(requests, "/v1/traces", :resource_spans, :scope_spans, :spans)
    %{logs: 2, metrics: 1, traces: 2} = counts(requests)
    [{"/ordinary", :ordinary}] = Enum.filter(requests, &(elem(&1, 0) == "/ordinary"))

    for {resource, _, _} <- logs ++ metrics ++ traces do
      true =
        %{key: "service.name", value: %{value: {:string_value, "replacement-consumer"}}} in resource.resource.attributes

      true =
        %{key: "service.instance.id", value: %{value: {:string_value, "replacement-instance-1"}}} in resource.resource.attributes
    end

    {_, operation_scope, operation} =
      Enum.find(traces, fn {_, _, span} -> span.name == "replacement operation" end)

    "replacement_operation" = operation_scope.scope.name
    "https://scope.example" = operation_scope.schema_url
    "" = operation.parent_span_id
    16 = byte_size(operation.trace_id)
    8 = byte_size(operation.span_id)
    false = operation.trace_id == <<0::128>>
    {_, http_scope, http} = Enum.find(traces, fn {_, _, span} -> span.name == "HTTP GET" end)
    "opentelemetry_finch" = http_scope.scope.name
    true = http.trace_id == operation.trace_id
    true = http.parent_span_id == operation.span_id
    true = %{key: "http.target", value: %{value: {:string_value, "/ordinary"}}} in http.attributes

    {_, _, inside} =
      Enum.find(logs, fn {_, _, log} ->
        log.body.value == {:string_value, "replacement inside context"}
      end)

    true = inside.trace_id == operation.trace_id
    true = inside.span_id == operation.span_id

    {_, _, outside} =
      Enum.find(logs, fn {_, _, log} ->
        log.body.value == {:string_value, "replacement outside context"}
      end)

    "" = outside.trace_id
    "" = outside.span_id

    [
      {_, _,
       %{
         name: "replacement.events.count",
         data:
           {:sum,
            %{
              is_monotonic: true,
              aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA,
              data_points: [%{value: {:as_int, 1}}]
            }}
       }}
    ] = metrics

    %{
      signals: counts(requests),
      correlated_logs: true,
      exporter_feedback_spans: 0,
      canonical_exporter_present: false,
      runtime_gpb_present: false
    }
  end

  # Inventory and VM snapshots are descriptive; this fixture is not a benchmark.
  defp inventory(started, before_memory) do
    dependencies = "dependencies.json" |> File.read!() |> :json.decode()
    false = Enum.any?(dependencies, &(&1["name"] == "opentelemetry_exporter"))

    applications =
      Application.loaded_applications()
      |> Enum.map(fn {name, _, version} ->
        %{name: Atom.to_string(name), version: to_string(version)}
      end)
      |> Enum.sort_by(& &1.name)

    %{
      mode: System.fetch_env!("OTLP_SMOKE_DEPENDENCY_SET"),
      sdk_version: to_string(Application.spec(:opentelemetry, :vsn)),
      api_version: to_string(Application.spec(:opentelemetry_api, :vsn)),
      finch_version: to_string(Application.spec(:finch, :vsn)),
      instrumentation_name: "opentelemetry_finch",
      instrumentation_version: to_string(Application.spec(:opentelemetry_finch, :vsn)),
      runtime_applications: applications,
      runtime_application_count: length(applications),
      resolved_dependencies: dependencies,
      resolved_dependency_count: length(dependencies),
      elapsed_ms: System.monotonic_time(:millisecond) - started,
      memory_before_bytes: before_memory,
      memory_after_bytes: :erlang.memory(:total)
    }
  end

  # Emit evidence only after every real-release assertion has succeeded.
  defp publish(report) do
    json = report |> :json.encode() |> IO.iodata_to_binary()

    case System.get_env("OTLP_REPLACEMENT_REPORT") do
      nil ->
        :ok

      path ->
        true = Path.type(path) == :absolute
        File.write!(path, json <> "\n")
    end

    IO.puts("Replacement release proof passed: " <> json)
  end
end

ReplacementProof.run()
