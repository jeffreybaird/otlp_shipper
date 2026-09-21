defmodule OtlpShipper.ScopeVersionTest do
  use ExUnit.Case, async: true

  alias OtlpShipper.{Conformance, Encoder, TraceFixtures, TraceRecord}

  @collector_fixture Path.expand("../fixtures/conformance/collector-0.160.0.txt", __DIR__)

  test "SCOPE-01 logs identify the installed application version" do
    assert {:ok, bytes} = Encoder.encode(:logs, [%{severity_number: 9}], %{attributes: []})

    decoded =
      :otlp_shipper_logs_service.decode_msg(
        bytes,
        :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest"
      )

    assert [%{scope_logs: [%{scope: scope}]}] = decoded.resource_logs
    assert scope.name == "otlp_shipper"
    assert scope.version == application_version()
  end

  test "SCOPE-01 metrics identify the installed application version" do
    assert {:ok, bytes} = Encoder.encode(:metrics, [%{name: "active"}], %{attributes: []})

    decoded =
      :otlp_shipper_metrics_service.decode_msg(
        bytes,
        :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest"
      )

    assert [%{scope_metrics: [%{scope: scope}]}] = decoded.resource_metrics
    assert scope.name == "otlp_shipper"
    assert scope.version == application_version()
  end

  test "SCOPE-02 trace scopes retain original instrumentation versions" do
    original = %{name: "consumer.instrumentation", version: "7.8.9", schema_url: ""}
    input = TraceFixtures.span(%{scope: original})
    assert {:ok, record} = TraceRecord.convert(input, TraceFixtures.offset())
    assert {:ok, bytes} = Encoder.encode(:traces, [record], TraceFixtures.resource())
    assert [%{scope_spans: [%{scope: scope}]}] = TraceFixtures.decode(bytes).resource_spans
    assert scope.name == original.name
    assert scope.version == original.version
  end

  test "SCOPE-03 conformance accepts the current application scope version" do
    assert :ok = Conformance.verify(collector_evidence(application_version()))
  end

  test "SCOPE-04 conformance rejects incorrect and prefix-matching versions" do
    for version <- ["0.1.0", application_version() <> ".999", "999.0.0"] do
      assert {:error, :collector_output_mismatch} =
               Conformance.verify(collector_evidence(version))
    end
  end

  defp application_version, do: :otlp_shipper |> Application.spec(:vsn) |> to_string()

  # The recorded Collector fixture is historical. Change only its shipper scope
  # version to exercise current-version validation without rewriting that evidence.
  defp collector_evidence(version) do
    @collector_fixture
    |> File.read!()
    |> String.replace(
      "InstrumentationScope otlp_shipper 0.1.0",
      "InstrumentationScope otlp_shipper #{version}"
    )
  end
end
