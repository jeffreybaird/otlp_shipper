> Historical setup reference. For current roles, workflow, and enforcement,
> follow [shared project guidance](../.docs/project-guidance.md) and
> [the agent workflow](../.docs/agent-workflow.md). The legacy setup below
> is not the active workflow or a description of current hook behavior.

# Narrow test and static-analysis review

The [hook definition](../.codex/hooks.json) runs the
[deadline wrapper](../.codex/hooks/run_guard.py), which invokes
[guard.py](../.codex/hooks/guard.py), only for canonical `Bash` and `apply_patch`
tool events. The classifier has two concerns:

1. Existing tests being changed to accommodate defective implementation code.
2. Static-analysis tools being bypassed instead of their diagnostics being fixed.

There is no tool/command allowlist, blanket test-file lock, or blanket protection
of configuration, scripts, instructions, or files containing doctests. Web research,
subagents, ordinary shell work, new tests, and unrelated edits are outside its scope.
The sandbox and other permission policies still apply independently.

## Contextual review versus denial

A patch cannot establish intent or whether the user authorized a new contract.
Potential changes to existing expectations, assertions, fixtures, skips, or coverage
produce a nonblocking `additionalContext` review reminder. The agent must compare
those changes with the original contract, user request, implementation, and any
failure evidence. If a change conceals a defect, restore the intended test contract
and fix the code. Authorized contract changes may proceed; unresolved contract
changes require human review of the exact change and reason. Ordinary test formatting,
renames, stronger/additional coverage, and contract-preserving refactors need no
separate approval. Some refactors may still produce a reminder.

Potential static-analysis suppressions, exclusions, disabled rules, or removed
checks likewise receive contextual review. Their necessity and authorization cannot
be determined from syntax alone. A legitimate exception needs explicit human
permission. Documentation and quoted regression fixtures describing bypass syntax
are not themselves analysis bypasses.

Concrete analyzer commands that mask failure status are denied, such as
`mix dialyzer --ignore-exit-status`, `ruff check --exit-zero`, or
`bundle exec rubocop || true`. Run the real check and fix its diagnostics. A focused
analysis run is allowed; it does not substitute for the required full check.

A context reminder does **not** pause the pending write or require a human click.
It supports agent and independent reviewer judgment; it is not a semantic proof
that tests were preserved. The hook never grants sandbox permission, rewrites tool
inputs, issues approval tokens, or treats unknown operations as forbidden.

## Detection limits

The implementation recognizes common patch and analyzer syntax. It is not a full
Elixir/Ruby/Python parser, shell interpreter, or malicious-agent security boundary.
External editors, arbitrary scripts, MCP writes, and interactive input are not
intercepted by this hook. The classifier still ignores unsupported inputs and catches
some inspection errors internally. The wrapper cannot recognize an inspection error
that the classifier turns into a successful empty response. Keep independent diff
review and all normal verification requirements.

## Execution failures and deadlines

The wrapper gives the classifier five seconds and bounds its own input reading and
inspection to seven seconds. The host hook timeout remains ten seconds. A child
timeout, nonzero exit, spawn failure, or malformed/unsupported output produces an
explicit `PreToolUse` denial. Timed-out child processes are killed and reaped.
Valid contextual reminders and explicit denials pass through unchanged. A successful
empty response still permits the pending call; stderr alone does not cause denial.

On an execution failure, stop the pending tool call and diagnose the hook. Do not
repeat the call or switch tools merely to bypass that failure. After repairing the
cause, verify the hook before retrying the intended operation.

This local wrapper is **not an absolute fail-closed guarantee**. Source inspection
of Codex 0.153.4 found that the host's outer hook timeout fails open. Failures before
the wrapper starts (including Git path resolution or Python startup), wrapper/host
termination, and the outer deadline can still prevent it from returning a denial.
The source patch intended to close that runtime gap is being tested separately in
`/tmp/codex-fail-closed-0.153.4`; it is not installed in the running host. The planned
patch artifact is `docs/patches/codex-0.153.4-pretool-fail-closed.patch`. Do not claim
runtime enforcement from a repository patch or a local wrapper test. See the
[work record](workflows/guard-deadline.md) for verification status.

## Activation and verification

The changed command requires the user to review and trust it through `/hooks`.
Do not silently trust or enable it on the user's behalf. Host
lifecycle may require a fresh session. Changing repository files alone does not
prove live enforcement.

Run the regression suites:

```sh
python3 -m unittest discover -s scripts -p 'test_agent_guard*.py'
```

Then verify the live host with harmless examples: web research and a quoted `rg`
pattern should run; a test expectation edit in a disposable checkout should produce
contextual review; a synthetic analysis command with failure masking should be
blocked before execution. Check both the hook output and the actual host behavior.
Do not use production tests as disposable activation fixtures.

## Sources

The [official hooks reference](https://learn.chatgpt.com/docs/hooks) documents the
canonical tool names and matcher aliases, command handlers, `deny`, and nonblocking
`additionalContext`. Prompt/agent handlers are parsed but not executed. This hook
uses the supported command protocol; it does not launch a nested model or infer
human approval from an agent-authored field.

<!-- BEGIN MANAGED AGENT WORKFLOW -->
Shared native agent workflow version 2.0.0 applies to every behavior
change. This section supersedes legacy workflow, role-assignment, and blanket
test-edit approval instructions only. Preserve domain, privacy, coverage,
static-analysis, deployment, and project constraints. Follow [.docs/agent-workflow.md](../.docs/agent-workflow.md) for role ownership,
red → accepted tests → implementation → green → independent review.
Accepted tests are a contract: only the test writer changes them when the
expected behavior changes, with renewed review. Never weaken tests to pass.
The orchestrator coordinates the pipeline. This hook restricts only direct source
and test edits; other files, tools and commands retain ordinary native permissions.
Do not use alternate editing routes to evade the source/test ownership workflow.
<!-- END MANAGED AGENT WORKFLOW -->
