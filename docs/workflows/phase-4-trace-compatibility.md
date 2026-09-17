# Phase 4: tracing compatibility and contracts

Base: `cb5b1f40073db64fe40c56ae6414f4f3ee3b0cf4` (`codex/trace-export-plan`).
Branch: `codex/phase-4-trace-compatibility`.
Prerequisite planning and specification PRs #10–12 and maintenance PRs #13–15 are merged.

## Scope and ownership

Establish the SDK integration contract described in PLAN.md §§12–13 through
synthetic, test-only probes and a decision record. Do not implement the production
trace exporter, vendor trace codecs, change runtime dependencies, or start Phase 5.
The orchestrator owns contracts, dependency/configuration changes, optional-consumer
verification, integration, and delivery. The spec writer owns new Gherkin, steps,
and assertions. The implementer owns test-only probe machinery. The runner owns
red/green verification and the reviewer independently checks evidence and decisions.

Acceptance covers SDK callbacks, span-table ownership/lifetime, cancellation,
retry-return behavior, asynchronous flush, shutdown, periodic queue enforcement,
supervised pool ownership, independent instances, record/resource mapping,
optional-SDK compilation, and a viable HTTP feedback prevention strategy.
Supported versions must be evidenced rather than inferred from dependency ranges.

## Contract decisions

Current SDK 1.7.0/API 1.5.0 has no generic suppression primitive; current Finch
instrumentation has no supported exclusion option. The owner explicitly approved a consumer-configured delegating
sampler wrapper. Do not claim
that arbitrary context keys or an unsampled parent suppress all instrumentation.

## Verification

The runner established six ExUnit and six Cucumber assertion failures against the
initial probe stub, followed by two additional suppression assertion failures.
These were implementation assertions, not compilation or infrastructure errors.
The six core scenarios then passed both ExUnit and Cucumber. Restart and record
fidelity scenarios were added for additional evidence; final verification follows.

The packaged non-tracing consumer smoke passed. The fresh optional SDK compilation
prototype passed SDK-present and SDK-absent production releases. It proves an
optional dependency edge is necessary for compilation ordering; Phase 6 will replace
the current test-only SDK declaration when adding the real guarded adapter.

Reviewer TCP-R1 (pool crash/recovery) and TCP-R2 (fresh optional consumer
compilation) are resolved. Restart testing exposed a genuine Finch registration
teardown race; using the existing shared Pool boundary resolved it without changing
the crash assertion. Independent review found no remaining material findings. Probes are development-only;
passing them cannot imply that Phase 5–7 tracing behavior has shipped.


## Scenario mapping

| Scenarios | Evidence |
| --- | --- |
| TCP-01–06 / TRC-02,06–09 | `trace_compatibility_test.exs`: SDK lifetime, cancellation, flush/retry/queue, pool ownership and bounded task mechanics |
| TCP-07 / TRC-10 | `trace_suppression_test.exs`: released Finch instrumentation, delegating sampler, marker restoration |
| TCP-08 / TRC-09 | `trace_pool_restart_test.exs`: pool crash, dependent SDK replacement, instance isolation |
| TCP-09 / TRC-03,05 | `trace_record_probe_test.exs`: actual SDK conversion inputs and dropped counts |
| Optional compilation / TRC-01 | `scripts/trace_consumer_smoke.sh`: fresh present/absent SDK production releases |
| Existing signal compatibility / TRC-01 | Full ExUnit/Cucumber suite and packaged logs/metrics smoke |

These map Phase 4 evidence to the broader acceptance contracts; they do not mark
all future TRC implementation criteria complete. The Gherkin file is registered
for strict CucumberEx execution. Both CI toolchain jobs run the new optional
compilation release probe. `opentelemetry_finch` 0.2.0 is a test-only dependency.


## Final local checks

Elixir 1.19.5 / Erlang OTP 29, frozen source:

- `mix deps.get`, formatting, and warnings-as-errors compilation passed.
- `mix test`: 19 doctests, 101 tests, zero failures.
- `MIX_ENV=test mix cucumber`: 14 scenarios passed under strict discovery.
- `mix credo --strict`: no issues across 54 files.
- `mix dialyzer`: zero errors, zero skipped.
- `mix hex.audit`: no retired dependencies (not a comprehensive security audit).
- `mix docs --warnings-as-errors` and `mix hex.build` passed.
- Fresh SDK-present/absent prototype releases passed.
- Final `sh scripts/package_smoke.sh`: passed, including real loopback logs/metrics
  delivery from a production release without tracing dependencies or runtime gpb.
- Shell syntax and local documentation links passed; no existing test was weakened.

The package build lists no probe modules, SDK, or Finch instrumentation dependency.
Source verification identifies the following files by SHA-256:

- `test/support/trace_compatibility_probe.ex`: `628fd96d950c758f01664c1b05ad77bb876a6440f4d12c3dda1c938db7b352f3`
- `test/support/trace_record_evidence.ex`: `a1679534eae3561e197d5fcee1ee73cee27cb22e29b07c05aad3aaefcf080749`
- `test/support/trace_suppression_probe.ex`: `1911a929cd3525e7f4afffbbd90fd7fe9d85aff8b759fd39c307d12eef8b4486`


CI's pinned and minimum OTP 28 toolchains are pending remote verification. No live
Collector or production provider request was used; no Hex release was published.
Phase 4 is ready for PR review; it completes only
when merged. Phase 5 has not started.


Red evidence was established at base `cb5b1f40073db64fe40c56ae6414f4f3ee3b0cf4`.
Tracked working-diff SHA-256 identifiers for the initial six, suppression, and
restart/record runs respectively were
`39022e715c74fdb22dab1f2d6fb02f81fe8ad6869195380e69a97c6783e371ba`,
`806914cfbe29fda2c7e145ff59b77eb9b4c765234ea2939d6b47c340d767b404`, and
`558ad2766fa8ea2237efdb8fc8dff4812a130ca1ed381cdb7041921e317d84d1`.
The added assertions failed on `{:error, :not_implemented}` before each probe was
implemented. The final full-gate tracked diff identifier was
`d767e0342ab65a63848fab682233d94ef3ec55b7e34ddf86a0de452da5f336ae`;
only evidence documentation was finalized afterward. Source hashes above identify
the new implementation files independently of tracked-diff identifiers.
