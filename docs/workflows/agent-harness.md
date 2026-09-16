# Feature: agent harness

## Scope and ownership

Install five narrow Codex roles, a specification/red/green/review workflow, and hooks
requiring human intervention for existing test edits or lint/style weakening.
No package runtime changes or Cucumber runtime dependency. Gherkin specifies behavior;
ExUnit remains the package execution layer, Python unittest tests the hook tool.
Base: `89bd9a1f149e4d6356e82ceec5a756f41dac542b`; branch: `codex/agent-harness`.

The primary agent owned contracts, docs, role definitions, CI and integration.
`guardrail_research` researched/implemented the hook and its tests.
`package_checks` ran verification on `gpt-5.6-luna`.
`workflow_review` independently reviewed standards, workflow, and hook behavior.
Bootstrap combined hook spec/test/implementation ownership before the harness existed;
future feature work uses the separate spec writer and implementer roles.

## Scenario mapping

All scenarios are in `docs/features/agent-harness.feature`.

| Scenario | Executable proof |
| --- | --- |
| GUARD-01 | AgentGuardTests.test_new_test_allowed_then_protected_immediately |
| GUARD-02 | AgentGuardTests existing test/doctest/move cases; ProtectedPaths cases |
| GUARD-03 | AgentGuardTests lint/formatter/config/suppression cases |
| GUARD-04 | AgentGuardTests arbitrary shell, opaque tools, malformed stdin subprocess cases |
| GUARD-05 | AgentGuardTests implementation/read/verification cases; WorkflowCommands, OrchestrationCommands and optional-check cases |
| LOOP-01 | Independent document/role review and this task's routed R1 fix/review cycle; no claim of a deterministic autonomous-agent integration test |

The hook has pure classifier tests and real stdin/stdout subprocess integration tests.
Existing Elixir tests are unchanged. A live trusted-host hook denial is a separate
manual activation check, not established by these tests.

## Red/green and verification

The hook implementer captured red before correcting workflow/path defects:

| Suite | Initial red | Green |
| --- | --- | --- |
| test_agent_guard.py | Initial red not retained; no claim of recorded red | 17 tests |
| test_agent_guard_workflow.py | 11 failing subcases | 4 tests |
| test_agent_guard_paths.py | 9 failing subcases | 3 tests |
| test_agent_guard_orchestration.py | 4 failures | 6 tests |
| test_agent_guard_optional_checks.py | 3 failing subcases | 2 tests |

Commands are `python3 scripts/<suite>` for each file above. Each green run exited 0.
The cheaper runner separately verified the original three suites; final verification
covers all five. The PR records final revision and CI results.

Package checks passed: `mix deps.get`, `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix test` (91 tests, 19 doctests), `mix dialyzer`,
`mix hex.audit`, `mix docs --warnings-as-errors`, and `mix hex.build`.
Mix needed sandbox escalation for its local PubSub socket. Dependency audit checks
retired packages, not comprehensive vulnerability coverage. No existing tests,
package code, dependency definitions or lint/style rules were modified.
Consumer smoke and Docker conformance were not run locally for this tooling change.

TOML/JSON parse successfully and follow the fetched official schema. Installed CLI
0.153.4 rejects `--strict-config` for the `features` and `debug` subcommands; those
attempts did not validate runtime agent loading. Trust/discovery/live denial must be
verified in a restarted Codex session as described in `docs/agent-guardrails.md`.

## Review iterations

| Finding | Evidence | Routing and resolution |
| --- | --- | --- |
| R1 | Required branch creation and documented coverage command denied | Implementer added narrow allowlist forms, new regression files, red then green; reviewer rechecks final diff |
| Integration hardening | Internal symlinks and Git internals could evade path classification; executable smoke scripts needed protection | Implementer added protected paths and symlink denial with new regressions |

No human approval was needed for existing test edits: none were made. New tests were
kept unchanged after creation; later coverage went into new regression files.
Activation remains human-owned. Review satisfaction covers the committed artifact,
not an assertion that untrusted hooks already enforce this running session.
