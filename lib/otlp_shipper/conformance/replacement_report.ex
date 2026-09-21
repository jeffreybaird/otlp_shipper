defmodule OtlpShipper.Conformance.ReplacementReport do
  @moduledoc false

  @doc false
  @spec verify(map()) :: :ok | {:error, :replacement_report_mismatch}
  # Validate the report schema and internal consistency, not the underlying claims.
  def verify(report) when is_map(report) do
    if versions?(report) and claims?(report) and measurements?(report) and applications?(report),
      do: :ok,
      else: {:error, :replacement_report_mismatch}
  rescue
    _ -> {:error, :replacement_report_mismatch}
  end

  def verify(_), do: {:error, :replacement_report_mismatch}

  # These are the verified SDK/API/instrumentation pair and supported Finch range.
  defp versions?(report) do
    report["mode"] in ["default", "minimum"] and
      report["sdk_version"] == "1.7.0" and report["api_version"] == "1.5.0" and
      report["instrumentation_name"] == "opentelemetry_finch" and
      report["instrumentation_version"] == "0.2.0" and finch?(report["finch_version"])
  end

  # Reject malformed versions before checking the declared dependency range.
  defp finch?(value) when is_binary(value) and byte_size(value) <= 100 do
    case Version.parse(value) do
      {:ok, version} -> Version.match?(version, "~> 0.20")
      :error -> false
    end
  end

  defp finch?(_), do: false

  # Actual release execution produces these claims; synthetic fixtures prove only parsing.
  defp claims?(report) do
    report["correlated_logs"] == true and report["exporter_feedback_spans"] === 0 and
      report["canonical_exporter_present"] == false and report["runtime_gpb_present"] == false and
      signals?(report["signals"])
  end

  # Every signal needs a positive decoded-record count.
  defp signals?(signals) when is_map(signals),
    do: Enum.all?(["logs", "metrics", "traces"], &positive?(signals[&1]))

  defp signals?(_), do: false

  # Measurements are descriptive observations, never performance thresholds or claims.
  defp measurements?(report) do
    is_integer(report["elapsed_ms"]) and report["elapsed_ms"] >= 0 and
      positive?(report["memory_before_bytes"]) and positive?(report["memory_after_bytes"])
  end

  # Counts and memory snapshots must be positive integers.
  defp positive?(value), do: is_integer(value) and value > 0

  # Bound traversal and reject duplicate or forbidden applications before comparing versions.
  defp applications?(%{"runtime_applications" => entries} = report) when is_list(entries) do
    bounded = Enum.take(entries, 257)

    if length(bounded) > 256 or not Enum.all?(bounded, &application_entry?/1) do
      false
    else
      application_versions?(bounded, report)
    end
  end

  defp applications?(_), do: false

  # OTP application versions are not all semantic versions, so preserve their strings.
  defp application_entry?(%{"name" => name, "version" => version}) do
    text?(name) and text?(version) and name not in ["opentelemetry_exporter", "gpb"]
  end

  defp application_entry?(_), do: false

  # Keep application names and version strings nonempty and bounded.
  defp text?(value), do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 256

  # Observed application versions must agree with each report's headline versions.
  defp application_versions?(entries, report) do
    apps = Map.new(entries, &{&1["name"], &1["version"]})

    map_size(apps) == length(entries) and Map.has_key?(apps, "otlp_shipper") and
      Map.get(report, "runtime_application_count", length(entries)) == length(entries) and
      apps["opentelemetry"] == report["sdk_version"] and
      apps["opentelemetry_api"] == report["api_version"] and
      apps["finch"] == report["finch_version"] and
      apps["opentelemetry_finch"] == report["instrumentation_version"]
  end
end
