# Feature: CRD — required strict Credo analysis

## Scope and ownership

The owner requested Credo as a dependency and mandatory pipeline check. Record and
fix the existing strict-analysis baseline; preserve package behavior, existing
assertions, and every existing verification gate. Do not add runtime acceptance
steps solely to test the analysis CLI.

- Branch: `codex/credo-gate`. Base revision: `7f45953`; stacked on `codex/tracing-gherkin`. PR recorded at delivery.
- Orchestrator owns integration, dependencies, CI, documentation integration,
  commits, pushes, and the PR.
- Spec writer owns `docs/features/credo.feature`, this initial work record, and the
  alias-only correction in `test/otlp_shipper/metrics_reporter_test.exs`.
- Implementer owns assigned source corrections; no test assertion changes.
- Test runner executes checks on a frozen snapshot and records exact commands,
  output, exit status, source identity, and environment.
- Independent reviewer checks behavior preservation and unchanged analysis strength.

## Scenario mapping

| Scenario ID | Feature specification | Unit layer | CLI/integration proof |
| --- | --- | --- | --- |
| CRD-01 | `docs/features/credo.feature` | New unit tests are inapplicable to adopting an existing analyzer; existing ExUnit tests prove preserved package behavior. | Baseline and corrected `mix credo --strict`; full existing test suite. |
| CRD-02 | `docs/features/credo.feature` | Inapplicable: the command exit status is the contract. | Run strict Credo against a disposable project copy with a known enabled violation; assert nonzero exit and matching diagnostic, then remove the copy. Inspect CI for unmasked failure. |
| CRD-03 | `docs/features/credo.feature` | Inapplicable: verification configuration is the contract. | Inspect CI and documented commands; run existing gates and strict Credo without suppressions, exclusions, or failure masking. |
| CRD-04 | `docs/features/credo.feature` | Inapplicable: dependency isolation requires a packaged consumer. | Inspect production dependency/release application graphs and run `scripts/package_smoke.sh`; confirm Credo is absent. |

## Verification evidence

These are tooling-adoption checks, not an invented product regression. A baseline
finding or absent command demonstrates setup state; it is not described as a failing
package-behavior assertion. Verification must identify the frozen source snapshot.

| Stage | Revision/snapshot and environment | Command | Exit/status | Evidence |
| --- | --- | --- | --- | --- |
| Baseline | `7f45953` plus dependency/lock addition, Elixir 1.19.5 / OTP 29 | `mix credo --strict --format flycheck` | Exit 30; 31 findings | Complexity, nesting, numeric literals, aliases, tautological comparisons, and Logger metadata. Expanded source coverage later exposed one compiler nesting finding. |
| Negative CLI proof | Disposable `/tmp/credo-violation.ex` | `mix credo --strict /tmp/credo-violation.ex` | Exit 20 | Detects IO.inspect and missing moduledoc; fixture SHA-256 `036c9a73599c0911b76e8da2ebadb470e4b674687ab200417c5ff6e56302f72f`. |
| Corrected strict gate | Elixir/Mix 1.19.5, OTP 29 | `mix credo --strict` | Exit 0 | 44 files, 382 modules/functions, zero issues or parsing exclusions. |
| Package behavior | Final source after dev-only Logger configuration | Format, warnings-as-errors compile, ExUnit, CucumberEx, Dialyzer | Exit 0 each | 91 tests, 19 doctests, four scenarios; Dialyzer zero errors/skips. |
| Release checks | Same production source/dependencies | `mix hex.audit`, `mix docs --warnings-as-errors`, `scripts/package_smoke.sh` | Exit 0 each | No retired dependencies; documentation and clean consumer release passed. |
| Production isolation | Same production source/dependencies | `MIX_ENV=prod mix deps.tree --only prod` and application metadata | Exit 0 | Credo and CucumberEx absent; smoke proved expected signal delivery. |

The final code-gate tracked diff SHA-256 was
`834f7baf288d6fe56b467f41ed4a8c63d1487ad268fe7229e472c47c34654237`;
only documentation evidence was finalized afterward. Local links and
`git diff --check` passed.

## Human approvals

The user's request authorizes adding Credo and requiring its check. The existing
test correction adds the `Definition` alias and replaces the fully qualified call
with `Definition.new/1`; it changes no assertion, input, or expected result. This is
a contract-preserving style correction under the current guardrail policy. No
analysis exception or test-contract change is requested or approved.

## Review iterations

| Finding | Severity / file:line | Standard and evidence | Destination | Resolution / verification |
| --- | --- | --- | --- | --- |
| Logger formatter regression | Test failure in malformed-domain coverage | Displaying malformed metadata in tests crashes the console formatter. | Orchestrator | Development-only display preserves original test configuration; full rerun passes. |

## Final handoff

Independent review found no remaining behavior, coverage, or analysis-strength
issues. Exact-commit review and remote CI status accompany the PR handoff. Minimum
supported toolchain checks run in CI. Real Collector/Docker conformance was not
rerun for these behavior-preserving refactors; the fake collector and packaged
consumer checks passed. No publication or merge performed.

## Implementation notes

Credo 1.7.19 is locked with `only: [:dev, :test], runtime: false`. Configuration
keeps default checks and extends source coverage to steps, compiler/configuration,
and conformance helpers. No checks are disabled and no source is excluded to hide
a finding. Both CI toolchains require strict Credo before package consumer checks;
release readiness requires the same gate. No automated publishing workflow exists.

Behavior-preserving source changes extract validation, retry, buffering, aggregation,
and protobuf compiler helpers. The redundant `value == value` float checks are
removed; existing numeric bounds are preserved. The only existing test edit adds
an alias without changing assertions. Development Logger formatter configuration
now actually prints the known metadata used by local diagnostics; it
is not packaged or applied to consumers and does not use an analysis allowlist.

The first full run found that enabling console metadata display in tests made the
existing malformed-domain fixture fail inside the console formatter. The display
configuration is now development-only; tests retain their original Logger formatter
configuration and malformed-input assertions. Credo runs in development in both CI
jobs. No check or metadata rule was disabled.

Automatic approval review rejected the initial commit/push because it required
exact human approval for the existing test's alias-only change. That approval
was requested before any further delivery attempt. After the exact two-line alias
patch was shown, the owner replied "Approve". This explicitly authorizes the
existing-test edit and continuation of the commit/push workflow.
