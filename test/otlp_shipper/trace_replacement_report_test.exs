defmodule OtlpShipper.TraceReplacementReportTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias OtlpShipper.Conformance

  # These synthetic inputs test report validation, not actual release behavior.
  @report Path.expand("../fixtures/conformance/replacement-report-synthetic.json", __DIR__)
          |> File.read!()
          |> :json.decode()

  test "TRP-04 validates complete evidence-report structure for default and minimum consumers" do
    assert Conformance.verify_replacement_report(@report) == :ok
    assert Conformance.verify_replacement_report(Map.put(@report, "mode", "minimum")) == :ok
  end

  test "TRP-04 rejects missing or false replacement claims and unsupported versions" do
    for key <- Map.keys(@report) -- ["runtime_application_count"] do
      assert Conformance.verify_replacement_report(Map.delete(@report, key)) ==
               {:error, :replacement_report_mismatch}
    end

    for {key, value} <- [
          {"mode", "unsupported"},
          {"sdk_version", "1.6.0"},
          {"api_version", "1.4.0"},
          {"finch_version", "not-a-version"},
          {"instrumentation_name", "fake_instrumentation"},
          {"instrumentation_version", "0.1.0"},
          {"correlated_logs", false},
          {"exporter_feedback_spans", 1},
          {"canonical_exporter_present", true},
          {"runtime_gpb_present", true},
          {"elapsed_ms", -1},
          {"memory_before_bytes", 0},
          {"memory_after_bytes", "100"},
          {"runtime_application_count", 99}
        ] do
      assert Conformance.verify_replacement_report(Map.put(@report, key, value)) ==
               {:error, :replacement_report_mismatch}
    end

    for signal <- ["logs", "metrics", "traces"], value <- [0, -1, "1"] do
      invalid = put_in(@report, ["signals", signal], value)

      assert Conformance.verify_replacement_report(invalid) ==
               {:error, :replacement_report_mismatch}
    end
  end

  test "TRP-04 report booleans cannot contradict actual runtime application observations" do
    for forbidden <- ["opentelemetry_exporter", "gpb"] do
      applications =
        @report["runtime_applications"] ++ [%{"name" => forbidden, "version" => "1.0.0"}]

      invalid =
        @report
        |> Map.put("runtime_applications", applications)
        |> Map.put("runtime_application_count", length(applications))

      assert Conformance.verify_replacement_report(invalid) ==
               {:error, :replacement_report_mismatch}
    end

    applications =
      Enum.map(@report["runtime_applications"], fn
        %{"name" => "opentelemetry"} = app -> Map.put(app, "version", "1.6.0")
        app -> app
      end)

    assert Conformance.verify_replacement_report(
             Map.put(@report, "runtime_applications", applications)
           ) ==
             {:error, :replacement_report_mismatch}

    assert Conformance.verify_replacement_report(%{}) == {:error, :replacement_report_mismatch}
    assert Conformance.verify_replacement_report(nil) == {:error, :replacement_report_mismatch}
  end
end
