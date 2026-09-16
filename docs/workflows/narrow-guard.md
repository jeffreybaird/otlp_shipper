# Feature: Narrow test and static-analysis guard

## Scope and ownership

Replace the global tool allowlist with two review concerns: changing tests to hide
implementation defects, and bypassing static analysis. No package/runtime changes.
User explicitly requested this policy replacement and then deactivated the old hook
so it could be implemented. That instruction authorizes updating the hook, its
superseded contract tests, and conflicting policy guidance; it does not authorize
weakening package tests or analysis checks.

Base: ec0a1df; branch: codex/narrow-agent-guard. Primary agent owns scope, integration,
policy docs, obsolete-suite migration, commits, and PR. Spec writer owns new
regressions and Gherkin; implementer owns hook code/config; test runner owns execution;
reviewer independently inspects the final change. No dependency or public API changes.

## Contract and limits

Official hook documentation supports command handlers, denial, and nonblocking
additionalContext. It does not run prompt/agent handlers. A command hook cannot
reliably infer intent or authorization from a patch. Candidate test-contract edits
and analysis configuration/suppression edits therefore request contextual review
through additionalContext; they are not automatic denials. That context does not
pause the pending tool or prove a human reviewed it. Concrete analysis commands
that mask their failing exit status are denied. Other tools and commands pass.

Only Bash and apply_patch are matched. This is a cooperative review aid, not a
sandbox against alternate write paths or arbitrary interpreter execution.

## Verification evidence

Independent runner (`test_runner`, gpt-5.6-luna) established red with
`python3 scripts/test_agent_guard_narrow.py`: Python 3.14.6, exit 1, 18 tests,
51 failing subcases. Failures were assertions against the broad allowlist, blanket
path protection, output schema, and wildcard matcher; no setup failure.
Old hook SHA-256: c3133aa59ebd91765b4db9ec889bb586c609387d73c392f71eae9f1fa24c38e4.
New test SHA-256: c841f8d615c9ab66708a95d4d2c048f849fff4fab5b93e3b724112ca0ad8010c.
Tracked diff SHA-256: f171c49f152b8c368b2e2dc89b799c475cdeb1964d1e9a4cb83de604aa0d06f1.

The five old classifier suites encoded the superseded deny-by-default contract.
They are replaced by independently written narrow-contract coverage, including
direct hook evaluation and subprocess protocol tests. Historical evidence remains
in agent-harness.md. Package tests and static-analysis commands are unchanged.
The existing dedicated agent-harness CI job now runs hook regression discovery;
its Python 3.11 setup and configuration parse checks remain intact.

Initial implementation passed 26 regression tests under Python 3.14.6 and system
Python 3.9.6, including eight independently added boundary cases (already green;
no claim of additional red). The runner also passed dependency fetch, formatting,
warnings-as-errors compile, 91 ExUnit tests / 19 doctests, and Dialyzer (0 errors,
0 skipped) on Elixir/Mix 1.19.5 / OTP 29. Socket restrictions required exact-command
sandbox escalation for Mix fetch/compile/test/Dialyzer; the retries passed without
changing checks. Initial green tracked diff SHA-256:
8e9a337a1c62b37ceffa6c0373759b1ef0af081b5de0f44da75ed069b45afb00.

Independent review found five gaps: operators in shell comments caused false
denials; `|| exit 0` was not denied; assertion weakening by insertion was missed;
existing analyzer exclusion expansion was missed; masking added to a CI analysis
command was missed. New regression coverage and fixes are required before handoff.
The spec writer additionally covers a false-to-true exit-status configuration change.
The runner established regression red with
`python3 scripts/test_agent_guard_review.py`: exit 1, six tests, seven failing
subcases covering all six cases (two shell-comment examples). No setup errors.
Regression file SHA-256:
5bd69343d8dd94f8defd866daf18c0784b3f19bd89b0d5a11cb8237005f2b84c.
Tracked diff SHA-256 at that red run:
f719991c438156c50ce23e458ff23558cfd6075df8331f681184e5226930a68f.

Final frozen candidate: all 32 hook tests passed independently on Python 3.14.6
and system Python 3.9.6. The runner repeated the full required package gate;
dependency fetch, formatting, warnings-as-errors compile, 91 tests / 19 doctests,
and Dialyzer all passed (0 errors, 0 skipped). `git diff --check` passed.
Tracked diff SHA-256 before this evidence-only update:
650d29cf8b57b9e87c9e613a6de7d44d686348cd16d7430e6bf813320be210a3.
Final guard SHA-256:
b5247cfe3277e13fba2a5804c0033528afcea60e9ac9db9dfcc4b8d940d0195d.

The independent reviewer reproduced every original finding against the updated
hook and confirmed NG-R1 through NG-R5 resolved, with no new material findings.
Additional read-only probes confirmed conditional assertion wrappers and quoted
exclusions receive review, while multiline formatting and added assertions pass.
Agent TOML, hook JSON, and current local documentation links were validated.

Hook is deactivated by the user; live host activation/enforcement is unverified.
Docker Collector conformance and release packaging were not run for this tooling
change. The package runtime, package tests, and required analysis checks are
unchanged. Re-enable/trust the revised hook through the host when ready.

## Scenario mapping

NG-01 through NG-09 in narrow-guard.feature map to `test_ng01_*` through
`test_ng09_*` in scripts/test_agent_guard_narrow.py. NG-08 exercises the hook's
subprocess JSON protocol; other scenarios use direct classifier/config tests.
Elixir/Collector integration is inapplicable to this Python-only behavior change.
Additional NG boundary tests live in scripts/test_agent_guard_boundaries.py.
Review regressions live in scripts/test_agent_guard_review.py, mapped by NG IDs
in their method names. Reviewer findings NG-R1 through NG-R5 map respectively to
shell comments, exit-zero fallback, assertion insertion, exclusions, and CI masking.

## References

- [Acceptance scenarios](../features/narrow-guard.feature)
- [Hook contract](../agent-guardrails.md)
- [Official hook protocol](https://learn.chatgpt.com/docs/hooks)
