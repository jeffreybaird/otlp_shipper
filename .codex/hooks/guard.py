#!/usr/bin/env python3
"""Narrow review reminders, not intent detection or a security boundary."""
import ast
from collections import Counter
import json
from pathlib import Path
import re
import shlex
import sys

TEST_REVIEW = (
    "Review the proposed existing test/fixture/helper/doctest change against the "
    "original contract, user request, implementation, and failure evidence. If it "
    "conceals a defect, restore the intended tests and fix the implementation. "
    "User-authorized contract changes, stronger coverage, and contract-preserving "
    "refactors may proceed. Otherwise present the exact contract change and reason "
    "for human review. This contextual reminder does not pause the pending write "
    "and does not establish intent."
)
ANALYSIS_REVIEW = (
    "Review the proposed static-analysis suppression, exclusion, disabled rule, or "
    "removed check. Fix the code and its diagnostics instead of bypassing analysis "
    "to make verification pass. A necessary exception needs explicit human "
    "authorization; agents cannot approve one another. This contextual reminder "
    "does not pause the pending write or establish intent."
)
MASKING_REASON = (
    "This analyzer command explicitly masks failure status. Run the check without "
    "exit masking and fix its diagnostics. A necessary analysis exception requires "
    "explicit human authorization."
)
COMMENT_SUPPRESSION = re.compile(
    r"(?i)\b(?:rubocop\s*:\s*(?:disable|todo)|noqa\b|nolint\b|"
    r"eslint-disable\b|credo:disable\b|type:\s*ignore\b|pyright:\s*ignore\b|"
    r"mypy:\s*ignore-errors\b|pylint:\s*disable\b|ruff:\s*noqa\b)"
)
ANALYZERS = {"dialyzer", "rubocop", "ruff", "mypy", "pyright", "pylint", "eslint", "credo"}
SOURCE_SUFFIXES = {".ex", ".exs", ".rb", ".py", ".js", ".ts", ".tsx", ".jsx", ".sh"}


def response(context=None, denial=None):
    output = {"hookEventName": "PreToolUse"}
    if denial:
        output.update(permissionDecision="deny", permissionDecisionReason=denial)
    else:
        output["additionalContext"] = context
    return {"hookSpecificOutput": output}


def lexical_views(text):
    """Mask quoted strings for code inspection; retain strings in comparison tokens.

    This deliberately small lexer supports ordinary and triple-quoted literals and
    line/block comments. It is not a language parser (e.g. arbitrary Ruby heredocs).
    """
    code, comments, tokens = [], [], []
    index = 0
    while index < len(text):
        char = text[index]
        if char in "\"'`":
            marker = char * 3 if text.startswith(char * 3, index) else char
            end = index + len(marker)
            while end < len(text):
                if text[end] == "\\":
                    end += 2
                elif text.startswith(marker, end):
                    end += len(marker)
                    break
                else:
                    end += 1
            literal = text[index:end]
            tokens.append(literal)
            code.append("".join("\n" if c == "\n" else " " for c in literal))
            index = end
        elif char == "#" or text.startswith("//", index) or text.startswith("/*", index):
            block = text.startswith("/*", index)
            end = text.find("*/" if block else "\n", index + 1)
            end = len(text) if end < 0 else end + (2 if block else 0)
            comment = text[index:end]
            comments.append(comment)
            code.append("".join("\n" if c == "\n" else " " for c in comment))
            index = end
        else:
            code.append(char)
            if not char.isspace():
                # Words/operators are tokens: preserve string contents and avoid
                # confusing `foo bar` with `foobar` while tolerating indentation.
                match = re.match(r"[\w]+|[^\w\s]", text[index:])
                token = match.group(0)
                tokens.append(token)
                code.extend(token[1:])
                index += len(token)
            else:
                index += 1
    return "".join(code), comments, tokens


def test_path(path):
    return (bool(set(path.parts) & {"test", "tests", "fixtures", "features"})
            or path.name.startswith("test_") or path.name.endswith(("_test.exs", "_test.py", ".feature")))


def preserves_tokens(before, after):
    """Existing tokens in order permit additions and whitespace-only changes."""
    if before == after:
        return True
    remaining = iter(after)
    return all(any(item == token for item in remaining) for token in before)


def doctests(text):
    """Extract prompt/output blocks so neighboring production edits are ignored."""
    blocks, current = [], []
    indent = 0
    for line in text.splitlines():
        stripped = line.strip()
        if re.match(r"(?:iex(?:\([^)]*\))?>|>>>|\.\.\.)", stripped):
            if not current:
                indent = len(line) - len(line.lstrip())
            current.append(line)
        elif current:
            if (not stripped or stripped in {'"""', "'''"}
                    or len(line) - len(line.lstrip()) < indent
                    or re.match(r"(?:def|defp|class|end|@doc|@spec)\b", stripped)):
                blocks.append(lexical_views("\n".join(current))[2])
                current = []
            else:
                current.append(line)
    if current:
        blocks.append(lexical_views("\n".join(current))[2])
    return blocks


def assertion_contracts(path, text):
    """Compare assertions, including Python control-flow around each assertion."""
    if path.suffix == ".py":
        try:
            tree = ast.parse(text)
        except SyntaxError:
            pass
        else:
            contracts = []

            def visit(node, controls=()):
                if isinstance(node, (ast.If, ast.While, ast.For, ast.Try, ast.With)):
                    # Record only the controlling expressions, not the body:
                    # adding a separate assertion must not change old contracts.
                    controls += ((type(node).__name__, tuple(
                        ast.dump(value, include_attributes=False)
                        for name, value in ast.iter_fields(node)
                        if isinstance(value, ast.AST) and name not in {"body", "orelse"})),)
                if isinstance(node, ast.Assert):
                    contracts.append((ast.dump(node, include_attributes=False), controls))
                for child in ast.iter_child_nodes(node):
                    visit(child, controls)

            visit(tree)
            return Counter(contracts)
    return Counter(tuple(lexical_views(line)[2]) for line in text.splitlines()
                   if re.match(r"\s*(?:assert|refute)\b", line))


def test_change(path, before, after):
    old_code, _, old_tokens = lexical_views(before)
    new_code, _, new_tokens = lexical_views(after)
    if test_path(path) and before:
        skip = r"@(?:module)?tag\s+:skip\b|\bskip\s*[:(]|\b(?:xit|xdescribe)\s*\("
        if len(re.findall(skip, new_code)) > len(re.findall(skip, old_code)):
            return True
        if (assertion_contracts(path, before) - assertion_contracts(path, after)
                or not preserves_tokens(old_tokens, new_tokens)):
            return True
    # Compare entire pre/post source, including output-only doctest edits.
    old_blocks = Counter(tuple(block) for block in doctests(before))
    new_blocks = Counter(tuple(block) for block in doctests(after))
    return bool(old_blocks - new_blocks)


def shell_segments(command):
    """Split only unquoted shell operators; shlex handles each simple command."""
    segments, start, index, quote = [], 0, 0, None
    while index < len(command):
        char = command[index]
        if char == "\\" and quote != "'":
            index += 2
            continue
        if quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "#" and (index == 0 or command[index - 1].isspace()
                              or command[index - 1] in ";|&()"):
            end = command.find("\n", index)
            index = len(command) if end < 0 else end
            continue
        elif char in ";|&\n":
            operator = char
            if char in "|&" and command[index:index + 2] == char * 2:
                operator *= 2
            segments.append((command[start:index], operator))
            index += len(operator)
            start = index
            continue
        index += 1
    segments.append((command[start:], ""))
    return [(shlex.split(part, comments=True), operator) for part, operator in segments]


def is_analyzer(words):
    words = list(words)
    while words and (re.match(r"^[A-Za-z_]\w*=", words[0]) or words[0] in {"env", "command", "exec"}):
        words.pop(0)
    if words[:2] == ["bundle", "exec"]:
        words = words[2:]
    if not words:
        return False
    executable = Path(words[0]).name
    return (executable in ANALYZERS
            or executable == "mix" and len(words) > 1 and words[1] in {"dialyzer", "credo"}
            or executable in {"python", "python3"} and len(words) > 2
            and words[1] == "-m" and words[2] in ANALYZERS)


def shell_masking(command):
    pending = False
    previous = ""
    for words, operator in shell_segments(command):
        analyzer = is_analyzer(words)
        if analyzer and any(word.split("=", 1)[0] in {
                "--ignore-exit-status", "--ignore_exit_status", "--exit-zero", "--exit_zero"}
                for word in words):
            return True
        if pending and (previous == "||" and words in (["true"], [":"], ["exit", "0"])
                        or previous in {";", "\n"} and words == ["exit", "0"]):
            return True
        pending = analyzer or pending and previous in {"&&", "||"}
        previous = operator
    return False


def analysis_signatures(path, text):
    """Count active suppression syntax, never prose or quoted fixture examples."""
    if path.suffix in {".md", ".rst", ".txt", ".feature"}:
        return Counter()
    code, comments, _ = lexical_views(text)
    signatures = []
    if path.suffix in SOURCE_SUFFIXES:
        signatures += [match.group(0).lower() for comment in comments
                       for match in COMMENT_SUPPRESSION.finditer(comment)]
        signatures += re.findall(r"@dialyzer\s*[^\n]*\b(?:nowarn_function|no_[a-z_]+)\b", code)
    config = (path.name.startswith((".rubocop", ".credo", ".dialyzer", ".ruff", ".eslintrc"))
              or path.name in {"mix.exs", "pyproject.toml", "setup.cfg", "mypy.ini", "eslint.config.js"}
              or ".github" in path.parts)
    if config:
        signatures += re.findall(
            r"(?im)\b(?:Enabled:\s*false|enabled:\s*false|warnings_as_errors:\s*false|"
            r"ignore_warnings\s*:|ignore_exit_status\s*:\s*true|continue-on-error:\s*true|"
            r"Exclude\s*:|exclude\s*[:=]|ignore\s*=|disable\s*=)", code)
        # Include exclusion entries, so extending an existing list is visible.
        # YAML quoted paths are values here, not executable suppression examples.
        list_indent = None
        for line in text.splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            indent = len(line) - len(line.lstrip())
            if list_indent is not None and indent > list_indent:
                if line.lstrip().startswith("-"):
                    signatures.append("exclusion-entry:" + line.strip())
                continue
            list_indent = None
            if re.match(r"\s*(?:Exclude|exclude|ignore)\s*:\s*$", line):
                list_indent = indent
    return Counter(signatures)


def analysis_commands(path, text, masking=False):
    if path.suffix not in {".sh", ".yml", ".yaml"} and path.name != "Makefile":
        return Counter()
    commands = []
    for line in text.splitlines():
        stripped = re.sub(r"^\s*(?:-\s*)?run:\s*", "", line).strip()
        if stripped.startswith("#"):
            continue
        try:
            if masking:
                if shell_masking(stripped):
                    commands.append("masked-analyzer")
                continue
            for words, _ in shell_segments(stripped):
                if is_analyzer(words):
                    # Options/formatting changes alone do not remove the check.
                    commands.append(next(word for word in words if Path(word).name in ANALYZERS))
        except ValueError:
            continue
    return Counter(commands)


def patch_files(patch, cwd):
    """Read targets and reconstruct before/after for ordinary apply_patch hunks.

    Unsupported/malformed hunks are left to the patch tool; never deny them as a
    third policy category. File moves themselves do not change the contract.
    """
    lines = patch.splitlines()
    index = 0
    while index < len(lines):
        match = re.match(r"\*\*\* (Add|Update|Delete) File: (.+)$", lines[index])
        if not match:
            index += 1
            continue
        operation, name = match.groups()
        path = Path(name)
        target = cwd / path
        before = target.read_text() if target.is_file() else ""
        index += 1
        body = []
        while index < len(lines) and not re.match(r"\*\*\* (?:Add|Update|Delete) File:|\*\*\* End Patch", lines[index]):
            body.append(lines[index])
            index += 1
        if operation == "Delete":
            yield path, before, ""
        elif operation == "Add":
            yield path, before, "\n".join(line[1:] for line in body if line.startswith("+")) + "\n"
        else:
            current = before.splitlines()
            cursor, hunks, hunk = 0, [], []
            for line in body:
                if line.startswith("@@"):
                    if hunk:
                        hunks.append(hunk)
                    hunk = []
                elif line[:1] in {" ", "+", "-"}:
                    hunk.append(line)
            if hunk:
                hunks.append(hunk)
            valid = True
            for hunk in hunks:
                old = [line[1:] for line in hunk if line[0] != "+"]
                new = [line[1:] for line in hunk if line[0] != "-"]
                position = next((pos for pos in range(cursor, len(current) + 1)
                                 if current[pos:pos + len(old)] == old), None)
                if position is None:
                    valid = False
                    break
                current[position:position + len(old)] = new
                cursor = position + len(new)
            if valid:
                yield path, before, "\n".join(current) + ("\n" if before.endswith("\n") else "")


def inspect_event(payload):
    if not isinstance(payload, dict) or payload.get("hook_event_name") != "PreToolUse":
        return None
    name = payload.get("tool_name")
    args = payload.get("tool_input")
    if name not in {"Bash", "apply_patch"} or not isinstance(args, dict):
        return None
    command = args.get("command")
    if not isinstance(command, str):
        return None
    if name == "Bash":
        return response(denial=MASKING_REASON) if shell_masking(command) else None
    reminders = []
    for path, before, after in patch_files(command, Path(payload.get("cwd", "."))):
        if test_change(path, before, after):
            reminders.append(TEST_REVIEW)
        if (analysis_signatures(path, after) - analysis_signatures(path, before)
                or analysis_commands(path, before) - analysis_commands(path, after)
                or analysis_commands(path, after, masking=True)
                - analysis_commands(path, before, masking=True)):
            reminders.append(ANALYSIS_REVIEW)
    return response(context="\n".join(dict.fromkeys(reminders))) if reminders else None


def evaluate(payload):
    try:
        return inspect_event(payload)
    except (ValueError, OSError, TypeError) as exc:
        print("Narrow guard could not inspect input: " + type(exc).__name__, file=sys.stderr)
        return None


def main():
    try:
        result = evaluate(json.load(sys.stdin))
        if result:
            print(json.dumps(result))
    except (ValueError, OSError, TypeError) as exc:
        print("Narrow guard could not inspect input: " + type(exc).__name__, file=sys.stderr)


if __name__ == "__main__":
    main()
