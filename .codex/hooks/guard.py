#!/usr/bin/env python3
"""Conservative Codex edit guard; not a sandbox or a shell interpreter."""
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys

APPROVAL = ("Human approval required. Present the exact proposed patch and reason; "
            "the human must review and apply protected changes outside the agent. "
            "Do not bypass this guard or create an approval token.")
SUPPRESSION = re.compile(r"(?i)(credo:disable|formatter:off|format:\s*off|noqa|nolint|"
                         r"eslint-disable|@dialyzer|@tag\s+:skip|@moduletag\s+:skip|"
                         r"skip:\s*true|warnings_as_errors:\s*false|"
                         r"ignore_warnings|ignore_exit_status|continue-on-error|"
                         r"dialyzer.*ignore|exclude:\s*\[)")


def protected(path):
    """Protect whole test/support trees and configuration conservatively."""
    parts = path.parts
    return (any(p in {"test", "tests", "features", "fixtures", ".codex", ".github", ".git", "scripts"}
                for p in parts)
            or path.name.startswith(("test_", ".formatter", ".credo", ".dialyzer"))
            or path.name.endswith(("_test.exs", "_test.py", ".feature"))
            or path.name in {"mix.exs", "mix.lock", ".tool-versions", "AGENTS.md",
                             ".pre-commit-config.yaml", "Makefile", "PLAN.md"}
            or str(path) in {"docs/elixir-style.md", "docs/testing.md", "docs/codex-agents.md",
                             "docs/agent-guardrails.md"})


def repository(cwd):
    result = subprocess.run(["git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
                            text=True, capture_output=True, check=True, timeout=3)
    return Path(result.stdout.strip()).resolve()


def patch_reason(command, root, cwd):
    lines = command.splitlines()
    if not lines or lines[0] != "*** Begin Patch" or lines[-1] != "*** End Patch":
        return "Malformed patch."
    seen = False
    for line in lines[1:-1]:
        match = re.match(r"^\*\*\* (Add File|Update File|Delete File|Move to): (.+)$", line)
        if match:
            seen = True
            operation, name = match.groups()
            raw = Path(name)
            unresolved = cwd / raw
            if any(p.is_symlink() for p in [unresolved, *unresolved.parents]):
                return "Edits through symlinks require review."
            target = unresolved.resolve()
            if not target.is_relative_to(root):
                return "Patch escapes the repository or follows an external symlink."
            relative = target.relative_to(root)
            # Never permit Add File to replace a file or a dangling symlink.
            exists = target.exists() or (cwd / raw).is_symlink()
            if operation == "Add File" and exists:
                return "Add File would replace an existing file."
            if operation != "Add File" and not exists and operation != "Move to":
                return "Patch target does not exist."
            if protected(relative) and (exists or operation != "Add File"):
                return "Existing tests or verification configuration are protected."
            # Configuration additions can disable rules too; only new tests are exempt.
            if operation == "Add File" and (".git" in relative.parts or ".codex" in relative.parts or
                    ".github" in relative.parts or relative.name in {"mix.exs", "AGENTS.md"}
                    or relative.name.startswith((".formatter", ".credo", ".dialyzer"))):
                return "Verification configuration requires review, including new files."
            if exists and target.is_file():
                content = target.read_text(errors="replace")
                if re.search(r"iex>|>>>|\bdoctest\b", content):
                    return "File contains existing doctests; changes require review."
            continue
        if line.startswith("*** ") and line not in {"*** End of File"}:
            return "Unknown patch directive."
        if line.startswith("+") and SUPPRESSION.search(line[1:]):
            return "Potential lint, style, or test suppression."
    return None if seen else "Patch has no file operations."


def delivery_allowed(words):
    """Narrow publication grammar; no hook bypass, force push, merge, or close."""
    if words in [["scripts/package_smoke.sh"],
                 ["OTLP_SMOKE_DEPENDENCY_SET=minimum", "scripts/package_smoke.sh"],
                 ["OTLP_SMOKE_DEPENDENCY_SET=minimum_with_tracing", "scripts/package_smoke.sh"],
                 ["gh", "auth", "status"]]:
        return True
    if words[:3] == ["git", "switch", "-c"]:
        return (len(words) == 4 and re.fullmatch(r"codex/[A-Za-z0-9][A-Za-z0-9_/-]*", words[3])
                is not None and "//" not in words[3] and not words[3].endswith("/"))
    if words[:3] == ["shasum", "-a", "256"]:
        return len(words) > 3 and all(p and not p.startswith("-") for p in words[3:])
    if words[:2] == ["git", "add"]:
        paths = words[2:]
        if paths[:1] == ["--"]:
            paths = paths[1:]
        return bool(paths) and all(p and not p.startswith(("-", ":")) for p in paths)
    if words[:2] == ["git", "commit"]:
        return len(words) == 4 and words[2] in {"-m", "--file"} and not words[3].startswith("-")
    if words[:2] == ["git", "push"]:
        return len(words) in {2, 3, 4} and all(
            re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_./-]*", p) for p in words[2:])
    if words[:2] != ["gh", "pr"] or len(words) < 3:
        return False
    action = words[2]
    args = words[3:]
    if action in {"view", "checks"}:
        return not args or (len(args) == 1 and args[0].isdigit())
    if action not in {"create", "edit"}:
        return False
    if action == "edit" and args and args[0].isdigit():
        args = args[1:]
    options = {"--title", "--body-file", "--base", "--head"} if action == "create" else {"--title", "--body-file"}
    index = 0
    while index < len(args):
        if args[index] == "--draft" and action == "create":
            index += 1
        elif args[index] in options and index + 1 < len(args) and not args[index + 1].startswith("-"):
            index += 2
        else:
            return False
    return bool(args)


def shell_reason(command):
    # Do not try to infer arbitrary program side effects from command strings.
    if any(c in command for c in "\n\r;&|<>`$(){}\\"):
        return "Shell control syntax, expansion, or redirection requires review."
    try:
        words = shlex.split(command)
    except ValueError:
        return "Malformed shell command."
    if not words:
        return "Empty command."
    if delivery_allowed(words):
        return None
    if words[0] == "mix":
        fixed = {("deps.get",), ("format", "--check-formatted"),
                 ("compile", "--warnings-as-errors"), ("test",), ("test", "--cover"),
                 ("otlp_shipper.conformance",), ("dialyzer",),
                 ("hex.audit",), ("docs", "--warnings-as-errors"), ("hex.build",)}
        args = tuple(words[1:])
        if args in fixed:
            return None
        if args and args[0] == "test" and all(
                re.fullmatch(r"test/[\w/.-]+_test\.exs(?::\d+)?", x)
                and ".." not in Path(x.split(":")[0]).parts for x in args[1:]):
            return None
        return "Only the documented verification commands are allowed."
    if words[0] in {"cat", "head", "tail", "wc", "pwd", "ls"}:
        return None
    if words[0] == "rg":
        if any(w in {"--pre", "--hostname-bin"} or w.startswith(("--pre=", "--hostname-bin=")) for w in words[1:]):
            return "Ripgrep helper programs can execute arbitrary commands."
        return None
    if words[0] == "git" and len(words) > 1:
        safe = {"status", "diff", "show", "log", "ls-files", "rev-parse"}
        if words[1] in safe and not any(
                w.startswith(("--ext-diff", "--textconv", "--output", "--exec"))
                for w in words[2:]):
            # Disable configured external diff and text conversion explicitly.
            if words[1] in {"diff", "show", "log"} and not {
                    "--no-ext-diff", "--no-textconv"}.issubset(words):
                return "Git content reads require --no-ext-diff --no-textconv."
            return None
    if len(words) == 2 and words[0] in {"python3", "/usr/bin/python3"} and words[1] in {
            "scripts/test_agent_guard.py", "scripts/test_agent_guard_workflow.py",
            "scripts/test_agent_guard_paths.py", "scripts/test_agent_guard_orchestration.py",
            "scripts/test_agent_guard_optional_checks.py"}:
        return None
    return "Unclassified execution requires human review; use apply_patch for ordinary edits."


def evaluate(payload):
    if not isinstance(payload, dict) or payload.get("hook_event_name") != "PreToolUse":
        return "Malformed hook event."
    name = payload.get("tool_name")
    args = payload.get("tool_input")
    if not isinstance(args, dict):
        return "Malformed tool input."
    if name in {"Bash", "apply_patch"}:
        command = args.get("command")
        if not isinstance(command, str):
            return "Missing command string."
        if name == "Bash":
            return shell_reason(command)
        cwd = Path(payload["cwd"]).resolve()
        return patch_reason(command, repository(cwd), cwd)
    if name in {"view_image", "update_plan", "spawn_agent", "send_message",
                "wait", "wait_agent", "list_agents", "close_agent", "resume_agent"}:
        return None
    return "Opaque tools and interactive input are not approved write paths."


def main():
    try:
        reason = evaluate(json.load(sys.stdin))
    except Exception as exc:
        reason = "Guard could not validate the operation: " + type(exc).__name__
    if reason:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": reason + " " + APPROVAL}}))


if __name__ == "__main__":
    main()
