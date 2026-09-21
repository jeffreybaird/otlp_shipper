defmodule OtlpShipper.Encoder do
  @moduledoc "Constructs OTLP export envelopes using generated protobuf encoders."

  @doc """
  Encodes log records, metric messages, or converted trace records.

  Logs and metrics use OTLP message maps under one scope. Traces use
  `TraceRecord.convert/2` results and a native authoritative resource passed to
  `TraceEncoder.encode/2`. Inputs are not raw Logger events or metric definitions.
  Malformed protobuf values return a tagged error without exposing the payload.

      iex> {:ok, resource} = OtlpShipper.Resource.new(service_name: "checkout")
      iex> record = %{body: OtlpShipper.Value.encode("ready")}
      iex> {:ok, bytes} = OtlpShipper.Encoder.encode(:logs, [record], resource)
      iex> is_binary(bytes)
      true
  """
  @spec encode(:logs | :metrics | :traces, [map()], map()) ::
          {:ok, binary()}
          | {:error, :invalid_payload | :invalid_signal | :invalid_resource | :batch_too_large}
  def encode(:traces, items, resource), do: OtlpShipper.TraceEncoder.encode(items, resource)

  def encode(signal, items, resource)
      when signal in [:logs, :metrics] and is_list(items) and is_map(resource) do
    version = :otlp_shipper |> Application.spec(:vsn) |> to_string()
    scope = %{name: "otlp_shipper", version: version}

    {module, type, message} =
      case signal do
        :logs ->
          {:otlp_shipper_logs_service,
           :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest",
           %{
             resource_logs: [
               %{resource: resource, scope_logs: [%{scope: scope, log_records: items}]}
             ]
           }}

        :metrics ->
          {:otlp_shipper_metrics_service,
           :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest",
           %{
             resource_metrics: [
               %{resource: resource, scope_metrics: [%{scope: scope, metrics: items}]}
             ]
           }}
      end

    {:ok, module.encode_msg(message, type, [:verify])}
  rescue
    _ -> {:error, :invalid_payload}
  end

  def encode(signal, _, _) when signal in [:logs, :metrics], do: {:error, :invalid_payload}
  def encode(_, _, _), do: {:error, :invalid_signal}
end
