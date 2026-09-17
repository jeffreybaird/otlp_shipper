#!/usr/bin/env python3
"""Fail-closed watchdog contract using real, disposable guard subprocesses."""
import importlib.util
import inspect
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / ".codex/hooks/run_guard.py"
SPEC = importlib.util.spec_from_file_location("agent_guard_deadline", WRAPPER)
watchdog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(watchdog)


class GuardDeadlineTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.event = json.dumps({
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": "mix credo --strict"},
        })

    def worker(self, source):
        path = self.directory / "worker.py"
        path.write_text(source)
        return [sys.executable, str(path)]

    def run_worker(self, source, timeout=2.0):
        return watchdog.run_guard(self.worker(source), self.event, timeout=timeout)

    def assert_denied(self, result):
        self.assertIsInstance(result, str)
        output = json.loads(result)["hookSpecificOutput"]
        self.assertEqual(output["hookEventName"], "PreToolUse")
        self.assertEqual(output["permissionDecision"], "deny")
        reason = output["permissionDecisionReason"]
        self.assertIsInstance(reason, str)
        self.assertTrue(reason.strip())
        return reason

    def test_worker_deadline_defaults_to_five_seconds(self):
        parameter = inspect.signature(watchdog.run_guard).parameters["timeout"]
        self.assertEqual(parameter.default, 5.0)

    def test_successful_guard_with_empty_stdout_allows(self):
        self.assertEqual(self.run_worker("pass\n"), "")

    def test_guard_receives_the_original_event_on_stdin(self):
        received = self.directory / "received.json"
        source = (
            "import pathlib, sys\n"
            f"pathlib.Path({str(received)!r}).write_text(sys.stdin.read())\n"
        )
        self.assertEqual(self.run_worker(source), "")
        self.assertEqual(received.read_text(), self.event)

    def test_valid_context_reminder_is_preserved_exactly(self):
        result = '{ "hookSpecificOutput": {"hookEventName": "PreToolUse", '
        result += '"additionalContext": "Review the original test contract."}}\n'
        source = f"import sys\nsys.stdout.write({result!r})\n"
        self.assertEqual(self.run_worker(source), result)

    def test_valid_explicit_denial_is_preserved_exactly(self):
        result = json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Analyzer failure status is masked.",
        }}) + "\n"
        source = f"import sys\nsys.stdout.write({result!r})\n"
        self.assertEqual(self.run_worker(source), result)

    def test_spawn_failure_denies_without_exposing_input(self):
        result = watchdog.run_guard(
            [str(self.directory / "missing-worker")],
            "PRIVATE_EVENT_INPUT",
            timeout=1.0,
        )
        self.assert_denied(result)
        self.assertNotIn("PRIVATE_EVENT_INPUT", result)

    def test_nonzero_exit_denies_and_discards_worker_output(self):
        source = (
            "import sys\n"
            "print('PRIVATE_STDOUT')\n"
            "print('PRIVATE_STDERR', file=sys.stderr)\n"
            "sys.exit(3)\n"
        )
        result = self.run_worker(source)
        self.assert_denied(result)
        self.assertNotIn("PRIVATE_STDOUT", result)
        self.assertNotIn("PRIVATE_STDERR", result)

    def test_nonzero_exit_cannot_pass_through_a_valid_reminder(self):
        reminder = json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "additionalContext": "Review this.",
        }})
        source = f"import sys\nprint({reminder!r})\nsys.exit(1)\n"
        self.assert_denied(self.run_worker(source))

    def test_malformed_output_denies_without_echoing_it(self):
        for stdout in ["PRIVATE_NOT_JSON", '{"PRIVATE_PARTIAL":', '{}\n{}']:
            with self.subTest(stdout=stdout):
                source = f"import sys\nsys.stdout.write({stdout!r})\n"
                result = self.run_worker(source)
                self.assert_denied(result)
                self.assertNotIn("PRIVATE_", result)

    def test_unsupported_output_shapes_do_not_allow(self):
        outputs = [
            None,
            [],
            {},
            {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "x"}},
            {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}},
            {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": 12}},
            {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny"}},
        ]
        for output in outputs:
            with self.subTest(output=output):
                serialized = json.dumps(output)
                self.assert_denied(self.run_worker(f"print({serialized!r})\n"))

    def test_timeout_denies_discards_partial_output_and_reaps_child(self):
        pid_path = self.directory / "worker.pid"
        source = (
            "import os, pathlib, sys, time\n"
            f"pathlib.Path({str(pid_path)!r}).write_text(str(os.getpid()))\n"
            "print('PRIVATE_PARTIAL_STDOUT', flush=True)\n"
            "print('PRIVATE_PARTIAL_STDERR', file=sys.stderr, flush=True)\n"
            "time.sleep(30)\n"
        )
        started = time.monotonic()
        result = self.run_worker(source, timeout=1.0)
        elapsed = time.monotonic() - started
        reason = self.assert_denied(result)
        self.assertRegex(reason.lower(), r"timed out|timeout|deadline")
        self.assertLess(elapsed, 5.0)
        self.assertNotIn("PRIVATE_PARTIAL", result)
        self.assertTrue(pid_path.exists(), "The fixture must start before its timeout")
        pid = int(pid_path.read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        with self.assertRaises(ChildProcessError):
            os.waitpid(pid, os.WNOHANG)

    def test_stderr_pipe_is_drained_without_corrupting_success_output(self):
        source = "import sys\nsys.stderr.write('diagnostic' * 32768)\n"
        self.assertEqual(self.run_worker(source), "")

    def test_cli_keeps_narrow_guard_read_only_behavior(self):
        event = json.dumps({
            "hook_event_name": "PreToolUse", "tool_name": "Bash",
            "cwd": str(self.directory),
            "tool_input": {"command": "rg 'foo|bar' ."},
        })
        result = subprocess.run(
            [sys.executable, str(WRAPPER)], input=event,
            text=True, capture_output=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_cli_preserves_existing_analysis_masking_denial(self):
        event = json.dumps({
            "hook_event_name": "PreToolUse", "tool_name": "Bash",
            "cwd": str(self.directory),
            "tool_input": {"command": "mix dialyzer --ignore-exit-status"},
        })
        result = subprocess.run(
            [sys.executable, str(WRAPPER)], input=event,
            text=True, capture_output=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_denied(result.stdout)


if __name__ == "__main__":
    unittest.main()
