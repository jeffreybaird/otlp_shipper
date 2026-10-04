defmodule OtlpShipper do
  @moduledoc """
  Bounded OTLP/HTTP shipping for Elixir.

  The shared core provides `OtlpShipper.Config`, `OtlpShipper.Resource`,
  `OtlpShipper.Value`, `OtlpShipper.Encoder`, `OtlpShipper.Transport`, and
  `OtlpShipper.Buffer`. Add `OtlpShipper.LogHandler` to your supervision tree
  for Logger export with optional span correlation, or `OtlpShipper.MetricsReporter`
  for bounded Telemetry.Metrics aggregation and delta export. Use
  `OtlpShipper.TraceExporter` with your application's OpenTelemetry SDK and API
  for trace export. See the [migration guide](migration.html) for exporter
  replacement and rollback.

  Resolve configuration before starting a component:

      iex> {:ok, config} = OtlpShipper.Config.new(:logs, service_name: "checkout")
      iex> config.endpoint
      "http://localhost:4318/v1/logs"
  """
end
