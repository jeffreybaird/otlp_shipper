defmodule OtlpShipper.Acceptance.ScopeVersionSteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions
  alias OtlpShipper.{Conformance, Encoder, TraceFixtures, TraceRecord}

  @collector_fixture Path.expand("../../test/fixtures/conformance/collector-0.160.0.txt", __DIR__)

  given_("the installed shipper application version", fn world ->
    Map.put(world, :shipper_version, application_version())
  end)

  when_("I encode a shipper {string} scope", fn world, signal ->
    scope = encode_scope(signal)
    Map.put(world, :shipper_scope, scope)
  end)

  then_("the encoded scope identifies the installed shipper version", fn world ->
    assert world.shipper_scope.name == "otlp_shipper"
    assert world.shipper_scope.version == world.shipper_version
    world
  end)

  given_("a trace scope named {string} at version {string}", fn world, name, version ->
    Map.put(world, :original_scope, %{name: name, version: version, schema_url: ""})
  end)

  when_("I encode that original trace scope", fn world ->
    input = TraceFixtures.span(%{scope: world.original_scope})
    assert {:ok, record} = TraceRecord.convert(input, TraceFixtures.offset())
    assert {:ok, bytes} = Encoder.encode(:traces, [record], TraceFixtures.resource())
    assert [%{scope_spans: [%{scope: scope}]}] = TraceFixtures.decode(bytes).resource_spans
    Map.put(world, :encoded_trace_scope, scope)
  end)

  then_("the original trace scope name and version are preserved", fn world ->
    assert world.encoded_trace_scope.name == world.original_scope.name
    assert world.encoded_trace_scope.version == world.original_scope.version
    world
  end)

  given_("Collector evidence using the installed shipper scope version", fn world ->
    # Normalize only the historical fixture's shipper scope version; all recorded
    # payload values remain unchanged and continue to be checked by the verifier.
    output =
      @collector_fixture
      |> File.read!()
      |> String.replace(
        "InstrumentationScope otlp_shipper 0.1.0",
        "InstrumentationScope otlp_shipper #{application_version()}"
      )

    Map.put(world, :shipper_collector_output, output)
  end)

  when_("I validate the shipper scope evidence", fn world ->
    Map.put(world, :shipper_verification, Conformance.verify(world.shipper_collector_output))
  end)

  then_("the shipper scope evidence is accepted", fn world ->
    assert world.shipper_verification == :ok
    world
  end)

  when_("I replace the shipper scope version with an incorrect version", fn world ->
    output =
      String.replace(
        world.shipper_collector_output,
        "InstrumentationScope otlp_shipper #{application_version()}",
        "InstrumentationScope otlp_shipper 999.0.0"
      )

    Map.put(world, :shipper_verification, Conformance.verify(output))
  end)

  then_("the shipper scope evidence is rejected", fn world ->
    assert world.shipper_verification == {:error, :collector_output_mismatch}
    world
  end)

  defp application_version, do: :otlp_shipper |> Application.spec(:vsn) |> to_string()

  defp encode_scope("logs") do
    assert {:ok, bytes} = Encoder.encode(:logs, [%{severity_number: 9}], %{attributes: []})

    decoded =
      :otlp_shipper_logs_service.decode_msg(
        bytes,
        :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest"
      )

    [%{scope_logs: [%{scope: scope}]}] = decoded.resource_logs
    scope
  end

  defp encode_scope("metrics") do
    assert {:ok, bytes} = Encoder.encode(:metrics, [%{name: "active"}], %{attributes: []})

    decoded =
      :otlp_shipper_metrics_service.decode_msg(
        bytes,
        :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest"
      )

    [%{scope_metrics: [%{scope: scope}]}] = decoded.resource_metrics
    scope
  end
end
