#!/usr/bin/env python3
"""Optional documented verification command regressions."""
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / ".codex/hooks/guard.py"
spec = importlib.util.spec_from_file_location("agent_guard", path)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class OptionalChecks(unittest.TestCase):
    def test_optional_checks_allowed(self):
        for command in ["mix test --cover", "mix otlp_shipper.conformance",
                        "python3 scripts/test_agent_guard_optional_checks.py"]:
            with self.subTest(command=command):
                self.assertIsNone(guard.shell_reason(command))

    def test_optional_checks_do_not_allow_arbitrary_options(self):
        for command in ["mix test --cover --exclude important", "mix otlp_shipper.conformance --evil"]:
            self.assertIsNotNone(guard.shell_reason(command))


if __name__ == "__main__":
    unittest.main()
