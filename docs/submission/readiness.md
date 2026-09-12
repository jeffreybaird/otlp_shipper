# Hex release readiness

Status: **not ready for publication**. The shared core and Logger handler are implemented;
metrics aggregation and real Collector conformance remain unfinished. This is
a manual checklist, not an implemented gate or a record of passing release tests.

Before the first release:

- Resolve the owner decisions in PLAN.md and implement its agreed public contract. Replace greeting
  examples and placeholder descriptions with accurate consumer documentation.
- Add the MIT license text selected in PLAN.md; align package metadata with it.
  Record real package ownership and appropriate source/support links for the selected public or private distribution.
- Confirm the intended Hex package name is available or owned by the publisher.
- Establish tested Elixir/OTP and dependency compatibility; make the declared
  requirements truthful. Runtime dependencies must be available to consumers.
- Configure Dialyzer, run `mix dialyzer` and `mix hex.audit`, and triage findings.
- Run the planned real-collector conformance check for both signals; local fake
  collector tests alone do not establish interoperability.
- Add ExDoc as development tooling, document the public API, and inspect generated
  docs. Add release notes with compatibility and migration details.
- Run the current verification gate and relevant integration tests. Follow
  [build.md](build.md) to inspect package contents and test a fresh consumer.
- Review [package-listing.md](package-listing.md), [reviewer-notes.md](reviewer-notes.md),
  and [../data-handling.md](../data-handling.md) against actual shipped behavior.
- Record the source commit, version, toolchain, archive checksum, executed checks,
  known limitations, and unresolved blockers for the specific candidate.

Build output is not proof of functionality, account ownership, or publication.
Only publish when the user has requested or authorized release. No Hex credentials,
account changes, uploads, or publishing automation are established by this task.

## Implementation evidence

MIT text, dependencies, generated protobuf, ExDoc, Dialyzer, core and Logger tests
are present. Local checks and a production consumer smoke test passed; see
[../testing.md](../testing.md). Metrics aggregation, real collector conformance, final package-name ownership
checks, and publication are still pending. Phase 0 pinned CI passed before merge;
check the Phase 1 PR for this candidate. This is not a finished 0.1.0 release.
