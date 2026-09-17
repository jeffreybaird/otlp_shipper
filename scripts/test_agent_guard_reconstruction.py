#!/usr/bin/env python3
"""Characterize patch reconstruction before and after the readability refactor."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "agent_guard_reconstruction", ROOT / ".codex/hooks/guard.py"
)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class GuardReconstructionTests(unittest.TestCase):
    """Preserve complete-file reconstruction and ordered hunk matching."""

    def setUp(self):
        """Create an isolated existing file containing repeated hunk context."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.path = Path("example_test.py")
        self.before = "assert ready\nmiddle()\nassert ready\n"
        (self.root / self.path).write_text(self.before)

    def test_repeated_context_matches_after_the_previous_hunk(self):
        """Ensure the second hunk cannot rematch context retained by the first."""
        patch = """*** Begin Patch
*** Update File: example_test.py
@@
 assert ready
+assert extra
@@
-assert ready
+assert changed
*** End Patch
"""
        expected = "assert ready\nassert extra\nmiddle()\nassert changed\n"
        self.assertEqual(
            list(guard.patch_files(patch, self.root)),
            [(self.path, self.before, expected)],
        )
        self.assertEqual((self.root / self.path).read_text(), self.before)

    def test_unmatched_later_hunk_does_not_yield_a_partial_file(self):
        """Discard a file reconstruction if any later hunk fails to match."""
        patch = """*** Begin Patch
*** Update File: example_test.py
@@
 assert ready
+assert extra
@@
-assert missing
+assert changed
*** End Patch
"""
        self.assertEqual(list(guard.patch_files(patch, self.root)), [])
        self.assertEqual((self.root / self.path).read_text(), self.before)


if __name__ == "__main__":
    unittest.main()
