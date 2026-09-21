# CucumberEx acceptance runner

## Scope and ownership

The owner requested adding their CucumberEx library. Add the published Hex dependency
for tests, execute new Gherkin acceptance scenarios against existing configuration
behavior, require strict execution in CI, and update the spec-writer guidance.
No production behavior changes or conversion of historical Python harness scenarios.

Base: `ee3fcfb5d4196a194295bd2df44c06289e399767`; branch: `codex/cucumberex`,
stacked on `codex/trace-export-plan`.

The orchestrator owns dependencies, runner configuration, role guidance and delivery.
The spec writer owns the new feature and step definitions; the implementer owns CI,
formatter inputs and workflow documentation. The cheaper runner verifies frozen
source, and the independent reviewer checks the final change.

## Acceptance and verification

- CucumberEx is test-only, locked from Hex, and absent from production consumers.
- Real configuration scenarios execute with strict undefined/pending handling.
- ExUnit and static-analysis gates remain required.
- Future Elixir acceptance specifications have executable step definitions.

This adds a runner for existing behavior. The initial missing-task result is setup
baseline evidence, not an assertion-based product regression. Verification also
uses temporary features to prove failed assertions and undefined steps exit nonzero.
Existing tests, helpers and fixtures are unchanged.

## Scenario mapping

All scenarios live in `docs/features/cucumberex.feature` and execute the public
`Config.new/3` API through `features/step_definitions/config_steps.ex`.

| ID | Contract |
| --- | --- |
| CUC-001 | Logs preserve exact endpoint and service resource |
| CUC-002 | Metrics preserve exact endpoint and service resource |
| CUC-003 | Unsupported protocol returns its specific tagged error |
| CUC-004 | Non-HTTP endpoint returns its specific tagged error |

These are pure public-API acceptance checks; HTTP/process integration is inapplicable.
Existing ExUnit configuration and transport coverage remains unchanged.

## Baseline

On base `ee3fcfb`, `MIX_ENV=test mix cucumber --strict docs/features/cucumberex.feature`
exited 1 with `The task "cucumber" could not be found`. The initial sandbox run could
not open Mix's local socket; the authorized retry established the missing-task result.
Elixir/Mix 1.19.5, OTP 29.0.1. This is setup evidence only.

## Final verification

Runner verification completed on Elixir 1.19.5 / OTP 29.0.1. Independent review found no code or coverage issues. Remote CI results belong to the PR head.

Initial gate: compilation, 91 ExUnit tests/19 doctests, all four Cucumber scenarios,
Dialyzer (zero errors/skips), Hex retirement audit, ExDoc and packaged consumer
release smoke passed. Undefined-step and wrong-endpoint temporary feature probes
both exited 1, proving strict discovery and assertion failure propagation.
The new step file initially needed formatter parentheses/line layout; corrected
without changing assertions, with focused verification repeated afterward.

`mix deps.tree` without `--only` lists dependencies across environments even with
`MIX_ENV=prod`; isolation must use `mix deps.tree --only prod` and consumer evidence.
The unfiltered tree is not evidence of a production dependency leak.

Final focused rechecks passed formatting and all four scenarios. Both negative
probes retained exit 1. The filtered production dependency tree and application
metadata exclude CucumberEx. Local documentation links/fences, role TOML parsing,
and `git diff --check` passed. No checks were suppressed. Minimum-toolchain checks
are delegated to CI. No existing tests, helpers, or fixtures were edited.
