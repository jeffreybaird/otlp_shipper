# Runs in a separate VM with OTEL_* variables removed by the conformance task.
import Telemetry.Metrics

{:ok, _} = Application.ensure_all_started(:otlp_shipper)

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

try do
  :logger.notice("otlp-shipper-conformance-log", %{conformance: true})

  for value <- [2, 7, 12] do
    :telemetry.execute([:conformance, :events], %{count: 1, value: value}, %{region: "test"})
  end

  :ok = OtlpShipper.MetricsReporter.flush(reporter)
  OtlpShipper.LogHandler.Buffer |> OtlpShipper.Buffer.handle() |> OtlpShipper.Buffer.flush()

  for signal <- [:logs, :metrics] do
    receive do
      {:exported, ^signal, :ok} -> :ok
      {:exported, ^signal, status} -> raise "conformance export failed: #{signal}/#{status}"
    after
      10_000 -> raise "conformance export timed out: #{signal}"
    end
  end
after
  Supervisor.stop(reporter)
  Supervisor.stop(logs)
  :telemetry.detach("otlp-shipper-conformance")
end
