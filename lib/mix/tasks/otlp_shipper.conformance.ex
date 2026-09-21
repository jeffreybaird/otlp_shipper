defmodule Mix.Tasks.OtlpShipper.Conformance do
  use Mix.Task
  @shortdoc "Verifies logs, metrics, and traces against a pinned Docker Collector"
  @moduledoc """
  Runs opt-in OTLP/HTTP conformance against OpenTelemetry Collector 0.160.0.

      mix otlp_shipper.conformance

  Requires a running local Docker engine and the image printed in the README
  pulled beforehand. No arguments are accepted. Publishes an ephemeral loopback
  port, sends synthetic gzip logs, all four metric types, and SDK spans from a separate VM,
  and checks the Collector's detailed debug output, parent relationships, and log
  correlation. The optional supported tracing SDK/API pair must be installed. The child VM receives no
  inherited `OTEL_*` configuration. The task removes its own container on exit;
  interrupted/killed VMs may require manual cleanup of the printed container name.
  It does not run in the default test suite or CI.
  """

  @impl Mix.Task
  def run([]) do
    Mix.Task.run("compile")

    case OtlpShipper.Conformance.run() do
      :ok ->
        Mix.shell().info(
          "Collector conformance passed: gzip logs, counter, sum, gauge, histogram, SDK traces and correlation"
        )

      {:error, reason} ->
        Mix.raise("Collector conformance failed: #{inspect(reason)}")
    end
  end

  def run(_), do: Mix.raise("Usage: mix otlp_shipper.conformance")
end
