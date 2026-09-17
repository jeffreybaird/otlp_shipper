#!/usr/bin/env python3
"""Exercise the real entry deadline and descendant cancellation boundaries."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / ".codex/hooks/run_guard.py"
SPEC = importlib.util.spec_from_file_location("agent_guard_entry_deadline", WRAPPER)
watchdog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(watchdog)


class GuardEntryDeadlineTests(unittest.TestCase):
    def assert_timeout_denial(self, stdout):
        result = json.loads(stdout)["hookSpecificOutput"]
        self.assertEqual(result["hookEventName"], "PreToolUse")
        self.assertEqual(result["permissionDecision"], "deny")
        self.assertRegex(result["permissionDecisionReason"].lower(), r"timed out|deadline")

    def test_entry_denies_when_stdin_stays_open_without_eof(self):
        process = subprocess.Popen(
            [sys.executable, str(WRAPPER)], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        started = time.monotonic()
        try:
            process.stdin.write('{"hook_event_name": "PreToolUse"')
            process.stdin.flush()
            # Keep stdin open: communicate() would close it and miss this boundary.
            process.wait(timeout=9.5)
            elapsed = time.monotonic() - started
            self.assertEqual(process.returncode, 0, process.stderr.read())
            self.assert_timeout_denial(process.stdout.read())
            self.assertGreaterEqual(elapsed, 6.0)
            self.assertLess(elapsed, 9.5)
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=2)
            for stream in (process.stdin, process.stdout, process.stderr):
                stream.close()

    def test_worker_timeout_kills_descendant_with_inherited_output_pipes(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            descendant_pid = directory / "descendant.pid"
            worker_pid = directory / "worker.pid"
            descendant = directory / "descendant.py"
            descendant.write_text(
                "import os, pathlib, time\n"
                f"pathlib.Path({str(descendant_pid)!r}).write_text(str(os.getpid()))\n"
                "time.sleep(30)\n"
            )
            worker = directory / "worker.py"
            worker.write_text(
                "import os, pathlib, subprocess, sys, time\n"
                f"pathlib.Path({str(worker_pid)!r}).write_text(str(os.getpid()))\n"
                f"subprocess.Popen([sys.executable, {str(descendant)!r}])\n"
                "print('PRIVATE_INHERITED_PIPE_OUTPUT', flush=True)\n"
                "time.sleep(30)\n"
            )
            try:
                started = time.monotonic()
                result = watchdog.run_guard([sys.executable, str(worker)], "{}", timeout=1.0)
                self.assertLess(time.monotonic() - started, 5.0)
                self.assert_timeout_denial(result)
                self.assertNotIn("PRIVATE_INHERITED_PIPE_OUTPUT", result)
                self.assertTrue(worker_pid.exists(), "Worker fixture must start before timeout")
                self.assertTrue(descendant_pid.exists(), "Descendant fixture must start before timeout")
                direct_pid = int(worker_pid.read_text())
                with self.assertRaises(ChildProcessError):
                    os.waitpid(direct_pid, os.WNOHANG)
                self.assert_process_stopped(int(descendant_pid.read_text()))
            finally:
                for path in (worker_pid, descendant_pid):
                    if path.exists():
                        try:
                            os.kill(int(path.read_text()), signal.SIGKILL)
                        except ProcessLookupError:
                            pass

    def assert_process_stopped(self, pid):
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            result = subprocess.run(
                ["ps", "-o", "stat=", "-p", str(pid)],
                text=True, capture_output=True, timeout=1, check=False,
            )
            if result.returncode == 1 and not result.stdout.strip():
                return
            self.assertEqual(result.returncode, 0, result.stderr)
            # An orphaned zombie is dead but awaits its adoptive parent's reaping.
            # This wrapper owns/reaps only its direct child, not grandchildren.
            if result.stdout.strip().startswith("Z"):
                return
            time.sleep(0.01)
        self.fail("Descendant remained live after the worker deadline")


if __name__ == "__main__":
    unittest.main()
