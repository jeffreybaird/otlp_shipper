#!/bin/sh
# Prove the proposed optional SDK dependency edge in fresh production releases.
set -eu
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/otlp_trace_compile.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT HUP INT TERM
unset MIX_BUILD_PATH MIX_DEPS_PATH MIX_ENV
mkdir -p "$probe_dir/adapter/lib"
cat > "$probe_dir/adapter/mix.exs" <<'MIX'
defmodule Phase4Adapter.MixProject do
  use Mix.Project
  def project do
    [app: :phase4_adapter, version: "0.0.0", elixir: "~> 1.19",
     deps: [{:opentelemetry, "== 1.7.0", optional: true}]]
  end
  def application, do: []
end
MIX
cat > "$probe_dir/adapter/lib/exporter.ex" <<'ELIXIR'
# This development fixture proves compilation order, not trace export behavior.
if Code.ensure_loaded?(:otel_exporter_traces) do
  defmodule Phase4Adapter.Exporter do
    @moduledoc false
    @behaviour :otel_exporter_traces
    @impl true
    def init(state), do: {:ok, state}
    @impl true
    def export(_table, _resource, _state), do: :ok
    @impl true
    def shutdown(_state), do: :ok
  end
end
ELIXIR
for sdk_mode in absent present; do
  consumer_dir="$probe_dir/$sdk_mode"
  mkdir -p "$consumer_dir/config"
  cp -R "$probe_dir/adapter" "$consumer_dir/adapter"
  export TRACE_PROBE_SDK_MODE="$sdk_mode"
  cat > "$consumer_dir/mix.exs" <<'MIX'
defmodule Phase4Consumer.MixProject do
  use Mix.Project
  def project do
    sdk = if System.fetch_env!("TRACE_PROBE_SDK_MODE") == "present",
      do: [{:opentelemetry, "== 1.7.0"}, {:opentelemetry_api, "== 1.5.0"}], else: []
    [app: :phase4_consumer, version: "0.0.0", elixir: "~> 1.19",
     deps: [{:phase4_adapter, path: "adapter"} | sdk]]
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
expected = System.fetch_env!("TRACE_PROBE_SDK_MODE") == "present"
true = Code.ensure_loaded?(:otel_exporter_traces) == expected
true = Code.ensure_loaded?(:otel_tracer) == expected
true = Code.ensure_loaded?(Phase4Adapter.Exporter) == expected
if expected do
  ~c"1.7.0" = Application.spec(:opentelemetry, :vsn)
  ~c"1.5.0" = Application.spec(:opentelemetry_api, :vsn)
  {:ok, :state} = apply(Phase4Adapter.Exporter, :init, [:state])
end
:non_existing = :code.which(:opentelemetry_exporter)
IO.puts("Fresh optional SDK release passed: #{System.fetch_env!("TRACE_PROBE_SDK_MODE")}")
ELIXIR
  cd "$consumer_dir"
  mix deps.get
  MIX_ENV=prod mix compile --warnings-as-errors
  MIX_ENV=prod mix release
  _build/prod/rel/phase4_consumer/bin/phase4_consumer eval 'Code.eval_file("verify.exs")'
done
