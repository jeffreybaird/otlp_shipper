#!/usr/bin/env python3
"""Branch, snapshot, and verification-infrastructure guard regressions."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

path = Path(__file__).resolve().parents[1] / ".codex/hooks/guard.py"
spec = importlib.util.spec_from_file_location("agent_guard", path)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class OrchestrationCommands(unittest.TestCase):
    def test_create_feature_branch(self):
        self.assertIsNone(guard.shell_reason("git switch -c codex/example-feature"))

    def test_branch_command_cannot_force_reset_or_change_base(self):
        for command in ["git switch -C codex/example", "git switch -c main",
                        "git switch -c codex/example origin/other", "git switch --discard-changes main",
                        "git switch -c codex/../main", "git switch -c codex/example.lock"]:
            with self.subTest(command=command):
                self.assertIsNotNone(guard.shell_reason(command))

    def test_snapshot_hashes(self):
        self.assertIsNone(guard.shell_reason("shasum -a 256 lib/a.ex test/a_test.exs"))

    def test_hash_command_rejects_options_and_missing_paths(self):
        for command in ["shasum -a 256", "shasum -a 256 --check file", "shasum -a 1 lib/a.ex",
                        "shasum -a 256 -", "shasum -a 256 file > test/a_test.exs"]:
            self.assertIsNotNone(guard.shell_reason(command))

    def test_existing_verification_scripts_are_protected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / "scripts").mkdir()
            for name in ["package_smoke.sh", "other_check.sh"]:
                (root / "scripts" / name).write_text("old\n")
                patch = "*** Begin Patch\n*** Update File: scripts/" + name + "\n@@\n-old\n+new\n*** End Patch"
                self.assertIsNotNone(guard.patch_reason(patch, root, root))

    def test_new_regression_suite_command(self):
        self.assertIsNone(guard.shell_reason("python3 scripts/test_agent_guard_orchestration.py"))


if __name__ == "__main__":
    unittest.main()
