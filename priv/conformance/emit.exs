# Runs in a separate VM with OTEL_* variables removed by the conformance task.
import Telemetry.Metrics

# This disposable consumer configures its SDK explicitly before starting applications.
Application.put_env(:opentelemetry, :traces_exporter, :none)
{:ok, _} = Application.ensure_all_started(:otlp_shipper)
{:ok, _} = Application.ensure_all_started(:opentelemetry)

[endpoint] = System.argv()
owner = self()

:ok =
  :telemetry.attach(
    "otlp-shipper-conformance",
    [:otlp_shipper, :export, :stop],
    fn _, _, metadata, target -> send(target, {:exported, metadata.signal, metadata.status}) end,
    owner
  )

options = [
  service_name: "otlp-shipper-conformance",
  base_endpoint: endpoint,
  headers: [],
  compression: :gzip,
  flush_ms: 60_000,
  timeout: 5_000,
  max_retries: 0
]

metrics = [
  counter("conformance.events.count", tags: [:region]),
  sum("conformance.events.total", measurement: :value),
  last_value("conformance.events.current", measurement: :value),
  distribution("conformance.events.histogram",
    measurement: :value,
    reporter_options: [buckets: [5, 10]]
  )
]

{:ok, logs} = OtlpShipper.LogHandler.start_link(options)
{:ok, reporter} = OtlpShipper.MetricsReporter.start_link([metrics: metrics] ++ options)

resource =
  :otel_resource.create(
    %{"service.name" => "otlp-shipper-conformance"},
    "https://otlp-shipper.dev/conformance/resource"
  )

batch = %{
  name: ConformanceTraces,
  resource: resource,
  exporter:
    {OtlpShipper.TraceExporter,
     [
       pool: ConformanceTraceFinch,
       base_endpoint: endpoint,
       headers: [],
       compression: :gzip,
       timeout: 5_000,
       max_retries: 0
     ]},
  scheduled_delay_ms: 60_000,
  exporting_timeout_ms: 7_000
}

provider = %{
  id_generator: :otel_id_generator,
  sampler: {OtlpShipper.TraceSampler, :always_on},
  processors: [{:otel_batch_processor, batch}],
  deny_list: []
}

children = [
  OtlpShipper.TraceExporter.pool_child_spec(ConformanceTraceFinch),
  %{
    id: ConformanceTraces,
    type: :supervisor,
    start: {:otel_tracer_server_sup, :start_link, [ConformanceTraces, resource, provider]}
  }
]

{:ok, traces} = Supervisor.start_link(children, strategy: :rest_for_one)

tracer =
  :otel_tracer_provider.get_tracer(
    ConformanceTraces,
    "conformance.sdk",
    "1.0",
    "https://otlp-shipper.dev/conformance/scope"
  )

try do
  :otel_tracer.with_span(tracer, "otlp-shipper-conformance-root", %{kind: :internal}, fn _ ->
    :otel_tracer.with_span(tracer, "otlp-shipper-conformance-child", %{kind: :client}, fn child ->
      :otel_span.set_attribute(child, "conformance.span", true)
      :otel_span.set_status(child, :opentelemetry.status(:error, "synthetic failure"))
      :otel_span.add_event(child, "conformance-event", %{"conformance" => true})
      :logger.notice("otlp-shipper-conformance-log", %{conformance: true})
    end)
  end)

  remote = :otel_tracer.from_remote_span(0x43, 0x42, 1)
  remote_context = :otel_tracer.set_current_span(:otel_ctx.new(), remote)

  :otel_tracer.with_span(
    remote_context,
    tracer,
    "otlp-shipper-conformance-remote",
    %{kind: :server},
    fn _ -> :ok end
  )

  :ok = :otel_tracer_provider.force_flush(ConformanceTraces)

  for value <- [2, 7, 12] do
    :telemetry.execute([:conformance, :events], %{count: 1, value: value}, %{region: "test"})
  end

  :ok = OtlpShipper.MetricsReporter.flush(reporter)
  OtlpShipper.LogHandler.Buffer |> OtlpShipper.Buffer.handle() |> OtlpShipper.Buffer.flush()

  for signal <- [:logs, :metrics, :traces] do
    receive do
      {:exported, ^signal, :ok} -> :ok
      {:exported, ^signal, status} -> raise "conformance export failed: #{signal}/#{status}"
    after
      10_000 -> raise "conformance export timed out: #{signal}"
    end
  end
after
  Supervisor.stop(traces)
  Supervisor.stop(reporter)
  Supervisor.stop(logs)
  :telemetry.detach("otlp-shipper-conformance")
end
