# Phase 6: SDK adapter and correlated operation

Branch: `codex/phase-6-trace-sdk`. Base: `5393652444d20beded638aba7718f49b8aaaeeb2`,
merged Phase 5 PR #17. The owner authorized Phase 6 after that merge.

## Scope and acceptance

Implement PLAN.md §15 using the approved Phase 4 compatibility contracts. Target
SDK 1.7.0 / API 1.5.0 only; reject unverified pairs. Keep the SDK batch processor,
context, sampling, instrumentation, and queue ownership with the consumer. Add the
optional guarded exporter, SDK record normalization, callback result mapping,
consumer-owned pool child specification, and consumer-configured delegating sampler.
No global configuration mutation, second queue, canonical exporter dependency,
release upload, or Phase 7 migration/performance claim.

Prove TRC-02 and 06–10 with real SDK providers, original resource/scope identity,
root/nested/remote parentage, supported data fields, sampled/unsampled operation,
correlated logs, concurrent producers, repeated flushes, cancellation, independent
instances, restart, and shutdown. Test actual Finch instrumentation feedback and
context restoration. Repeat fresh packaged consumers with and without the SDK.

## Ownership and interfaces

The primary agent owns contracts, dependencies, feature registration, documentation,
package consumer proof, commits, and PR. The spec writer owns new Gherkin and test
files. One implementer owns exporter/SDK normalization and the shared batch deadline
entry point; another owns sampler/suppression and the actual HTTP-worker marker.
The independent runner establishes assertion red and verifies frozen source.
Reviewers inspect code they did not author.

- `TraceExporter.init/1` accepts keyword transport options plus a named `:pool`,
  verifies the actual Finch pool and supported versions, and returns SDK callback
  shapes. It never starts or owns the pool.
- `TraceExporter.pool_child_spec/1` creates a child specification using the existing
  bounded pool restart boundary. The consumer starts it before its named SDK provider
  in a `:rest_for_one` supervisor and stops the provider first.
- `export/3` consumes the callback table synchronously. SDK normalization is lazy
  and bounded inside the shared worker. Resource normalization also happens within
  the same deadline. No callback resource is rebuilt from shipper identity options.
- Internal `TraceBatch.export_until/7` preserves an absolute deadline captured at
  callback entry; existing `export/6` behavior remains intact.
- `TraceSampler` wraps a consumer-selected sampler specification. Internal
  `TraceSuppression.with_suppression/1` sets `:otlp_shipper_export` in OTel context
  around actual transport work and restores prior context in `after`. All shipper
  HTTP signals use the marker, preventing their HTTP spans from feeding tracing.
- Existing Phase 4 result mapping and diagnostic ownership remain authoritative.
  SDK export timeout must exceed the shipper budget by at least 2,000 ms. Flush
  initiates work; it does not acknowledge delivery. Shutdown does not own the pool.

## Evidence

The initial independent red run used the compileable exporter/sampler stubs:

- `mix deps.get`: passed; the SDK dependency changes from test-only to optional,
  with no lockfile version change.
- `mix test test/otlp_shipper/trace_sdk_callback_test.exs test/otlp_shipper/trace_sdk_sampler_test.exs`:
  exit 2, seven tests/seven assertion failures (`init` returned `:ignore`, sampler
  returned `:not_implemented`, marker remained unset). No setup failure.
- Base: `5393652444d20beded638aba7718f49b8aaaeeb2`; tracked diff SHA-256:
  `5b57b098e4cfbd6216bd21e9ba87c2783d3d7a901d9b685fbc14869a70857aa0`.
- Callback test SHA-256: `bd0018c2ab1dee3fe540748e1a94084b41582bfceec659c1c30330c4f43fada5`;
  sampler test: `e578732d02dfd775e08dcfbce7beb2ccf93b9ea0fad3048fce4a1bafedcef9af`;
  fixture: `ea5a26699fd85147493303103b2e8417d31fc7117ed2fc43835811c2df9b8526`.

Subsequent integration coverage was developed alongside implementation; the initial
seven-test run is the stable preimplementation red evidence. A later integration
run also observed five stub-init assertion failures, but overlapping file writes
mean it is not used as an independent frozen-source red snapshot.

Review identified blocking initialization telemetry, raw resource schema allocation,
and scope identity incorrectly counted against span-only bounds. All three are fixed
and covered by boundary regressions. The generated full-fidelity SDK fixture exceeds the
65,536-byte default span limit, so that fidelity test explicitly raises its request
limits; default oversized-span rejection remains covered. Timestamp assertions use
the SDK's original event order rather than its reversed storage representation.

## Scenario mapping

Executable feature: `docs/features/trace-sdk.feature`; steps:
`features/step_definitions/trace_sdk_steps.ex`. Nine expanded scenarios map to these
stable acceptance groups:

| ID | Coverage |
| --- | --- |
| TSDK-01 | `trace_sdk_callback_test.exs`, `trace_sdk_outcomes_test.exs`: ownership, validation, callback mappings, partial/permanent/transient results |
| TSDK-02 | `trace_sdk_integration_test.exs`: real SDK metadata, dropped counts, epoch timestamps, event/link order, resources and scopes |
| TSDK-03 | Integration and outcome tests: borrowed table destruction, linked retry cancellation, callback timeout |
| TSDK-04 | `trace_sdk_lifecycle_test.exs` and integration tests: independent trees, crash recovery, reverse shutdown, asynchronous repeated flush |
| TSDK-05 | `trace_sdk_correlation_test.exs`, integration and outcome tests: correlated/detached logs, parentage, concurrent producers, scopes, sampling, real exception event/status |
| TSDK-06 | `trace_sdk_sampler_test.exs`, `trace_sdk_feedback_test.exs`: delegation, exact marker, complete context restoration and actual Finch instrumentation feedback |
| TSDK-07 | `trace_sdk_boundaries_test.exs`: blocked init diagnostics, independent scope bounds, bounded resource schemas |

## Review regressions and corrections

- **R6-01:** A blocking subscriber could hang invalid exporter initialization.
  Diagnostic execution now uses a linked task with a 100 ms budget and reaps it.
- **R6-02:** Character-list resource schema conversion could allocate before a raw
  bound. Resource preflight now precedes normalization inside the callback deadline.
- **R6-03:** The raw span budget incorrectly included scope identity. A separate raw
  scope bound now precedes normalization, preserving the existing normalized scope
  and exact request limits. A valid 300 KB scope exports without raising span limits.
- Independent boundary red: `mix test test/otlp_shipper/trace_sdk_boundaries_test.exs`
  exited 2, three tests/two failures. R6-01 returned no result within 700 ms; R6-03
  dropped the valid scope instead of sending HTTP. R6-02 had already been fixed and
  passed characterization. Test SHA-256:
  `41471085be1d3a06a424dcff592b0a40c34aef2a94738aa177d495995c6fe2e5`;
  tracked diff: `066d282e3740e8e1d471c042799e5481db63cac5c6d1580c2f58023e066dee8e`.
- **R6-04:** Fresh consumers selected allowed Finch 0.23.0, whose pool metadata no
  longer contains `manager_name`. The real SDK HTTP-delivery smoke failed. Pool
  validation now uses shared registry/supervisor metadata; locked Finch 0.20.0 and
  fresh Finch 0.23.0 both pass. The dependency range was not narrowed.
- The release version-gate fixture initially used Elixir `Application.load/1` with
  an Erlang application specification. It now correctly uses `:application.load/1`
  in its disposable VM. Assertions for rejecting both unsupported versions remain.
- Independent review also caught a stale README statement denying the implemented
  SDK adapter; that statement was corrected before the passing documentation gate.

## Final local verification

Elixir 1.19.5 / OTP 29.0.1, independent runner:

- `mix deps.get`, format check, warnings-as-errors compilation: passed.
- ExUnit: 153 tests and 22 doctests, zero failures (22 added SDK tests).
- Strict CucumberEx: 30 scenarios, all passed (nine added SDK scenarios).
- Strict Credo: no issues. Dialyzer: zero errors and zero skipped checks.
- Hex retirement audit: no retired packages; this is not a vulnerability scan.
- ExDoc warnings-as-errors and Hex build: passed.
- Actual packaged SDK release: SDK absent and SDK 1.7.0/API 1.5.0 present both passed.
  The latter uses Finch 0.23.0, initializes the actual exporter/sampler, delivers a
  real SDK span through HTTP, preserves identities, and rejects unsupported SDK/API
  application versions. The canonical exporter and runtime gpb remain absent.
- Default and minimum package consumers: logs, metrics and trace protocol core
  passed without optional tracing dependencies. The minimum optional-API mode also
  passed with API 1.3.0 and no SDK. Its known upstream OTP 29 `link/2` warning is
  unchanged; no warning suppression was introduced.
- Shell syntax, changed-document local links, and `git diff --check`: passed.

Code/spec snapshot SHA-256:
`c4346e15939aed660c915a10ce9baf06ad8cb731e568c8a54b50f951c3ba64b3`.
It hashes sorted changed/untracked `.ex`, `.exs`, `.proto`, `.sh`, and `.feature`
paths followed by NUL, file bytes, and NUL (21 files). Documentation evidence is
excluded to avoid a self-referential digest. No test assertion was weakened and no
analysis rule or failure was suppressed.

Exact-commit review and remote pinned/minimum-toolchain CI remain pending. Phase 7
waits for this phase's merge; no public package has been published.
