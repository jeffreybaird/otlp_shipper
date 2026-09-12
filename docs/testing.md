# Testing an Elixir package

## Current commands

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

CI also runs `mix dialyzer`, `mix hex.audit`, `mix docs --warnings-as-errors`, and
`scripts/package_smoke.sh` (Hex build plus a fresh consumer release). Run the full code-commit gate through Dialyzer before committing. For focused iteration use
`mix test test/otlp_shipper_test.exs`; use `mix test --cover` for coverage inspection.
No browser, database, external collector, or production credentials are needed.
The suite starts an isolated loopback collector.

## Test layers

| Behavior | Default proof |
| --- | --- |
| Pure public transformations | Doctests and ExUnit boundary cases |
| Public operation and errors | ExUnit tests through the public interface |
| External client | Local protocol fixture/server and request assertions |
| Process lifecycle | Supervised ExUnit integration tests |
| Package installation | Fresh consumer using unpacked package contents |

Every new behavior and meaningful branch needs coverage. Acceptance tests enumerate
consumer success and failure pathways. Gherkin, Phoenix, Wallaby, Ecto sandboxing,
and ExMachina are not required for a library. Use simple fixture builders initially.

Test the client itself at its actual transport boundary: destination, method where
applicable, headers, encoding, response parsing, timeouts, and mapped errors. A mock
of the client only proves its caller. Use synthetic data and local endpoints; fail
unexpected external requests. Live interoperability checks, if needed, are separate,
explicitly configured checks and cannot substitute for deterministic tests.

## Isolation and concurrency

Use `async: true` only when tests have no shared mutable state. Prefer per-test
options and unique process names. Tests that change application environment or
other global state must run synchronously and restore prior values with `on_exit`.

Use `start_supervised!` for owned processes. Clean up fixture servers, temporary
files, handlers, and connections on failure too. Prefer `assert_receive`, monitors,
and bounded observable waits over arbitrary sleeps. Inject clocks when elapsed time
is part of the domain contract. If Mox is introduced, verify expectations on exit
and explicitly allow spawned callers; avoid global mock mode in async tests.

For affected process behavior cover startup validation, normal operation, overload,
flush, retry limits, restart, and bounded shutdown. Prove no external side effect
occurs on rejected input. Test multiple instances only if that is a supported contract.
For retried sends, distinguish duplicate safety from returning the same result twice.

Test our event names, attributes, redaction, and feedback-loop prevention when
instrumentation is part of the feature; do not retest an upstream SDK's internals.

## Compatibility and release checks

The single pinned CI toolchain does not establish the whole declared version range.
Before release, exercise the oldest supported Elixir/OTP combination and the current
supported combination, plus relevant dependency bounds. Record tested versions and
any gaps. PLAN.md requires Dialyzer and a clean `mix hex.audit` for release. Both are now
configured in CI.
Credo remains optional. There is no Marquee verification alias here.

Follow [submission/build.md](submission/build.md) for the package consumer check.
A source checkout passing tests does not prove an archive contains everything a
consumer needs. Report checks as passed, failed, blocked, skipped, or unrun accurately.

## Planned OTLP acceptance suite

Build the local Bandit/Plug fake collector in Phase 0. Accept `/v1/logs` and
`/v1/metrics`, decode generated protobuf in test support, and assert full payload
contracts. Runtime encoding-only scope does not prohibit a test decoder.

For logs, cover severity, structured bodies, metadata filtering, truncation counts,
16-byte trace and 8-byte span IDs inside a span, and empty IDs without tracing.
Exercise operation with the optional tracing dependency absent. Prove a 10,000-event
burst stays bounded at ingress as well as in retained state and reports drops.
Cover handler recovery, recursion filtering, 401 failures, gzip, timeout, and a
503/503/200 sequence that delivers one batch to the accepting fixture.

For metrics, assert exact counters, sums, last values and histogram buckets, delta
reset across intervals, transformed tags and units, and no points for idle series.
Reject summaries at startup with a tagged reason and documentation naming
`distribution` as the alternative. Test handler detach/cleanup and any series cap.

Keep configuration/endpoint precedence, resource validation, value conversion,
severity mapping, and histogram layout pure and doctested. Cover `Retry-After`,
retry exhaustion, drop telemetry, and bounded shutdown in transport/process tests.

Phase 3 adds the planned opt-in real OTel Collector check using Docker, excluded
from default CI. Record it separately from fake-collector success. Recheck the
upstream logs replacement before Phase 1 as required by PLAN.md.

## Phase 0 verification — September 12, 2026

- Local Elixir 1.19.5 / OTP 29.0.1: formatting, warnings-as-errors compile,
  37 ExUnit tests and 10 doctests, Dialyzer, and ExDoc passed.
- `mix hex.audit`: no retired dependencies found; this is not a comprehensive
  vulnerability scan.
- Clean consumer compile and release encoding passed with the optional tracing API
  absent and gpb excluded from runtime. The compiler explicitly loads syntax_tools
  and writes generated BEAM files to the active dependency compile directory.
- The test collector exercises actual loopback HTTP and generated decoding, not a
  production collector. Real OTel Collector conformance remains Phase 3.
- CI is configured to run the package-consumer regression check and the pinned
  `.tool-versions` pair. Check the Phase 0 PR for the remote CI result.
