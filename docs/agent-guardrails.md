# Narrow test and static-analysis review

The [hook definition](../.codex/hooks.json) runs [guard.py](../.codex/hooks/guard.py)
only for canonical `Bash` and `apply_patch` tool events. It has two concerns:

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
intercepted by this hook. Invalid or unsupported input and inspection errors do not
create a third category of denied work. Check stderr for inspection diagnostics.
Keep independent diff review and all normal verification requirements.

## Activation and verification

The user deactivated the old hook during this update. Do not silently reactivate it.
Review the changed definition in `/hooks` and trust/enable it when ready. Host
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
