#!/bin/sh
# Prove replacement from a fresh package and production release, never the checkout.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mode=${OTLP_SMOKE_DEPENDENCY_SET:-default}
case "$mode" in default|minimum) ;; *) echo "Expected default or minimum dependency set" >&2; exit 2 ;; esac
smoke_dir=$(mktemp -d "${TMPDIR:-/tmp}/otlp_replacement.XXXXXX")
trap 'rm -rf "$smoke_dir"' EXIT HUP INT TERM
unset MIX_BUILD_PATH MIX_DEPS_PATH MIX_ENV
export OTLP_SMOKE_DEPENDENCY_SET="$mode"
export OTLP_REPLACEMENT_PACKAGE="$smoke_dir/package"
cd "$repo_root"
mix hex.build --unpack --output "$OTLP_REPLACEMENT_PACKAGE"
mkdir -p "$smoke_dir/consumer"
cp "$repo_root/scripts/fixtures/trace_replacement/"* "$smoke_dir/consumer/"
cd "$smoke_dir/consumer"
mix deps.get
MIX_ENV=prod mix compile --warnings-as-errors
MIX_ENV=prod mix run --no-start inventory.exs
MIX_ENV=prod mix release
_build/prod/rel/replacement_consumer/bin/replacement_consumer eval 'Code.eval_file("verify.exs")'
