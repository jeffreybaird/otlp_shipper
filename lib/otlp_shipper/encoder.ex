defmodule OtlpShipper.Encoder do
  @moduledoc "Constructs OTLP export envelopes using generated protobuf encoders."

  @doc """
  Encodes log records or metric messages under a single resource and scope.

  Inputs are OTLP message maps, not raw Logger events or metric definitions.
  Malformed protobuf values return a tagged error without exposing the payload.

      iex> {:ok, resource} = OtlpShipper.Resource.new(service_name: "checkout")
      iex> record = %{body: OtlpShipper.Value.encode("ready")}
      iex> {:ok, bytes} = OtlpShipper.Encoder.encode(:logs, [record], resource)
      iex> is_binary(bytes)
      true
  """
  @spec encode(:logs | :metrics, [map()], map()) ::
          {:ok, binary()} | {:error, :invalid_payload | :invalid_signal}
  def encode(signal, items, resource)
      when signal in [:logs, :metrics] and is_list(items) and is_map(resource) do
    scope = %{name: "otlp_shipper", version: "0.1.0"}

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
