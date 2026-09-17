# Phase 5: trace protocol and shared core

Branch: `codex/phase-5-trace-protocol`. Base: merged Phase 4 on
`codex/trace-export-plan`, `9ebb09e` (PR #16, all three CI jobs passed).

## Scope

Implement PLAN.md §14 and the Phase 4 contracts: generated trace schemas,
transport-only configuration, strict SDK-independent span conversion,
resource/scope-preserving envelopes, bounded request construction, shared deadlines,
and fake-collector conformance. Preserve existing logs/metrics behavior. Do not
implement SDK callbacks, tracing lifecycle registration, or the production sampler
wrapper; those remain Phase 6. No release publication.

The orchestrator owns contracts, schema provenance/compiler registration, dependency
and shared configuration integration, documentation, commits, and PR delivery.
The spec writer owns new assertions/Gherkin/steps and trace collector support.
One implementer owns Config/Transport; another owns conversion/encoding/batching.
The independent runner establishes assertion red and runs frozen-source checks;
the reviewer checks contracts, boundaries, and final evidence.

## Core interfaces

- `Config.transport(:traces, options, environment)` and `load_transport/2` omit
  resource creation. Existing `Config.new(:traces, ...)` stays invalid.
- `TraceRecord.convert(span, native_offset, max_bytes \\ 65_536)` consumes normalized
  maps, not SDK records; returns a span message and its original scope identity.
- `Encoder.encode(:traces, converted_spans, resource)` delegates to `TraceEncoder`.
- `Transport.export_until(config, pool, body, count, deadline)` uses an absolute
  monotonic millisecond deadline, capped by the configured timeout.
- `TraceBatch.export(config, pool, spans, resource, offset, total_count)` consumes a
  bounded portion of a finite enumerable at a time. The caller supplies its exact
  count (the future SDK adapter can read table size), so cancellation can account
  for unvisited spans without evaluating a blocked enumerable. Count mismatch is
  an invalid batch. Summary counts partition accepted, rejected, invalid, failed,
  and unsent spans; requests counts logical requests, not retry attempts.

All conversion, encoding, enumeration, and transport share one bounded linked-worker
lifetime. Transport owns submitted-request rejection/failure diagnostics; batching
reports only local invalid and unsent spans. A parent-owned, coherent progress
ledger marks chunks submitted before transport and terminal before telemetry handlers.
An internal transport observer supports that ordering. All diagnostics run inside
the bounded worker: deadline cancellation may omit final diagnostics, but must not
double-count prior outcomes or run arbitrary handlers after the budget expires.
Returned counters preserve the latest committed outcomes. Count mismatches can be
discovered after prior delivery; they do not roll back accepted chunks.
A lost response does not prove remote
non-delivery. Accepted chunks are never replayed after a later failure.

## Evidence

### Scenario mapping

All scenarios execute in `features/step_definitions/trace_protocol_steps.ex`.

| Scenario | Focused ExUnit coverage |
| --- | --- |
| TPC-01 | `trace_config_test.exs`, `trace_runtime_config_test.exs` |
| TPC-02 | `trace_record_test.exs`, `trace_doctest_test.exs` |
| TPC-03 | `trace_encoder_test.exs`, `trace_doctest_test.exs` |
| TPC-04 | `trace_batch_test.exs` count, full-request bytes, indivisible span limits |
| TPC-05 | `trace_transport_test.exs` HTTP/gzip/retry/response bounds; `trace_batch_test.exs` partial outcomes |
| TPC-06 | `trace_shared_deadline_test.exs`; `trace_batch_test.exs` blocked source/telemetry cancellation; transport expired deadline |
| TPC-07 | `trace_batch_test.exs` later permanent failure and late count mismatch |

### Assertion red

At base `9ebb09ee218cbd56430e5b3c3620a4fff85da572`, the independent runner observed:

- `mix test test/otlp_shipper/trace_record_test.exs test/otlp_shipper/trace_encoder_test.exs`:
  exit 2, 9 tests/9 assertion failures against the unimplemented core. The generated
  codec was already available; these were not compilation/setup failures. Tracked
  diff SHA-256: `68320d7eb45607d20390115131903c273ad31d36e80a440e09e8ba8850f259ab`.
  Record test SHA-256: `552f9156124d724084bdc7aae240b9e395181cd812ecbcc07d29f2f10b2f4b0a`;
  encoder test: `c73fd444f2e0299350d2a60fe4fd875d95c35d4941aa451f05eb94f5de5f7133`;
  fixture: `f50767b1d96f570af8752d015dd6058244f3f0ada0356adb44c9015ca149afe4`.
- `mix test test/otlp_shipper/trace_config_test.exs test/otlp_shipper/trace_transport_test.exs test/otlp_shipper/trace_batch_test.exs`:
  exit 2, 17 tests/17 assertion failures against the stub Config/Transport/Batch APIs.
  Additional deadline/runtime/doctest and Gherkin coverage was added during the
  implementation; no separate preimplementation red run is claimed for those.

The first full-suite run found an old assertion that `:traces` was unsupported by
`Encoder`. Phase 5 intentionally adds this signal. The unsupported-signal assertion
now uses `:profiles`, with additive trace-delegation assertions. This implements the
user-authorized contract change; it does not weaken validation or mask a code defect.

### Final verification

Local environment: Elixir 1.19.5 / OTP 29.0.1. Independent runner results:

- Dependency resolution, format check, warnings-as-errors compilation: passed.
- ExUnit: 131 tests and 22 doctests, zero failures.
- Strict CucumberEx: 21 scenarios, all passed (7 new Phase 5 scenarios).
- Strict Credo: no issues; Dialyzer: zero errors and zero skipped checks.
- Hex retirement audit: no retired packages. This is not a vulnerability scan.
- ExDoc warnings-as-errors and Hex build: passed.

The first Cucumber run exposed a setup defect: Bandit's generated child ID did not
match the helper's lookup. Giving the test collector an explicit supervisor child
ID fixed setup without changing behavior assertions. ExDoc also identified an
abbreviated README module reference, corrected to its fully qualified name.

The code/spec snapshot SHA-256 is
`7b19bd7730a293509bec6385a5ec1181224e1557f165853ed828f8e7b81d4130`.
It hashes sorted changed/untracked `.ex`, `.exs`, `.proto`, `.sh`, and `.feature`
paths plus NUL, file bytes, and NUL (25 files). Documentation evidence is excluded
from that digest. No analysis rule, skip, or exclusion was added.

Default, minimum-dependency, and minimum optional-API production consumer smokes
all passed. The latter retains the known upstream API 1.3.0 `link/2` warning on
OTP 29; no warning suppression was added. Final commit review is pending. Local shell syntax,
`git diff --check`, and changed-document local links passed. Remote pinned/minimum
toolchain CI remains a separate required check. Real Collector trace conformance
and SDK integration remain later phases. Phase 5 completes only after PR merge.
