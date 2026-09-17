# Feature: Guard execution deadlines

## Scope and ownership

The user requested that a hook timeout stop the pending tool call. The local
implementation wraps the existing narrow Python guard and changes its command
entry point. It does not change Elixir runtime behavior, package tests, or the
classifier's two review concerns.

Branch: `codex/fail-closed-hook`. Base revision:
`930de2d074f38d4850ea00e8b34326d99f7e1ae9`.
The orchestrator owns wrapper/config integration, runtime investigation, and final
verification. The spec writer owns Python regressions. The documentation worker
owns this record, the acceptance specification, and guardrail guidance. Independent
runner/reviewer evidence is required before completion.

## Contract and limits

The wrapper uses a five-second classifier deadline, a seven-second entry deadline
covering stdin, and the unchanged ten-second host timeout. Nonzero exit, spawn
failure, timeout, and malformed or unsupported output become explicit denials.
Valid reminders and denials retain their original output. Successful empty output
remains allowed, even with stderr. The existing classifier still catches some
inspection errors internally; this change does not make those detectable.

Codex 0.153.4 source inspection established that outer hook timeout handling fails
open. The wrapper reduces exposure but cannot cover failures before it starts,
Git/Python startup failures, wrapper/host termination, or all outer-deadline cases.
An upstream runtime source patch was tested separately at
`/tmp/codex-fail-closed-0.153.4`. Patch artifact:
`docs/patches/codex-0.153.4-pretool-fail-closed.patch`. The patch is **not installed**;
the running host must not be described as fully fail-closed.

The changed hook needs user review/trust through `/hooks`. Repository edits and
subprocess tests do not prove live enforcement. On hook failure, block the pending
call and diagnose the cause; do not retry or choose another tool to bypass it.

## Scenario mapping

[GD-01 through GD-05](../features/guard-deadline.feature) map to
`scripts/test_agent_guard_deadline.py` and
`scripts/test_agent_guard_entry_deadline.py`: successful-output/stdin tests,
invalid-output and failure tests, timeout cleanup, entry-deadline coverage, and
CLI classification tests. Existing narrow/boundary/review suites retain classifier
coverage. GD-06 requires runtime source tests and separately verified installation;
local Python tests cannot prove it. These are Python tooling scenarios and are not
registered in CucumberEx. Elixir tests and Collector integration are inapplicable.

## Verification status

- `PYTHONWARNINGS=error python3 -m unittest discover -s scripts -p 'test_agent_guard*.py'`: 48 passed.
- The same command with `/usr/bin/python3`: 48 passed. Both runs had no warnings.
- Process-tree tests required an unsandboxed retry because macOS denied `ps` in
  the sandbox. The tests were not skipped.
- On the original Codex error-handling branch, the four new runtime regressions
  produced three expected failures and one pass. The failures demonstrate
  synchronous timeout, spawn, and I/O errors permitting the pending call.
- With the runtime fix, `just test -p codex-hooks`: 179 passed, zero skipped.
  The timeout test uses a real sleeping command, and verifies a successful
  competing input rewrite cannot override the timeout's block decision.
- Upstream `just fmt` passed after temporary test/formatter tools were installed.
- `just fix -p codex-hooks` passed; Clippy made no further hook-source changes.
- The exported patch passed `git apply --reverse --check` against the patched checkout.

The runtime checkout is tag `rust-v0.153.4`, source commit
`3d2ee51ca2d5db578f328aa75e20aa22c0197c9a`, using its pinned Rust 1.95.0.
Cargo normalized workspace package versions in its local lockfile from 0.0.0 to
0.153.4; no dependency updates are included in the patch. The installed application
was not rebuilt or replaced. Full app-server/end-to-end installation verification
remains outstanding; the crate tests do not constitute live host activation.

Review finding HTO-01 requested held-open stdin and inherited-pipe descendant
coverage. Both were added in the new entry-deadline suite and passed on both Python
versions. The direct worker is reaped; tests establish descendants terminate but
do not claim the wrapper can reap grandchildren.
