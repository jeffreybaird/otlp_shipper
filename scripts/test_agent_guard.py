#!/usr/bin/env python3
"""Exercise the Codex guard in disposable repositories, without mutating tests."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GUARD = Path(__file__).resolve().parents[1] / ".codex/hooks/guard.py"
spec = importlib.util.spec_from_file_location("agent_guard", GUARD)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class AgentGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def existing(self, name, content="old\n"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def check_patch(self, body):
        return guard.evaluate({"hook_event_name": "PreToolUse", "tool_name": "apply_patch",
                               "cwd": str(self.root), "tool_input": {
                                   "command": "*** Begin Patch\n" + body + "\n*** End Patch"}})

    def test_new_test_allowed_then_protected_immediately(self):
        patch = "*** Add File: test/new_test.exs\n+assert true"
        self.assertIsNone(self.check_patch(patch))
        self.existing("test/new_test.exs", "assert true\n")
        self.assertIsNotNone(self.check_patch(patch))
        self.assertIsNotNone(self.check_patch("*** Update File: test/new_test.exs\n@@\n-assert true\n+assert false"))

    def test_existing_tests_support_fixtures_features_and_guard_locked(self):
        for name in ["test/a_test.exs", "test/support/helper.ex", "test/fixtures/a.bin",
                     "features/example.feature", "scripts/test_agent_guard.py", ".codex/hooks/guard.py"]:
            with self.subTest(name=name):
                self.existing(name)
                self.assertIsNotNone(self.check_patch("*** Delete File: " + name))

    def test_normal_implementation_edit_allowed(self):
        self.existing("lib/example.ex")
        self.assertIsNone(self.check_patch("*** Update File: lib/example.ex\n@@\n-old\n+new"))

    def test_existing_doctest_file_locked(self):
        for content in ["iex> Example.call()\n:ok\n", ">>> calculate()\n1\n", "doctest Example\n"]:
            self.existing("lib/example.ex", content)
            self.assertIsNotNone(self.check_patch("*** Update File: lib/example.ex\n@@\n-old\n+new"))

    def test_lint_ci_and_formatter_files_locked(self):
        for name in ["mix.exs", ".formatter.exs", ".credo.exs", ".github/workflows/ci.yml"]:
            with self.subTest(name=name):
                self.existing(name)
                self.assertIsNotNone(self.check_patch("*** Update File: " + name + "\n@@\n-old\n+new"))

    def test_new_lint_configuration_requires_review(self):
        self.assertIsNotNone(self.check_patch("*** Add File: .credo.exs\n+checks: []"))

    def test_inline_suppressions_denied(self):
        for text in ["# credo:disable-for-this-file", "@dialyzer {:nowarn_function, x: 1}",
                     "@tag :skip", "@moduletag :skip", "warnings_as_errors: false", "# noqa"]:
            with self.subTest(text=text):
                self.assertIsNotNone(self.check_patch("*** Add File: lib/new.ex\n+" + text))

    def test_move_into_existing_test_denied(self):
        self.existing("lib/example.ex")
        self.existing("test/a_test.exs")
        self.assertIsNotNone(self.check_patch("*** Update File: lib/example.ex\n*** Move to: test/a_test.exs\n@@\n-old\n+new"))

    def test_outside_paths_and_symlinks_denied(self):
        self.assertIsNotNone(self.check_patch("*** Add File: ../escaped\n+bad"))
        (self.root / "outside").symlink_to(self.root.parent, target_is_directory=True)
        self.assertIsNotNone(self.check_patch("*** Add File: outside/escaped\n+bad"))

    def test_dangling_symlink_cannot_be_replaced(self):
        (self.root / "dangling").symlink_to(self.root / "missing")
        self.assertIsNotNone(self.check_patch("*** Add File: dangling\n+bad"))

    def test_malformed_patch_denied(self):
        self.assertIsNotNone(guard.patch_reason("bad", self.root, self.root))
        self.assertIsNotNone(self.check_patch("*** Unknown: lib/x\n+bad"))

    def test_verification_commands_allowed(self):
        for command in ["mix deps.get", "mix format --check-formatted", "mix compile --warnings-as-errors",
                        "mix test", "mix test test/a_test.exs:12", "mix dialyzer", "mix hex.audit",
                        "mix docs --warnings-as-errors", "mix hex.build", "python3 scripts/test_agent_guard.py"]:
            with self.subTest(command=command):
                self.assertIsNone(guard.shell_reason(command))

    def test_read_commands_allowed(self):
        for command in ["rg --files", "rg -n failure test", "cat AGENTS.md", "git status --short",
                        "git diff --no-ext-diff --no-textconv", "git log --no-ext-diff --no-textconv -1"]:
            self.assertIsNone(guard.shell_reason(command))

    def test_arbitrary_shell_and_control_syntax_denied(self):
        for command in ["sed -i s/a/b/ test/a_test.exs", "python3 -c 'print(1)'", "bash",
                        "sh script.sh", "mix format", "mix test --exclude important",
                        "cat README.md > test/a_test.exs", "cat a; rm b", "cat $(touch bad)",
                        "cat `touch bad`", "rg --pre=evil pattern", "git -c alias.x=evil x",
                        "git diff --output=test/a_test.exs", "git show HEAD", "mix test test/../a_test.exs"]:
            with self.subTest(command=command):
                self.assertIsNotNone(guard.shell_reason(command))

    def test_opaque_tools_and_interactive_input_denied(self):
        for name in ["write_stdin", "Code", "exec", "mcp__filesystem__write_file"]:
            self.assertIsNotNone(guard.evaluate({"hook_event_name": "PreToolUse", "tool_name": name,
                                                "tool_input": {}}))

    def test_invalid_inputs_fail_closed_with_supported_deny_schema(self):
        for payload in ["not json", "null", "{}", json.dumps({"hook_event_name": "PreToolUse",
                         "tool_name": "Bash", "tool_input": {"command": None}})]:
            result = subprocess.run([sys.executable, str(GUARD)], input=payload,
                                    capture_output=True, text=True, check=True)
            output = json.loads(result.stdout)["hookSpecificOutput"]
            self.assertEqual(output["hookEventName"], "PreToolUse")
            self.assertEqual(output["permissionDecision"], "deny")
            self.assertIn("human", output["permissionDecisionReason"])

    def test_success_has_no_output(self):
        result = subprocess.run([sys.executable, str(GUARD)], input=json.dumps({
            "hook_event_name": "PreToolUse", "tool_name": "Bash",
            "tool_input": {"command": "mix test"}}), text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
