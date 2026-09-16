#!/usr/bin/env python3
"""Independent review regressions for narrow semantic review candidates."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

GUARD = Path(__file__).resolve().parents[1] / ".codex/hooks/guard.py"
SPEC = importlib.util.spec_from_file_location("review_agent_guard", GUARD)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class ReviewRegressionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def event(self, name, command):
        return {"hook_event_name": "PreToolUse", "tool_name": name,
                "cwd": str(self.root), "tool_input": {"command": command}}

    def existing(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def patch(self, body):
        return guard.evaluate(self.event("apply_patch", "*** Begin Patch\n" + body + "\n*** End Patch"))

    def review(self, result):
        self.assertIsInstance(result, dict)
        output = result["hookSpecificOutput"]
        self.assertEqual(output["hookEventName"], "PreToolUse")
        self.assertTrue(output.get("additionalContext"))
        self.assertNotIn("permissionDecision", output)

    def test_ng04_appending_true_to_assertion_requires_review(self):
        self.existing("tests/test_example.py", "assert value == expected\n")
        self.review(self.patch("*** Update File: tests/test_example.py\n@@\n-assert value == expected\n+assert value == expected or True"))

    def test_ng05_append_to_existing_exclusion_list_requires_review(self):
        self.existing(".rubocop.yml", "AllCops:\n  Exclude:\n    - vendor/**/*\n")
        self.review(self.patch("*** Update File: .rubocop.yml\n@@\n     - vendor/**/*\n+    - lib/problem.rb"))

    def test_ng06_exit_zero_fallback_denied(self):
        result = guard.evaluate(self.event("Bash", "mix dialyzer || exit 0"))
        self.assertIsInstance(result, dict)
        output = result["hookSpecificOutput"]
        self.assertEqual(output["permissionDecision"], "deny")
        self.assertTrue(output.get("permissionDecisionReason"))

    def test_ng01_shell_comments_are_not_executable_bypasses(self):
        for command in ["echo ok # example; mix dialyzer || true",
                        "mix dialyzer # fallback || true"]:
            with self.subTest(command=command):
                self.assertIsNone(guard.evaluate(self.event("Bash", command)))

    def test_ng05_ci_analyzer_command_masking_requires_review(self):
        self.existing(".github/workflows/ci.yml", "steps:\n  - run: mix dialyzer\n")
        self.review(self.patch("*** Update File: .github/workflows/ci.yml\n@@\n-  - run: mix dialyzer\n+  - run: mix dialyzer || true"))

    def test_ng05_enable_ignore_exit_status_requires_review(self):
        self.existing("mix.exs", "dialyzer: [ignore_exit_status: false]\n")
        self.review(self.patch("*** Update File: mix.exs\n@@\n-dialyzer: [ignore_exit_status: false]\n+dialyzer: [ignore_exit_status: true]"))


if __name__ == "__main__":
    unittest.main()
