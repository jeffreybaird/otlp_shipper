defmodule OtlpShipper.TraceFixtures do
  @moduledoc false

  @doc false
  def span(overrides \\ %{}) do
    Map.merge(
      %{
        trace_id: 1,
        span_id: 2,
        parent_span_id: nil,
        parent_span_is_remote: false,
        trace_flags: 1,
        tracestate: [{"vendor", "value"}],
        name: "operation",
        kind: :internal,
        start_time: 0,
        end_time: native(10),
        attributes: %{},
        dropped_attributes_count: 0,
        events: [],
        dropped_events_count: 0,
        links: [],
        dropped_links_count: 0,
        status: %{code: :unset, message: ""},
        scope: %{name: "example", version: "1.0", schema_url: "https://schema/scope"}
      },
      overrides
    )
  end

  @doc false
  def resource(overrides \\ %{}) do
    Map.merge(
      %{
        attributes: %{"service.name" => "sdk-service"},
        schema_url: "https://schema/resource",
        dropped_attributes_count: 0
      },
      overrides
    )
  end

  @doc false
  def native(milliseconds), do: System.convert_time_unit(milliseconds, :millisecond, :native)

  @doc false
  def offset, do: System.convert_time_unit(1_700_000_000, :second, :native)

  @doc false
  def request_type, do: :"opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest"

  @doc false
  def response_type, do: :"opentelemetry.proto.collector.trace.v1.ExportTraceServiceResponse"

  @doc false
  def span_type, do: :"opentelemetry.proto.trace.v1.Span"

  @doc false
  def decode(body), do: :otlp_shipper_trace_service.decode_msg(body, request_type())

  @doc false
  def response(rejected, message \\ "") do
    :otlp_shipper_trace_service.encode_msg(
      %{partial_success: %{rejected_spans: rejected, error_message: message}},
      response_type()
    )
  end

  @doc false
  def spans(request) do
    for resource <- request.resource_spans,
        scope <- resource.scope_spans,
        span <- scope.spans,
        do: span
  end
end
