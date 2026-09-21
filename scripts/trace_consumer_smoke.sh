#!/bin/sh
# Verify the actual packaged adapter with and without its optional SDK.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/otlp_trace_compile.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT HUP INT TERM
unset MIX_BUILD_PATH MIX_DEPS_PATH MIX_ENV
cd "$repo_root"
mix hex.build --unpack --output "$probe_dir/package"
export TRACE_SMOKE_PACKAGE="$probe_dir/package"
for sdk_mode in absent present; do
  consumer_dir="$probe_dir/$sdk_mode"
  mkdir -p "$consumer_dir/config"
  export TRACE_PROBE_SDK_MODE="$sdk_mode"
  cat > "$consumer_dir/mix.exs" <<'MIX'
defmodule TraceConsumer.MixProject do
  use Mix.Project
  def project do
    sdk = if System.fetch_env!("TRACE_PROBE_SDK_MODE") == "present",
      do: [{:opentelemetry, "== 1.7.0"}, {:opentelemetry_api, "== 1.5.0"}], else: []
    [app: :trace_consumer, version: "0.0.0", elixir: "~> 1.19",
     deps: [{:otlp_shipper, path: System.fetch_env!("TRACE_SMOKE_PACKAGE")} | sdk]]
  end
  def application, do: [extra_applications: [:logger]]
end
MIX
  cat > "$consumer_dir/config/config.exs" <<'ELIXIR'
import Config
if System.fetch_env!("TRACE_PROBE_SDK_MODE") == "present" do
  config :opentelemetry, traces_exporter: :none
end
ELIXIR
  cat > "$consumer_dir/verify.exs" <<'ELIXIR'
{:ok, _} = Application.ensure_all_started(:trace_consumer)
expected = System.fetch_env!("TRACE_PROBE_SDK_MODE") == "present"
true = Code.ensure_loaded?(:otel_exporter_traces) == expected
true = Code.ensure_loaded?(:otel_tracer) == expected
true = Code.ensure_loaded?(OtlpShipper.TraceExporter) == expected
true = Code.ensure_loaded?(OtlpShipper.TraceSampler) == expected
:non_existing = :code.which(:opentelemetry_exporter)
:non_existing = :code.which(:gpb_compile)

unless expected do
  {:error, :tracing_sdk_unavailable} =
    OtlpShipper.Conformance.run(fn _, _, _ ->
      raise "SDK-absent conformance must not invoke Docker or another command"
    end)
end

# Read one request through an actual release socket without development dependencies.
defmodule TraceReleaseCollector do
  def receive_trace(listener) do
    {:ok, socket} = :gen_tcp.accept(listener, 5000)
    {:ok, {:http_request, :POST, {:abs_path, "/v1/traces"}, _}} = :gen_tcp.recv(socket, 0, 5000)
    length = content_length(socket, nil)
    :ok = :inet.setopts(socket, packet: :raw)
    {:ok, body} = :gen_tcp.recv(socket, length, 5000)
    decoded = :otlp_shipper_trace_service.decode_msg(body,
      :"opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest")
    :ok = :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    :gen_tcp.close(socket)
    decoded
  end

  defp content_length(socket, length) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, :http_eoh} -> length
      {:ok, {:http_header, _, name, _, value}} ->
        next = if String.downcase(to_string(name)) == "content-length",
          do: String.to_integer(to_string(value)), else: length
        content_length(socket, next)
    end
  end
end

if expected do
  ~c"1.7.0" = Application.spec(:opentelemetry, :vsn)
  ~c"1.5.0" = Application.spec(:opentelemetry_api, :vsn)
  {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin, ip: {127, 0, 0, 1}])
  {:ok, {_, port}} = :inet.sockname(listener)
  resource = :otel_resource.create(%{"service.name" => "sdk-release-smoke"}, "https://resource.example")
  batch = %{name: TraceReleaseProvider, resource: resource,
    exporter: {OtlpShipper.TraceExporter, [pool: TraceReleaseFinch,
      endpoint: "http://127.0.0.1:#{port}/v1/traces", timeout: 1000]},
    scheduled_delay_ms: 60000, exporting_timeout_ms: 3000}
  options = %{id_generator: :otel_id_generator,
    sampler: {OtlpShipper.TraceSampler, :always_on},
    processors: [{:otel_batch_processor, batch}], deny_list: []}
  children = [apply(OtlpShipper.TraceExporter, :pool_child_spec, [TraceReleaseFinch]),
    %{id: TraceReleaseProvider, type: :supervisor,
      start: {:otel_tracer_server_sup, :start_link, [TraceReleaseProvider, resource, options]}}]
  {:ok, supervisor} = Supervisor.start_link(children, strategy: :rest_for_one)
  try do
    {:ok, _} = apply(OtlpShipper.TraceExporter, :init, [[pool: TraceReleaseFinch]])
    tracer = :otel_tracer_provider.get_tracer(TraceReleaseProvider, "release-sdk", "1.0", "https://scope.example")
    collector = Task.async(fn -> TraceReleaseCollector.receive_trace(listener) end)
    span = :otel_tracer.start_span(:otel_ctx.new(), tracer, "real SDK release span", %{kind: :client})
    false = :otel_span.is_recording(:otel_span.end_span(span))
    :otel_tracer_provider.force_flush(TraceReleaseProvider)
    %{resource_spans: [%{schema_url: "https://resource.example", resource: sdk_resource,
      scope_spans: [%{scope: %{name: "release-sdk", version: "1.0"}, schema_url: "https://scope.example",
        spans: [%{name: "real SDK release span", kind: :SPAN_KIND_CLIENT, trace_id: trace_id, span_id: span_id}]}]}]} =
      Task.await(collector, 5000)
    true = %{key: "service.name", value: %{value: {:string_value, "sdk-release-smoke"}}} in sdk_resource.attributes
    16 = byte_size(trace_id)
    8 = byte_size(span_id)
    false = trace_id == <<0::128>>
    false = span_id == <<0::64>>
  after
    Supervisor.stop(supervisor)
    :gen_tcp.close(listener)
  end

  # This disposable release VM also proves actual application-version gates.
  {:ok, check_pool} = Finch.start_link(name: TraceVersionCheckFinch)
  {:ok, _} = apply(OtlpShipper.TraceExporter, :init, [[pool: TraceVersionCheckFinch]])
  :ok = Application.stop(:opentelemetry)
  {:ok, original_sdk} = :application.get_all_key(:opentelemetry)
  :ok = Application.unload(:opentelemetry)
  :ok = :application.load({:application, :opentelemetry, Keyword.put(original_sdk, :vsn, ~c"9.9.9")})
  :ignore = apply(OtlpShipper.TraceExporter, :init, [[pool: TraceVersionCheckFinch]])
  :ok = Application.unload(:opentelemetry)
  :ok = :application.load({:application, :opentelemetry, original_sdk})
  {:ok, _} = apply(OtlpShipper.TraceExporter, :init, [[pool: TraceVersionCheckFinch]])
  :ok = Application.stop(:opentelemetry_api)
  {:ok, original_api} = :application.get_all_key(:opentelemetry_api)
  :ok = Application.unload(:opentelemetry_api)
  :ok = :application.load({:application, :opentelemetry_api, Keyword.put(original_api, :vsn, ~c"9.9.9")})
  :ignore = apply(OtlpShipper.TraceExporter, :init, [[pool: TraceVersionCheckFinch]])
  Supervisor.stop(check_pool)
end
IO.puts("Packaged SDK adapter release passed: #{System.fetch_env!("TRACE_PROBE_SDK_MODE")}")
ELIXIR
  cd "$consumer_dir"
  mix deps.get
  MIX_ENV=prod mix compile --warnings-as-errors
  MIX_ENV=prod mix release
  _build/prod/rel/trace_consumer/bin/trace_consumer eval 'Code.eval_file("verify.exs")'
done
