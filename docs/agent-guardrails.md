# Human approval guardrails

The repository's [hook definition](../.codex/hooks.json) runs
[guard.py](../.codex/hooks/guard.py) before supported tool calls. It uses Python 3.9+
and Git, with no Python packages. It denies protected operations; it never emits an
approval decision or writes an approval token.

## Activate once, then verify

1. Review `.codex/config.toml`, `.codex/agents/*.toml`, `.codex/hooks.json`, and the
   hook script. Open a new Codex session in this repository with the project trusted.
2. Open `/hooks` in Codex and personally review/trust the hook definition. A project
   file alone does not activate an untrusted hook. Changed definitions require trust
   again. Do not use `--dangerously-bypass-hook-trust` or disable hooks.
3. Run the five commands below in a normal terminal. Confirm a
   live Codex `apply_patch` attempt to change an existing test is denied before any
   write. Use a disposable checkout for this activation test. Then confirm a new
   ordinary test file can be added and a documented verification command can run.
4. Confirm the host discovers all five custom agents. Older hosts may need an update.
   The primary session reads the orchestrator directive; it is not automatically
   replaced by the custom orchestrator definition.

```sh
python3 scripts/test_agent_guard.py
python3 scripts/test_agent_guard_workflow.py
python3 scripts/test_agent_guard_paths.py
python3 scripts/test_agent_guard_orchestration.py
python3 scripts/test_agent_guard_optional_checks.py
```

Do not claim enforcement is active until trust and the live denial check succeed.
This change was developed on Codex CLI 0.153.4; classifier tests do not prove desktop
hook activation. Hooks are reloaded according to the host lifecycle; a running task
may continue using its original configuration until restarted.

## Protected changes

All existing tests are protected, including untracked files, helper/fixture trees,
Gherkin scenarios, test harness scripts, and doctests. Rename, delete, formatting,
and delete/recreate operations count as edits. A new test file is allowed; once it
exists it is protected. This deliberately requires the spec writer to prepare a
complete new file or obtain approval for corrections.

The guard conservatively protects whole files containing doctests and verification
configuration, not just assertion lines. Changes to Mix configuration, CI, formatter,
analysis configuration, agent/hook configuration, and workflow/style policy need
review even if the intended change is harmless. Known inline skip/suppression forms
are rejected in new or edited files. Arbitrary semantic rule weakening cannot be
fully recognized by string matching; all agents and the reviewer must enforce the
broader requirement from AGENTS.md.

When blocked, prepare the exact proposed diff and explain why it is needed, what
behavior/assertions/rules change, and how it will be checked. Ask for human approval
with a link to the governing instruction. The human reviews and applies that patch
outside the agent, then tells the orchestrator to resume. Reinspect the actual diff
and rerun checks. Approval of one patch never authorizes a later revision. No agent,
including the orchestrator or reviewer, may grant approval or apply the protected
patch through another tool. General task authorization does not waive this gate.

## Shell and tool boundaries

Use `apply_patch` for edits. The shell guard allows documented verification commands
and a small set of reads and PR operations. Submit one command per call: shell
chaining, expansion, redirection, arbitrary interpreters, and unclassified scripts
are blocked because they can modify tests without using `apply_patch`.
Use `git diff --no-ext-diff --no-textconv` for diff inspection.

Opaque tool execution is denied when visible to PreToolUse. Do not use code-mode
wrappers, MCP file editors, interactive shells, or another runtime to evade checks.
Codex does not invoke PreToolUse again for `write_stdin` input to an existing process;
never start an interactive shell as an editing path. Checks execute repository code
and can write build artifacts. This guard is an accident-prevention mechanism, not
an OS security boundary against malicious code or a compromised agent. Protecting
against hostile changes requires independently managed sandbox/server enforcement.
Hook crashes/timeouts, untrusted hooks, unsupported tools, and external editors can
escape this classifier's control. Malformed input that reaches the script returns
a supported denial. Keep human review and independent final diff review mandatory.

## Sources and supported behavior

The [official hooks reference](https://learn.chatgpt.com/docs/hooks) documents
project hook discovery and trust, the PreToolUse denial schema, tool coverage, and
unsupported `permissionDecision: "ask"`. That value currently fails open, so this
harness intentionally denies and uses human-applied patches instead.
The [official subagent reference](https://learn.chatgpt.com/docs/agent-configuration/subagents)
documents `.codex/agents/*.toml` and per-role model configuration.
