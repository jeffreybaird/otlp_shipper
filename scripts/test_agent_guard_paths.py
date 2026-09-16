#!/usr/bin/env python3
"""Protected policy and symlink path regressions."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

path = Path(__file__).resolve().parents[1] / ".codex/hooks/guard.py"
spec = importlib.util.spec_from_file_location("agent_guard", path)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class ProtectedPaths(unittest.TestCase):
    def test_policy_and_git_paths_protected(self):
        for name in [".git/config", ".git/hooks/pre-commit", "docs/elixir-style.md", "docs/testing.md",
                     "docs/codex-agents.md", "docs/agent-guardrails.md", "PLAN.md"]:
            with self.subTest(name=name):
                self.assertTrue(guard.protected(Path(name)))

    def test_internal_symlink_not_an_edit_bypass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / "test").mkdir()
            (root / "lib").mkdir()
            (root / "lib/a.ex").write_text("old\n")
            (root / "test/link").symlink_to(root / "lib", target_is_directory=True)
            patch = "*** Begin Patch\n*** Update File: test/link/a.ex\n@@\n-old\n+new\n*** End Patch"
            self.assertIsNotNone(guard.patch_reason(patch, root, root))

    def test_new_git_hook_is_protected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            patch = "*** Begin Patch\n*** Add File: .git/hooks/pre-commit\n+evil\n*** End Patch"
            self.assertIsNotNone(guard.patch_reason(patch, root, root))


if __name__ == "__main__":
    unittest.main()
