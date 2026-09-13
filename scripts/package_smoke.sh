#!/bin/sh
# Exercise the package as a dependency, then without Mix/build tools at runtime.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
smoke_dir=$(mktemp -d "${TMPDIR:-/tmp}/otlp_shipper.smoke.XXXXXX")
trap 'rm -rf "$smoke_dir"' EXIT HUP INT TERM

cd "$repo_root"
mix hex.build --unpack --output "$smoke_dir/package"
mkdir -p "$smoke_dir/consumer"
cd "$smoke_dir/consumer"
unset MIX_BUILD_PATH MIX_DEPS_PATH MIX_ENV
export OTLP_SMOKE_PACKAGE="$smoke_dir/package"
cat > mix.exs <<'MIX'
defmodule Consumer.MixProject do
  use Mix.Project
  def project do
    [app: :consumer, version: "0.1.0", elixir: "~> 1.19",
     deps: [{:otlp_shipper, path: System.fetch_env!("OTLP_SMOKE_PACKAGE")}] ++ compatibility_deps()]
  end
  defp compatibility_deps do
    minimum = [{:finch, "== 0.20.0"}, {:telemetry, "== 1.3.0"},
      {:telemetry_metrics, "== 1.1.0"}, {:gpb, "== 4.21.7", runtime: false}]
    case System.get_env("OTLP_SMOKE_DEPENDENCY_SET") do
      nil -> []
      "minimum" -> minimum
      "minimum_with_tracing" -> [{:opentelemetry_api, "== 1.3.0"} | minimum]
      _ -> raise "Unknown smoke dependency set"
    end
  end
  def application, do: [extra_applications: [:logger]]
end
MIX
cat > smoke.exs <<'ELIXIR'
{:ok, _} = Application.ensure_all_started(:consumer)
{:ok, config} = OtlpShipper.Config.new(:logs, service_name: "release-smoke")
{:ok, body} = OtlpShipper.Encoder.encode(:logs,
  [%{body: OtlpShipper.Value.encode("release works")}], config.resource)
true = byte_size(body) > 0
:non_existing = :code.which(:gpb_compile)
tracing? = System.get_env("OTLP_SMOKE_DEPENDENCY_SET") == "minimum_with_tracing"
^tracing? = Code.ensure_loaded?(:otel_tracer)
{:ok, apps} = :application.get_key(:otlp_shipper, :applications)
false = :gpb in apps
defmodule ReleaseLogCollector do
  def receive_record(listener) do
    {:ok, socket} = :gen_tcp.accept(listener, 5000)
    {:ok, {:http_request, :POST, {:abs_path, "/v1/logs"}, _}} = :gen_tcp.recv(socket, 0, 5000)
    length = content_length(socket, nil)
    :ok = :inet.setopts(socket, packet: :raw)
    {:ok, body} = :gen_tcp.recv(socket, length, 5000)
    decoded = :otlp_shipper_logs_service.decode_msg(body,
      :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest")
    :ok = :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    :gen_tcp.close(socket)
    hd(hd(hd(decoded.resource_logs).scope_logs).log_records)
  end

  def receive_metrics(listener) do
    {:ok, socket} = :gen_tcp.accept(listener, 5000)
    {:ok, {:http_request, :POST, {:abs_path, "/v1/metrics"}, _}} = :gen_tcp.recv(socket, 0, 5000)
    length = content_length(socket, nil)
    :ok = :inet.setopts(socket, packet: :raw)
    {:ok, body} = :gen_tcp.recv(socket, length, 5000)
    decoded = :otlp_shipper_metrics_service.decode_msg(body,
      :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest")
    :ok = :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    :gen_tcp.close(socket)
    hd(hd(hd(decoded.resource_metrics).scope_metrics).metrics)
  end

  defp content_length(socket, length) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, :http_eoh} -> length
      {:ok, {:http_header, _, name, _, value}} ->
        length = if String.downcase(to_string(name)) == "content-length",
          do: String.to_integer(to_string(value)), else: length
        content_length(socket, length)
    end
  end
end

{:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin, ip: {127, 0, 0, 1}])
{:ok, {_, port}} = :inet.sockname(listener)
collector = Task.async(fn -> ReleaseLogCollector.receive_record(listener) end)
{:ok, supervisor} = OtlpShipper.LogHandler.start_link(service_name: "release-smoke",
  endpoint: "http://127.0.0.1:#{port}/v1/logs", max_batch: 1)
:logger.log(:notice, "release log from consumer")
record = Task.await(collector, 5000)
%{body: %{value: {:string_value, "release log from consumer"}}, trace_id: "", span_id: ""} = record
collector = Task.async(fn -> ReleaseLogCollector.receive_metrics(listener) end)
metric = Telemetry.Metrics.counter("release.events.count")
{:ok, reporter} = OtlpShipper.MetricsReporter.start_link(metrics: [metric],
  service_name: "release-smoke", endpoint: "http://127.0.0.1:#{port}/v1/metrics")
:telemetry.execute([:release, :events], %{count: 1})
:ok = OtlpShipper.MetricsReporter.flush(reporter)
%{name: "release.events.count", data: {:sum, %{is_monotonic: true,
  aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA,
  data_points: [%{value: {:as_int, 1}}]}}} = Task.await(collector, 5000)
Supervisor.stop(reporter)
Supervisor.stop(supervisor)
:gen_tcp.close(listener)
IO.puts("Package release smoke passed: HTTP logs and metrics without runtime gpb (tracing API presence checked)")
ELIXIR
mix deps.get
MIX_ENV=prod mix compile --warnings-as-errors
MIX_ENV=prod mix release
_build/prod/rel/consumer/bin/consumer eval 'Code.eval_file("smoke.exs")'
