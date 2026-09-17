#!/usr/bin/env python3
"""Translate worker outcomes into denials at a small process boundary."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

WORKER_TIMEOUT_SECONDS = 5.0
ENTRY_TIMEOUT_SECONDS = 7.0


def deny(reason):
    """Encode a denial without exposing event input or worker output."""
    return json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }})


def valid_hook_output(result):
    """Accept only a contextual reminder or a denial with a nonempty reason."""
    if not isinstance(result, dict) or result.get("hookEventName") != "PreToolUse":
        return False
    if set(result) == {"hookEventName", "additionalContext"}:
        return isinstance(result["additionalContext"], str)
    return (
        set(result) == {"hookEventName", "permissionDecision", "permissionDecisionReason"}
        and result["permissionDecision"] == "deny"
        and isinstance(result["permissionDecisionReason"], str)
        and bool(result["permissionDecisionReason"].strip())
    )


def valid_response(output):
    """Validate the worker's JSON envelope and supported hook output."""
    try:
        payload = json.loads(output)
    except (ValueError, TypeError):
        return False
    return (
        isinstance(payload, dict)
        and set(payload) == {"hookSpecificOutput"}
        and valid_hook_output(payload["hookSpecificOutput"])
    )


def worker_response(returncode, stdout):
    """Preserve successful output or replace an invalid outcome with a denial."""
    if returncode != 0:
        return deny(
            "Guard inspection failed; the pending tool call was blocked. "
            "Repair the guard before retrying."
        )
    if not stdout.strip() or valid_response(stdout):
        return stdout
    return deny("Guard returned invalid output; the pending tool call was blocked.")


def start_worker(command):
    """Start an isolated process group with pipes for the guard protocol."""
    return subprocess.Popen(
        command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, start_new_session=True,
    )


def kill_worker_group(process):
    """Terminate the worker and descendants sharing its process group."""
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def close_worker_streams(process):
    """Release the parent's pipe handles after the worker has stopped."""
    for stream in (process.stdin, process.stdout, process.stderr):
        if stream is not None:
            stream.close()


def stop_worker(process):
    """Finish worker cleanup in kill, reap, then close order."""
    kill_worker_group(process)
    process.wait()
    close_worker_streams(process)


def run_guard(command, event_input, timeout=WORKER_TIMEOUT_SECONDS):
    """Own one bounded worker execution and translate its outcome."""
    process = None
    try:
        process = start_worker(command)
        stdout, _stderr = process.communicate(event_input, timeout=timeout)
        return worker_response(process.returncode, stdout)
    except (subprocess.TimeoutExpired, TimeoutError):
        return deny(
            "Guard timed out; the pending tool call was blocked. "
            "Diagnose the guard before retrying."
        )
    except (OSError, ValueError, UnicodeError):
        return deny("Guard could not run; the pending tool call was blocked.")
    finally:
        if process is not None:
            stop_worker(process)


def expire_entry(_signum, _frame):
    """Interrupt blocked input or inspection when the entry deadline expires."""
    raise TimeoutError("Guard entry deadline exceeded")


def inspect_stdin(command):
    """Read and inspect one event within the outer entry deadline."""
    signal.signal(signal.SIGALRM, expire_entry)
    signal.setitimer(signal.ITIMER_REAL, ENTRY_TIMEOUT_SECONDS)
    try:
        return run_guard(command, sys.stdin.read())
    except TimeoutError:
        return deny("Guard timed out reading or inspecting the event; the pending tool call was blocked.")
    except (OSError, ValueError, UnicodeError):
        return deny("Guard input could not be read; the pending tool call was blocked.")
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)


def write_response(result):
    """Flush a nonempty hook response to the host."""
    if result:
        sys.stdout.write(result)
        sys.stdout.flush()


def main():
    """Connect the adjacent classifier to the host's standard streams."""
    command = [sys.executable, str(Path(__file__).with_name("guard.py"))]
    write_response(inspect_stdin(command))


if __name__ == "__main__":
    main()
