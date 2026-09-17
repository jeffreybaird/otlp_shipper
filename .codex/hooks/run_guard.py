#!/usr/bin/env python3
"""Turn guard execution failures into explicit PreToolUse denials."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

WORKER_TIMEOUT_SECONDS = 5.0
ENTRY_TIMEOUT_SECONDS = 7.0


def deny(reason):
    return json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }})


def valid_response(output):
    try:
        payload = json.loads(output)
        if not isinstance(payload, dict) or set(payload) != {"hookSpecificOutput"}:
            return False
        result = payload["hookSpecificOutput"]
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
    except (ValueError, TypeError):
        return False


def stop_worker(process):
    # Kill the isolated process group too: descendants must not outlive a deadline.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()
    for stream in (process.stdin, process.stdout, process.stderr):
        if stream is not None:
            stream.close()


def run_guard(command, event_input, timeout=WORKER_TIMEOUT_SECONDS):
    process = None
    try:
        process = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, start_new_session=True,
        )
        stdout, _stderr = process.communicate(event_input, timeout=timeout)
        if process.returncode != 0:
            return deny("Guard inspection failed; the pending tool call was blocked. Repair the guard before retrying.")
        if not stdout.strip():
            return stdout
        if not valid_response(stdout):
            return deny("Guard returned invalid output; the pending tool call was blocked.")
        return stdout
    except (subprocess.TimeoutExpired, TimeoutError):
        return deny("Guard timed out; the pending tool call was blocked. Diagnose the guard before retrying.")
    except (OSError, ValueError, UnicodeError):
        return deny("Guard could not run; the pending tool call was blocked.")
    finally:
        if process is not None:
            stop_worker(process)


def expire_entry(_signum, _frame):
    raise TimeoutError("Guard entry deadline exceeded")


def main():
    # Bound stdin handling as well as child execution on the supported macOS host.
    signal.signal(signal.SIGALRM, expire_entry)
    signal.setitimer(signal.ITIMER_REAL, ENTRY_TIMEOUT_SECONDS)
    try:
        event_input = sys.stdin.read()
        result = run_guard([sys.executable, str(Path(__file__).with_name("guard.py"))], event_input)
    except TimeoutError:
        result = deny("Guard timed out reading or inspecting the event; the pending tool call was blocked.")
    except (OSError, ValueError, UnicodeError):
        result = deny("Guard input could not be read; the pending tool call was blocked.")
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    if result:
        sys.stdout.write(result)
        sys.stdout.flush()


if __name__ == "__main__":
    main()
