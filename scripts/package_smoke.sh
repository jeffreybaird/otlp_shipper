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
     deps: [{:otlp_shipper, path: System.fetch_env!("OTLP_SMOKE_PACKAGE")}]]
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
:non_existing = :code.which(:otel_tracer)
{:ok, apps} = :application.get_key(:otlp_shipper, :applications)
false = :gpb in apps
IO.puts("Package release smoke passed without gpb or optional tracing modules")
ELIXIR
mix deps.get
MIX_ENV=prod mix compile --warnings-as-errors
MIX_ENV=prod mix release
_build/prod/rel/consumer/bin/consumer eval 'Code.eval_file("smoke.exs")'
