#!/usr/bin/env python3
"""Behavioral contract for the narrow guard, using disposable repository inputs."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / ".codex/hooks/guard.py"
SPEC = importlib.util.spec_from_file_location("narrow_agent_guard", GUARD)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class NarrowGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def existing(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def payload(self, name, command):
        return {"hook_event_name": "PreToolUse", "tool_name": name,
                "cwd": str(self.root), "tool_input": {"command": command}}

    def patch_payload(self, body):
        return self.payload("apply_patch", "*** Begin Patch\n" + body + "\n*** End Patch")

    def patch(self, body):
        return guard.evaluate(self.patch_payload(body))

    def review(self, result):
        self.assertIsInstance(result, dict)
        output = result["hookSpecificOutput"]
        self.assertEqual(output["hookEventName"], "PreToolUse")
        self.assertNotIn("permissionDecision", output)
        self.assertTrue(output.get("additionalContext"))
        return output["additionalContext"]

    def denied(self, result):
        self.assertIsInstance(result, dict)
        output = result["hookSpecificOutput"]
        self.assertEqual(output["hookEventName"], "PreToolUse")
        self.assertEqual(output["permissionDecision"], "deny")
        self.assertTrue(output.get("permissionDecisionReason"))

    def test_ng01_unrelated_tools_pass(self):
        for name in ["web.run", "mcp__web__search", "spawn_agent", "exec", "write_stdin"]:
            with self.subTest(name=name):
                self.assertIsNone(guard.evaluate(self.payload(name, "anything")))

    def test_ng01_ordinary_shell_syntax_and_checks_pass(self):
        for command in ["rg 'foo|bar' .", "cat README.md; cat PLAN.md", "git show HEAD",
                        "python3 -c 'print(1)'", "mix format", "mix dialyzer",
                        "bundle exec rubocop", "mix dialyzer lib/example.ex",
                        "rg 'mix dialyzer --ignore-exit-status' docs", "echo 'rubocop || true'",
                        "mix test test/example_test.exs:12", "mix deps.get && mix compile"]:
            with self.subTest(command=command):
                self.assertIsNone(guard.evaluate(self.payload("Bash", command)))

    def test_ng02_no_blanket_file_protection(self):
        for name in ["AGENTS.md", "PLAN.md", "docs/testing.md", "mix.exs", ".codex/config.toml",
                     "scripts/helper.py", ".github/workflows/ci.yml", ".formatter.exs"]:
            with self.subTest(name=name):
                self.existing(name, "old\n")
                self.assertIsNone(self.patch("*** Update File: " + name + "\n@@\n-old\n+new"))

    def test_ng02_module_with_unchanged_doctest_passes(self):
        self.existing("lib/example.ex", "iex> Example.call()\n:ok\ndef call, do: :ok\n")
        self.assertIsNone(self.patch("*** Update File: lib/example.ex\n@@\n-def call, do: :ok\n+def call, do: helper()"))

    def test_ng02_production_assert_changes_pass(self):
        self.existing("lib/check.py", "assert value > 0\n")
        self.assertIsNone(self.patch("*** Update File: lib/check.py\n@@\n-assert value > 0\n+assert value >= 0"))

    def test_ng03_new_test_and_added_assertion_pass(self):
        self.assertIsNone(self.patch("*** Add File: test/new_test.exs\n+assert result == :ok"))
        self.existing("test/example_test.exs", "assert result == :ok\n")
        self.assertIsNone(self.patch("*** Update File: test/example_test.exs\n@@\n assert result == :ok\n+assert count == 1"))

    def test_ng03_whitespace_comments_and_rename_pass(self):
        self.existing("test/example_test.exs", "assert value == 1\n")
        for body in ["*** Update File: test/example_test.exs\n@@\n-assert value == 1\n+  assert value == 1",
                     "*** Update File: test/example_test.exs\n@@\n+# Explain the contract\n assert value == 1",
                     "*** Update File: test/example_test.exs\n*** Move to: test/renamed_test.exs"]:
            with self.subTest(body=body):
                self.assertIsNone(self.patch(body))

    def test_ng04_changed_or_removed_assertion_reminds_without_denying(self):
        self.existing("test/example_test.exs", 'assert message == "has spaces"\n')
        for replacement in ['+assert message == "hasspaces"', '+assert true', '']:
            with self.subTest(replacement=replacement):
                context = self.review(self.patch('*** Update File: test/example_test.exs\n@@\n-assert message == "has spaces"\n' + replacement))
                self.assertRegex(context.lower(), r"fix|implementation|defect")
                self.assertRegex(context.lower(), r"user|contract")

    def test_ng04_fixture_and_helper_changes_receive_review(self):
        for name in ["test/fixtures/response.json", "test/support/helper.ex"]:
            with self.subTest(name=name):
                self.existing(name, "old\n")
                self.review(self.patch("*** Update File: " + name + "\n@@\n-old\n+new"))

    def test_ng04_delete_existing_test_receives_review(self):
        self.existing("test/example_test.exs", "assert value == 1\n")
        self.review(self.patch("*** Delete File: test/example_test.exs"))

    def test_ng04_skip_existing_test_receives_review(self):
        self.existing("test/example_test.exs", "test \"works\" do\n  assert true\nend\n")
        self.review(self.patch('*** Update File: test/example_test.exs\n@@\n+@tag :skip\n test "works" do'))

    def test_ng04_doctest_output_only_change_receives_review(self):
        self.existing("lib/example.ex", "iex> Example.call()\n:ok\n")
        self.review(self.patch("*** Update File: lib/example.ex\n@@\n iex> Example.call()\n-:ok\n+:error"))

    def test_ng05_real_source_suppression_receives_review(self):
        for name, line in [("lib/example.ex", "@dialyzer {:nowarn_function, call: 1}"),
                           ("lib/example.rb", "# rubocop:disable Metrics/MethodLength"),
                           ("lib/example.py", "import missing  # noqa")]:
            with self.subTest(name=name):
                self.review(self.patch("*** Add File: " + name + "\n+" + line))

    def test_ng05_analysis_removal_and_configuration_weakening_receive_review(self):
        for name, old, new in [(".github/workflows/ci.yml", "  - run: mix dialyzer", "  - run: echo done"),
                               (".rubocop.yml", "  Enabled: true", "  Enabled: false"),
                               ("mix.exs", "dialyzer: []", 'dialyzer: [ignore_warnings: "ignore.exs"]')]:
            with self.subTest(name=name):
                self.existing(name, old + "\n")
                self.review(self.patch("*** Update File: " + name + "\n@@\n-" + old + "\n+" + new))

    def test_ng06_explicit_analysis_exit_masking_denied(self):
        for command in ["mix dialyzer --ignore-exit-status", "rubocop --exit-zero",
                        "mix dialyzer || true", "bundle exec rubocop || :",
                        "mix dialyzer; exit 0"]:
            with self.subTest(command=command):
                self.denied(guard.evaluate(self.payload("Bash", command)))

    def test_ng07_documentation_and_literal_mentions_pass(self):
        for name, line in [("docs/analysis.md", "@dialyzer suppresses an analysis warning"),
                           ("scripts/test_detector.py", 'example = "# rubocop:disable all"'),
                           ("test/example_test.exs", 'text = "@dialyzer {:nowarn_function, call: 1}"'),
                           ("lib/example.ex", 'text = "@dialyzer {:nowarn_function, call: 1}"')]:
            with self.subTest(name=name):
                self.assertIsNone(self.patch("*** Add File: " + name + "\n+" + line))

    def test_ng08_cli_outputs_supported_schemas(self):
        self.existing("test/example_test.exs", "assert value == 1\n")
        cases = [(self.payload("Bash", "rg 'foo|bar' ."), "pass"),
                 (self.patch_payload("*** Update File: test/example_test.exs\n@@\n-assert value == 1\n+assert true"), "review"),
                 (self.payload("Bash", "mix dialyzer || true"), "deny")]
        for payload, expected in cases:
            with self.subTest(expected=expected):
                completed = subprocess.run([sys.executable, str(GUARD)], input=json.dumps(payload),
                                           capture_output=True, text=True, check=True)
                if expected == "pass":
                    self.assertEqual(completed.stdout, "")
                elif expected == "review":
                    self.review(json.loads(completed.stdout))
                else:
                    self.denied(json.loads(completed.stdout))

    def test_ng09_matcher_is_narrow_and_anchored(self):
        # The shared v2 workflow separates edit ownership from shell auditing.
        config = json.loads((ROOT / ".codex/hooks.json").read_text())
        dynamic_root = "$(git rev-parse --show-toplevel)"

        def command(script):
            return ('python3 -B "' + dynamic_root + '/.codex/hooks/' + script +
                    '" --platform codex --root "' + dynamic_root +
                    '" --policy "' + dynamic_root + '/.codex/hooks/policy.json"')

        entries = config["hooks"]["PreToolUse"]
        self.assertEqual(len(entries), 2)
        guard_entries = [entry for entry in entries if any(
            hook["command"] == command("workflow_guard.py") for hook in entry["hooks"])]
        self.assertEqual(len(guard_entries), 1)
        self.assertEqual(guard_entries[0], {"matcher": ".*", "hooks": [{
            "type": "command", "command": command("workflow_guard.py"), "timeout": 5}]})

        for event in ["PreToolUse", "PostToolUse"]:
            with self.subTest(event=event):
                audit_entries = [entry for entry in config["hooks"][event] if any(
                    hook["command"] == command("workflow_audit.py") for hook in entry["hooks"])]
                self.assertEqual(len(audit_entries), 1)
                [audit_entry] = audit_entries
                self.assertEqual(audit_entry, {"matcher": "^(Bash|apply_patch)$", "hooks": [{
                    "type": "command", "command": command("workflow_audit.py"), "timeout": 10}]})
                matcher = audit_entry["matcher"]
                for name in ["Bash", "apply_patch"]:
                    self.assertIsNotNone(re.search(matcher, name))
                for name in ["web.run", "spawn_agent", "BashExtra", "prefix_apply_patch",
                             "prefix_Bash", "apply_patchExtra"]:
                    self.assertIsNone(re.search(matcher, name))
        self.assertEqual(len(config["hooks"]["PostToolUse"]), 1)


if __name__ == "__main__":
    unittest.main()
