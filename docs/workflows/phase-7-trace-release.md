# Phase 7: replacement proof and release preparation

Branch: `codex/phase-7-trace-release`. Base: `111f27ba4c447ee6f4a44e20f070d976c5a09c78`,
merged Phase 6 PR #18. The owner authorized Phase 7 after that merge.

## Scope and acceptance

Prove packaged production release operation for logs, metrics, and SDK traces with
existing Finch instrumentation, without the canonical exporter or runtime gpb.
Keep SDK 1.7.0/API 1.5.0 and instrumentation consumer-owned. Exercise current and
minimum shared dependencies, retain SDK/API-absent consumers, and extend pinned
Collector 0.160.0 conformance to exact trace parentage and correlated log IDs.
Prepare version 0.2.0 and migration, rollback, limitations, and release evidence.
No public Hex upload, documentation upload, release tag, or merge is authorized.
No comparative performance advantage is claimed.

## Ownership and contracts

The primary agent owns scope, dependencies/version, feature registration, CI,
migration/release documentation, integration, final checks, commits and PR.
The spec writer owns new Gherkin, focused tests, and authorized strengthening of
the existing conformance runner's fixture to include all three signals.
One implementer owns Collector tooling and pure evidence validation. Another owns
the separate fresh packaged consumer fixture and smoke script. The independent
runner establishes assertion red and executes checks; cross-reviewers inspect
work they did not author.

`Conformance.verify/1` retains its logs/metrics contract. New `verify_traces/1`
validates scoped records and exact relationships, returning `:ok` or
`{:error, :collector_trace_output_mismatch}`. `run/1` now requires both checks;
missing optional SDK support fails before Docker with `:tracing_sdk_unavailable`.
`verify_replacement_report/1` validates the tooling report contract; synthetic
report validation does not prove a fresh release was executed. Only successful
production fixture runs supply release evidence.

The consumer owns the global SDK as an included application, starts its Finch
pool first, and configures the sampler wrapper before startup. The library does
not mutate consumer SDK configuration. Two fresh-release attempts rejected the SDK
as both regular and included because shipper's optional dependency still declared
runtime ownership. Marking that dependency `runtime: false` retains compilation
ordering and leaves startup with the consumer. The initial failure appeared in
tool output; its temporary log was overwritten and is not claimed as an archived
artifact. Public `set_tracer/4` routing was also rejected during investigation
because API 1.5.0 does not export it; no private cache manipulation is used.


## Evidence

Independent assertion red on base `111f27ba4c447ee6f4a44e20f070d976c5a09c78`:

- Trace verifier and orchestration: six tests, six assertion failures (exit 2).
  Stubs returned `:not_implemented`; old orchestration wrongly accepted logs/metrics
  without traces. Tracked diff SHA-256:
  `7a6fc9f94fc7e1a0299ba2202dfc751004f6b4eb1b061a24d3b581c361fb5974`.
  Conformance test SHA-256:
  `74568c71eca93e0f6ae6602f0d63e95ebceac7cb33efb128f347563e8aee54ef`;
  orchestration test SHA-256:
  `4253afc1c28c943654721bbf5f5543e874428f47b61d6ace62ff3fce723f5d91`.
- Report validator: three tests, three assertion failures (exit 2); seven expanded
  Gherkin scenarios, seven assertion failures (exit 1). No setup failure.
  Tracked diff SHA-256:
  `b30372eba9d7a9bbe04bb3ab21525aa123f24e3d4606b9e7076054882de2ae4b`;
  report test SHA-256:
  `d92288d3f2eee626297a88667a3381e795ce679b3fe9199b39709915868146d0`;
  feature SHA-256:
  `a5b273104550daf6e17a93585d31fb4820cf1b94ae9087e5322d4a092622db8a`.

Real Collector 0.160.0 passed twice through local Docker 29.5.3 with the pinned
image digest from the conformance task. The second run captured its unmodified
successful debug output (7,302 bytes), SHA-256
`44ddf709e0527831f8b960a2336f9f50d1cac470a6277cf761df153954307cf3`.
The task verified gzip logs, four metric types, SDK root/child/remote-parent spans,
resource/scope identity, child error/event, and correlated log IDs before cleanup.
Synthetic mutation fixtures remain clearly separate from this authentic capture.

Full local gates and fresh consumers passed; results follow below. Exact-commit
review and remote CI are recorded separately after commit.


## Scenario mapping

| ID | Proof |
| --- | --- |
| TRP-01 | `trace_replacement_conformance_test.exs`, authentic capture test: scoped trace identities and correlated log |
| TRP-02 | Conformance mutation tests and executable steps: reject status, correlation, scope, duplicate names and cross-record decoys |
| TRP-03 | `trace_replacement_orchestration_test.exs`: legacy two-signal output cannot finish the run; cleanup still occurs |
| TRP-04 | `trace_replacement_report_test.exs`: validate a report's structure and consistency without asserting it came from a real run |
| TRC-11 | `scripts/replacement_consumer_smoke.sh` default/minimum actual packaged releases plus pinned real Collector |

Earlier TRC-01–10 evidence remains in Phase 5/6 work records. Phase 7 repeats
non-tracing release checks and adds actual instrumentation replacement proof.


## Review corrections

- TRP-R1: span and event attributes could be satisfied from nested event/link
  sections. New scoping regression tests reject both misleading placements.
- TRP-R2: incoming remote trace identity must equal the emitter's `0x43`, not just
  differ from the root. The new regression rejects a different nonzero trace ID.
- Independent scoping red: three tests, three assertion failures (exit 2), each
  returning `:ok` incorrectly. Test SHA-256:
  `a076bb63c0697f0eddcaa5f5d5843575f3cabebdb70018ac27d9e1d63d857643`;
  tracked diff SHA-256:
  `caf4b2438b3fce1015634dfa363f3ad3a13fbfd94d03b841379219237a33264e`.
- Removing implicit SDK runtime startup exposed the repository test consumer's
  reliance on it (19 setup failures). The test application now explicitly starts
  the SDK; production extra applications remain unchanged. Full ExUnit/Cucumber
  passed after that ownership fix.
- Dialyzer now explicitly includes the compile-only SDK in its PLT. This expands
  analysis of callback/types; no warning or rule is suppressed. A Credo finding
  in a new test helper was fixed with equivalent `Enum.map_join`.

- The real global SDK resource revealed its default `service.instance.id` is a
  128-bit integer outside OTLP's signed 64-bit range. The strict exporter rejected
  the resource and reported two unsent spans. The consumer now explicitly configures
  a string instance ID across all signals; migration instructions require this
  override. Resource fidelity/validation was not weakened or silently coerced.

- The new release fixture initially inherited `OTEL_*` settings. With
  `OTEL_SDK_DISABLED=true` and `OTEL_TRACES_SAMPLER=always_off`, the retained release
  failed its SDK-provider assertion (exit 1). The disposable fixture now removes
  those variables before startup, preserving its `OTLP_*` control/report options.
  A fresh release with those conflicting settings then passed.
- Strict Credo explicitly checked all five standalone consumer `.exs` files
  (34 modules/functions) with `mix credo --strict 'scripts/fixtures/trace_replacement/*.exs'`.
  The fixture sits outside the repository's normal source-discovery paths.


## Final local verification

Elixir 1.19.5 / OTP 29.0.1, independent runner:

- Dependencies, formatting, warnings-as-errors compile: passed.
- ExUnit: 166 tests and 22 doctests, zero failures. Strict CucumberEx: 37 scenarios,
  all passed. The original logs/metrics assertions remain intact.
- Strict Credo: 91 source files, no issues. Dialyzer: zero errors and zero skipped
  checks. Standalone consumer fixtures also pass explicit strict Credo/formatting.
- Hex retirement audit: no retired packages; not a comprehensive vulnerability scan.
- ExDoc warnings-as-errors, Hex build, and local publish dry run: passed.
- Default/minimum/API-minimum package consumers: passed. SDK-absent/present fresh
  release script: passed via `sh`, as invoked by CI. Direct execution is not
  supported by its existing non-executable file mode (exit 126); no check was skipped.
- Current/minimum replacement consumers: passed, including a conflicting inherited
  OTel environment in the current mode. Actual reports and measurement limitations
  are in [candidate evidence](../submission/candidate-0.2.0.md).
- Real pinned Collector: passed again after verifier corrections. Required source
  assets, licenses, migration docs and archive exclusions inspected. Local Markdown
  links, shell syntax and whitespace checks passed.

Archive SHA-256:
`cab8b8b6a51b18786fdf653e726316414126a9113f01506d1fd1d507f4962c7b`.
Code/spec/CI snapshot (24 changed files; sorted path + NUL + file bytes + NUL,
`.ex`, `.exs`, `.proto`, `.sh`, `.feature`, `.yml`, `.yaml`):
`ce7821365671fdcc672e55d35a6d6e1111e63a85eb0603ff52606f7763fd50dd`.
Replacement fixture six-file snapshot:
`5d55f26dd82c63b968d7f66e118eb6311aac81ebf7c215e00859a8671e7b8e6d`.
Independent cross-review is satisfied for production conformance and, separately,
consumer fixtures/docs/dependencies/CI. No findings remain in those scopes.
No analysis rules, assertions, or required checks were suppressed.


## Committed-source review

Implementation revision: `01ff8c1564224d39fc2ca1e07dcafcf83b684eb5`.
The worktree matched the verified snapshot and was clean. Independent reviewers
confirmed their separate scopes on that exact commit: production conformance
(TRP-R1/R2 closed), and consumer/scripts/docs/dependencies/CI. Remote CI remains
pending. Later evidence-only documentation does not change packaged source.
