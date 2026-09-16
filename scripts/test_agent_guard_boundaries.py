#!/usr/bin/env python3
"""Additional narrow guard boundaries; no general shell security guarantee."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GUARD = Path(__file__).resolve().parents[1] / ".codex/hooks/guard.py"
SPEC = importlib.util.spec_from_file_location("boundary_agent_guard", GUARD)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class GuardBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def event(self, name, command):
        return {"hook_event_name": "PreToolUse", "tool_name": name,
                "cwd": str(self.root), "tool_input": {"command": command}}

    def patch(self, body):
        return guard.evaluate(self.event("apply_patch", "*** Begin Patch\n" + body + "\n*** End Patch"))

    def existing(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def test_ng06_analyzer_after_ordinary_command_is_still_checked(self):
        for command in ["pwd; mix dialyzer || true", "cat README.md && rubocop --exit-zero"]:
            with self.subTest(command=command):
                result = guard.evaluate(self.event("Bash", command))
                self.assertIsInstance(result, dict)
                self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_ng01_quoted_analyzer_operators_are_only_text(self):
        for command in ["rg 'mix dialyzer || true' docs; pwd",
                        "echo 'rubocop --exit-zero; exit 0'",
                        'rg "rubocop || :" README.md']:
            with self.subTest(command=command):
                self.assertIsNone(guard.evaluate(self.event("Bash", command)))

    def test_ng06_preserving_failure_exit_is_allowed(self):
        for command in ["mix dialyzer || exit 1", "bundle exec rubocop || exit 2"]:
            with self.subTest(command=command):
                self.assertIsNone(guard.evaluate(self.event("Bash", command)))

    def test_ng05_removing_active_suppression_is_allowed(self):
        self.existing("lib/example.ex", "@dialyzer {:nowarn_function, call: 1}\ndef call(value), do: value\n")
        self.assertIsNone(self.patch("*** Update File: lib/example.ex\n@@\n-@dialyzer {:nowarn_function, call: 1}\n def call(value), do: value"))

    def test_ng07_multiline_docstring_is_not_active_suppression(self):
        self.assertIsNone(self.patch('*** Add File: scripts/explain.py\n+"""Analyzer examples.\n+# noqa\n+# rubocop:disable all\n+@dialyzer {:nowarn_function, call: 1}\n+"""\n+value = 1'))

    def test_ng08_malformed_events_do_not_create_unrelated_denials(self):
        for payload in [None, [], {}, {"hook_event_name": "PostToolUse"},
                        {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": None},
                        self.event("Bash", None)]:
            with self.subTest(payload=payload):
                self.assertIsNone(guard.evaluate(payload))

    def test_ng08_invalid_json_cli_does_not_crash_or_deny(self):
        for serialized in ["not JSON", "null", json.dumps({})]:
            with self.subTest(serialized=serialized):
                result = subprocess.run([sys.executable, str(GUARD)], input=serialized,
                                        text=True, capture_output=True, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")

    def test_ng04_doctest_output_edit_without_prompt_context_is_reviewed(self):
        self.existing("lib/example.ex", 'defmodule Example do\n  @doc """\n  iex> Example.call()\n  :ok\n  """\n  def call, do: :ok\nend\n')
        result = self.patch("*** Update File: lib/example.ex\n@@\n-  :ok\n+  :error")
        self.assertIsInstance(result, dict)
        output = result["hookSpecificOutput"]
        self.assertTrue(output.get("additionalContext"))
        self.assertNotIn("permissionDecision", output)


if __name__ == "__main__":
    unittest.main()
