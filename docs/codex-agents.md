# Agent coordination for package work

The primary agent owns architecture, public API decisions, integration, and final
verification. Routine documentation and small code changes stay with that agent.
This repository currently has no `.codex/agents/` definitions. The roles below are
assignment patterns, not installed agents or automatic delegation authorization.

When delegation is requested or otherwise authorized and independent work exists:

| Role | Bounded assignment |
| --- | --- |
| Explorer | Trace existing APIs, dependencies, configuration, and lifecycle; cite evidence |
| Spec writer | Define consumer acceptance cases and meaningful regression tests |
| Implementer | Implement one agreed behavior in explicitly assigned files |
| Test runner | Run named checks against stable source and report exact outcomes |
| Reviewer | Review compatibility, errors, OTP lifecycle, tests, and package contents |

Establish the scaffold, public types, and test harness first. Give each assignment
its requirement, allowed files, shared contracts, dependencies, verification commands,
and expected handoff. Use one owner for `mix.exs`, the lockfile, and public types.
Avoid overlapping writes; do not assume separate worktrees or enforced read-only
permissions. Keep source stable while another agent verifies it.

A review should identify actionable defects with file/line evidence and verification
gaps. Resolve findings and run the integrated checks before handoff. Claude model
IDs, tool lists, hooks, and memory settings are source-platform configuration;
these documents do not install or translate them into Codex configuration.
