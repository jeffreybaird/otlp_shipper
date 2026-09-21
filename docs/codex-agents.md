# Five-role feature harness

The primary agent acts as orchestrator. Use the definitions in
[../.codex/agents/](../.codex/agents/) for delegated roles. A custom role definition
is a directive, not a background daemon: the orchestrator must dispatch work,
consume reports, and run the loop. Read AGENTS.md, PLAN.md, product decisions, and
applicable architecture, interface, style, testing, and data-handling docs first.

| Role | Owns | Must not do |
| --- | --- | --- |
| Orchestrator | Scope, public contracts, assignment boundaries, integration, PR and final evidence | Declare completion with open findings or stale checks |
| Spec writer | Feature plan, Cucumber/Gherkin scenarios, failing unit and integration tests | Implement production behavior or adapt tests to conceal implementation defects |
| Test runner | Execute prescribed checks on frozen source; report exact results to implementer and orchestrator | Edit source/tests/config, repair failures, or silently substitute models |
| Implementer | Minimal production changes that satisfy approved behavior | Change tests, weaken checks, expand scope, commit, or push |
| Reviewer | Independent inspection against AGENTS.md and applicable docs; finding ledger | Fix its own findings or sign off without checking coverage and final changes |

The runner uses `gpt-5.6-luna`, the cheaper model available in this environment.
Other roles inherit the session model. If the runner model is unavailable, report
that fact to the orchestrator; record an explicit supported replacement before use.
Model availability and relative cost depend on the host/account.

## Dispatch and ownership

Pass each agent the feature ID, acceptance criteria, allowed files, forbidden files,
public contracts, prerequisite reports, exact commands, and expected output.
Keep one writer active for any file. The orchestrator assigns one owner for
`mix.exs`, `mix.lock`, and shared types. Freeze all source during verification and
review; resume edits only after the report. Agents do not spawn nested teams.

Five roles do not require five simultaneous sessions. With four total slots, run
the spec writer and runner first, then implementer and runner, then reviewer.
Release completed sessions where supported; otherwise reuse slots with explicit
role instructions. In hosts without named custom-agent dispatch, pass the complete
`developer_instructions` from the role file to the subagent. For the cheaper runner,
use a fresh or bounded context when supplying a model override. Never substitute
an ordinary task/sidebar conversation for a subagent.

## Red, green, and review

1. Orchestrator records scope, branch/base revision, ownership, acceptance criteria,
   and intended checks in `docs/workflows/<feature>.md`. Follow existing phase merge
   boundaries; post-phase maintenance uses a focused `codex/` branch.
2. Spec writer breaks the feature into `docs/features/<feature>.feature` using
   Cucumber/Gherkin `Feature`, `Scenario`/`Scenario Outline`, `Given`, `When`, `Then`.
   Give scenarios stable IDs and map each to test file/test name in the work record.
   Execute new Elixir acceptance scenarios with CucumberEx: add step definitions
   under `features/step_definitions/` and register the feature path in
   `config/config.exs`. Keep strict execution enabled. Retain ExUnit coverage for
   meaningful unit and integration boundaries. Historical Python harness features
   remain mapped to Python tests unless explicitly converted to executable features.
   Cover happy path, declared failures, and boundaries. Write new unit and integration
   test files. Existing test changes must preserve the intended contract or implement
   a user-authorized contract change; they must never conceal an implementation defect.
3. Runner executes the focused tests before implementation, including
   `MIX_ENV=test mix cucumber` for executable acceptance features. Record command, exit
   code, expected failure and actual assertion, revision plus working-tree diff
   identity, and environment. Compilation/setup failures alone are not valid red
   evidence for an assertion-based regression. Return environment problems to the
   orchestrator and test defects to the spec writer. Escalate unresolved contract
   changes to the user; routine test corrections need no blanket approval.
4. Implementer consumes the plan and runner report, changes only assigned production
   files, then requests the runner. Runner sends failures directly to the implementer
   and copies the orchestrator. Repeat until focused tests and applicable full checks
   pass. Missing scenarios go back to the spec writer, who adds new tests; establish
   red before the implementer addresses each newly found behavior.
5. Orchestrator integrates the green result, commits/pushes an atomic change, and
   opens or updates the draft PR with scope, scenario mapping, and red/green evidence.
   Do not commit a deliberately failing intermediate test suite. Preserve linear
   history and unrelated work. No merge or release is implied.
6. Reviewer inspects the current PR revision, implementation, specs, tests, and full
   applicable standards. Report each issue with ID, severity, file/line, violated
   contract, reproduction/evidence, and destination (`implementer` or `spec_writer`).
   Review approval requests and coverage gaps as well as code quality.
7. Orchestrator routes every finding. Repeat red/green for missing behavior, rerun
   affected and full gates after fixes, commit/push, update the same PR, and ask the
   reviewer to inspect the new revision and every previous finding. No arbitrary
   retry limit counts as success. Genuine blockers are reported to the user.
8. Reviewer reports `satisfied` only when every finding is resolved with evidence
   and the final revision is covered by current verification. Orchestrator checks CI,
   updates the PR summary/status, and reports the PR and remaining external blockers.
   Any later code/test/config edit invalidates sign-off and requires another review.

## Evidence and approval

Use [the work record template](work-record-template.md). Red/green runs can use an
uncommitted snapshot: record HEAD, `git diff --binary` digest, and hashes of untracked
inputs. A HEAD SHA alone does not identify an uncommitted test run. After committing,
confirm the tree matches the verified snapshot and obtain review for that commit.

Run all applicable checks from AGENTS.md and testing.md before code commits.
Documentation-only tasks use content/link checks. Harness code additionally runs
the `python3 -m unittest discover -s scripts -p 'test_agent_guard*.py'` suite listed in
[agent-guardrails.md](agent-guardrails.md). Pure docs/config work need not invent failing
package tests; tooling behavior must have executable regression coverage.

Never revise tests to accommodate defective code or bypass static analysis. Ask for
human review when an unresolved contract change or necessary analysis exception is
not already authorized; provide the exact change and reason. Routine test changes
that preserve the contract and tests for user-authorized behavior changes may
proceed. Follow [agent-guardrails.md](agent-guardrails.md). Agents cannot approve
exceptions on behalf of the human.
