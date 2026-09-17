# Testing an Elixir package

## Current commands

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
MIX_ENV=test mix cucumber
mix credo --strict
```

CI also runs `mix dialyzer`, `mix hex.audit`, `mix docs --warnings-as-errors`, and
`scripts/package_smoke.sh` (Hex build plus a fresh consumer release). Run the full code-commit gate through Dialyzer before committing. For focused iteration use
`mix test test/otlp_shipper_test.exs`; use `mix test --cover` for coverage inspection.
No browser, database, external collector, or production credentials are needed.
The suite starts an isolated loopback collector. Strict Credo analysis is required
before code commits and runs in both CI toolchain jobs before package checks.
Resolve findings in the code; do not disable checks, add exclusions, or mask failures
to make the gate pass.

## Test layers

| Behavior | Default proof |
| --- | --- |
| Pure public transformations | Doctests and ExUnit boundary cases |
| Public operation and errors | ExUnit tests through the public interface |
| External client | Local protocol fixture/server and request assertions |
| Process lifecycle | Supervised ExUnit integration tests |
| Package installation | Fresh consumer using unpacked package contents |

Every new behavior and meaningful branch needs coverage. Acceptance tests enumerate
consumer success and failure pathways. Write Gherkin specifications under
`docs/features/` before implementing new behavior. Execute new Elixir acceptance
features with CucumberEx, with ExUnit unit/integration tests proving lower-level
boundaries. Map every scenario ID to its step definitions and relevant ExUnit tests
(or the harness's Python tests for tooling). CucumberEx is a test-only dependency;
it does not enter consumer releases. See
[codex-agents.md](codex-agents.md) for the red/green handoff and evidence format.
Phoenix, Wallaby, Ecto sandboxing, and ExMachina are not required.

### Executable Gherkin

Run `MIX_ENV=test mix cucumber` alongside `mix test`. Both CI toolchain jobs run
this separate acceptance check. `config/config.exs` configures CucumberEx with
`strict: true`, so undefined or pending steps fail the check.

The initial executable feature is `docs/features/cucumberex.feature`. Place step
definition modules under `features/step_definitions/` and register each future
executable feature in CucumberEx's `paths` list in `config/config.exs`.
Keep that list explicit: historical feature specifications, including the Python
agent-harness scenarios, remain specifications mapped to their existing tests;
they are not currently executable CucumberEx features. Do not add them to discovery
until their step definitions implement the scenarios.

Do not change a test, helper, fixture, doctest, or discovery setting to conceal an
implementation defect. Compare expectation changes with the requested contract;
fix defective code first. Authorized contract changes, stronger assertions,
additional coverage, formatting, renames, and contract-preserving refactors do not
need separate approval. Ask for review of an unresolved contract change rather
than adapting expectations to observed output. Never suppress static-analysis
diagnostics or mask a failed required check to make verification pass. A necessary
analysis exception requires explicit human authorization. See [guardrail scope
and limitations](agent-guardrails.md).
Run checks with source frozen; stale green results do not validate a later edit.

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
`mix credo --strict` is also required for release readiness. There is no Marquee
verification alias here.

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

Collector/process assertions allow up to one second for message delivery on shared
CI runners. This addresses the observed first-request timeout at ExUnit's default
100 ms; payload assertions and explicit transport deadlines are unchanged. No test
retry or skip is enabled.

## Phase 1 verification — September 12, 2026

Local Elixir 1.19.5 / OTP 29.0.1 checks cover 60 tests and 13 doctests, including
real SDK span correlation, no IDs after detach, 503/503/200 retry delivery, gzip,
401 telemetry and filtered diagnostics, a 10,000-event bounded Logger burst, worker/
buffer/registration/pool recovery, shutdown flush, and independent instances.
The SDK is test-only and its trace exporter is disabled. Original Phase 0 tests
remain intact. The recorded recipe fixture is copied unchanged and compared at
the record level; scope identity and attribute ordering intentionally differ.

The clean consumer release also starts the handler and delivers a real log over
loopback HTTP while both tracing API and gpb are absent at runtime. Guarded optional
API references have targeted compile annotations so absent tracing does not produce
undefined-module warnings. ExDoc, Dialyzer, formatting, warnings-as-errors compile,
and Hex retirement audit run with the standard gate. Verify the final Phase 1 PR
head's CI result separately; real Collector conformance remains Phase 3.

## Phase 2 verification — September 12, 2026

The suite now covers 82 tests and 19 doctests. New tests assert exact counts, sums,
gauges, histogram buckets and boundaries, interval reset and idle behavior, tag
transformation, unit conversion, unsupported definitions, series/ingress limits,
concurrent producers, retry/failure isolation, final shutdown snapshot, independent
instances, and worker/buffer/registration recovery. A 10,000-event burst with a
10-sample ingress cap reports exactly 9990 dropped observations. Old timer tokens
and exporter/callback feedback are exercised explicitly.

Precision and memory regression tests demonstrate that histogram bounds cannot
collapse to identical doubles and retained tag strings cannot keep huge source
binaries alive. Prior phase tests remain intact. The package smoke also delivers
an exact delta counter alongside logs with no tracing or gpb at runtime. Final
format, compile, ExUnit, Dialyzer, ExDoc, retirement audit, and packaged-release
results belong to the Phase 2 PR head; check CI's pinned toolchain separately from
local Elixir 1.19.5 / OTP 29.0.1. Live Collector conformance remains Phase 3.

## Phase 3 verification — September 12, 2026

The suite covers 91 tests and 19 doctests. New regressions prove that empty OTLP
partial-success responses mean full success for logs and metrics, while warning-only
and rejection responses retain their distinct outcomes. The real Collector exposed
this bug before the regression was added and fixed.

`mix otlp_shipper.conformance` is opt-in and absent from default CI. Pull the pinned
image using the README command first. It checks gzip delivery through the public
Logger and metrics components against official Collector 0.160.0. Its detailed
output verifies log body/severity/attributes and counter 3, sum 21, gauge 12, and
histogram buckets `[1, 1, 1]` for bounds `[5, 10]`. The checked-in synthetic debug
fixture is output from that Collector, not generated by our decoder. Unit tests
reject missing/wrong fields, mismatched metric values/types, failed fixture execution,
and invalid Docker port mappings, and verify cleanup and child environment isolation.

Production consumer modes:

```sh
scripts/package_smoke.sh
OTLP_SMOKE_DEPENDENCY_SET=minimum scripts/package_smoke.sh
OTLP_SMOKE_DEPENDENCY_SET=minimum_with_tracing scripts/package_smoke.sh
```

All modes test real loopback log/metric delivery from a release without runtime gpb.
The default/minimum modes also require tracing API absence; the last mode requires
API 1.3.0 presence. Lower bounds are Finch 0.20.0, telemetry 1.3.0,
telemetry_metrics 1.1.0, and gpb 4.21.7. A failed consumer build demonstrated that
gpb 4.21.0 cannot compile on OTP 29 (`syntax error before: 'else'`), motivating the
corrected requirement. API 1.3.0 emits an upstream `link/2` warning on OTP 29 but the
consumer passes; prefer API 1.5.0 on OTP 29. Full active-span integration uses the
locked API 1.5.0 / SDK 1.7.0 pair, not the minimum optional API.

The added minimum CI job tests Elixir 1.19.0 / OTP 28.0 and both lower-bound consumer
modes. Default CI retains `.tool-versions`. Local checks use Elixir 1.19.5 / OTP
29.0.1. See [submission/candidate.md](submission/candidate.md) for source revision,
archive checksum and pre-publication results. See
[release verification](submission/release-0.1.0.md) for the subsequent public
Hex installation check.

## Published 0.1.1 verification — September 15, 2026

See [0.1.1 release verification](submission/release-0.1.1.md) for public Hex
installation, the widened Finch requirement, and compatibility smoke results.
Earlier phase and 0.1.0 records retain their original versions and dates.
