# Guard readability refactor

Implementation baseline: `e21617081fd37ae208f48555c6ae349159d1f6ef`.
PR base: `8a718d4287d61308bef81e73a76b358a7057ec68` on
`codex/tracing-gherkin`, after the parent PRs merged. Both revisions have identical
trees; only this refactor is included in the new PR.
Branch: `codex/guard-readability`.

## Scope and acceptance

Refactor `.codex/hooks/guard.py` and `.codex/hooks/run_guard.py` without changing
policy, output, exception handling, deadlines, or process cleanup. Separate pure
parsing, reconstruction, and decisions from filesystem, subprocess, signal, and
standard-stream operations. Give every function a succinct explanatory docstring
and one clear responsibility. Keep the existing callable interfaces compatible.
No dependency, matcher, timeout setting, or runtime patch changes are included.

The orchestrator owns the deadline wrapper and integration; the implementer owns
the classifier. The spec writer owns new patch reconstruction characterization
coverage. The independent runner verifies the frozen result; the reviewer checks
behavior preservation and readability. Existing test files remain unchanged.

This is a behavior-preserving refactor: existing tests and added characterization
cases should pass both before and after it. No artificial failing behavior test is
required. The existing narrow-policy and deadline Gherkin specifications remain
the acceptance contract, mapped to `scripts/test_agent_guard*.py`.

## Verification

Before refactoring, all 48 existing guard tests passed under `/usr/bin/python3`
with warnings treated as errors. The classifier SHA-256 was
`b5247cfe3277e13fba2a5804c0033528afcea60e9ac9db9dfcc4b8d940d0195d`;
the wrapper SHA-256 was
`aafd9e838084b30c81188f734a096bb86f1ffba076046ade9ddfa41421021688`.
Both stayed unchanged throughout that run.

Two new characterization cases in `scripts/test_agent_guard_reconstruction.py`
also passed against the unchanged classifier: repeated hunk contexts match only
forward, and an unmatched later hunk does not yield a partial file. The fixture
files remain untouched by inspection. No existing test was edited.

Final checks on frozen sources:

- Both `PYTHONWARNINGS=error python3 -m unittest discover -s scripts -p 'test_agent_guard*.py'`
  and the same command using `/usr/bin/python3` passed all 50 tests. Process cleanup
  checks ran with sandbox escalation for macOS `ps`; no tests were skipped.
- `mix format --check-formatted`, `mix credo --strict`, and `mix dialyzer` passed.
  Credo reported no issues; Dialyzer reported zero errors and zero skipped.
- Differential checks matched the baseline for 4,000 generated classifier inputs
  across five pure APIs and 82 wrapper response-validation cases.
- Independent review found no material findings and confirmed all 42 hook functions
  have docstrings. Existing tests and hook configuration are unchanged.
- `git diff --check` passed. Elixir behavior tests were not rerun for this Python-only
  refactor; the required package formatting and analysis checks above were run.

Verified classifier SHA-256:
`07b8461e897cbdac75ad4bf64ce48877354dbcf84d034f76fb2bdf4161c81a8f`.
Verified wrapper SHA-256:
`28deffad0a463a4247ab5c1b264d8b827c8e49d902d9b3b6ae981307d34bca5c`.

## Code organization

The classifier keeps tokenization, shell inspection, patch reconstruction, and
source comparison pure. `patch_files` reads snapshots; `inspect_event` routes the
request; `evaluate` and `main` retain the existing error and stream boundaries.
The wrapper's `worker_response` decides what output to return from explicit
values. Worker startup, termination, pipe cleanup, signal deadlines, and response
writing have separate named functions. Short orchestration functions compose those
operations without hiding policy inside I/O.

 The prior runtime patch remains uninstalled; this refactor does not establish
live host enforcement.
