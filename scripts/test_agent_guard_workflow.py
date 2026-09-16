#!/usr/bin/env python3
"""Regression coverage for orchestrator commands through the guard."""
from pathlib import Path
import importlib.util
import unittest

path = Path(__file__).resolve().parents[1] / ".codex/hooks/guard.py"
spec = importlib.util.spec_from_file_location("agent_guard", path)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class WorkflowCommands(unittest.TestCase):
    def test_orchestrator_delivery(self):
        for command in ["git add AGENTS.md docs .codex", "git add -- AGENTS.md", "git commit -m 'feat: harness'",
                        "git commit --file /tmp/message.txt", "git push origin codex/agent-harness",
                        "gh auth status", "gh pr view", "gh pr checks 12",
                        "gh pr create --title 'feat: harness' --body-file /tmp/body.md --base main --head codex/agent-harness --draft",
                        "gh pr edit 12 --title 'feat: harness' --body-file /tmp/body.md"]:
            with self.subTest(command=command):
                self.assertIsNone(guard.shell_reason(command))

    def test_consumer_verification(self):
        for command in ["scripts/package_smoke.sh",
                        "OTLP_SMOKE_DEPENDENCY_SET=minimum scripts/package_smoke.sh",
                        "OTLP_SMOKE_DEPENDENCY_SET=minimum_with_tracing scripts/package_smoke.sh",
                        "python3 scripts/test_agent_guard_workflow.py"]:
            self.assertIsNone(guard.shell_reason(command))

    def test_delivery_cannot_override_policies_or_destroy_history(self):
        for command in ["git add --all", "git add -f test/a_test.exs", "git commit --no-verify -m x",
                        "git commit --amend -m x", "git push --force origin main", "git push origin :main",
                        "git push origin +main", "git push --mirror", "gh pr merge", "gh pr close 12",
                        "gh pr edit 12 --repo other/repo --title x", "gh pr create --body-file x --web",
                        "OTLP_SMOKE_DEPENDENCY_SET=evil scripts/package_smoke.sh",
                        "rg --hostname-bin=evil pattern", "rg --hostname-bin evil pattern"]:
            with self.subTest(command=command):
                self.assertIsNotNone(guard.shell_reason(command))

    def test_instruction_and_policy_paths(self):
        for name in ["AGENTS.md", ".codex/config.toml", ".github/workflows/ci.yml", ".formatter.exs"]:
            self.assertTrue(guard.protected(Path(name)))


if __name__ == "__main__":
    unittest.main()
