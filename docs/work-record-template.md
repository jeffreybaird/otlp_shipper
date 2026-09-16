# Feature: <ID and title>

## Scope and ownership

- Request, acceptance criteria, exclusions, public contract decisions:
- Base revision, branch, PR:
- Orchestrator, spec writer, runner/model, implementer, reviewer:
- Allowed files per writer; shared type/dependency owner:

## Scenario mapping

| Scenario ID | Feature file | Unit test file/name | Integration test file/name |
| --- | --- | --- | --- |
| <ID> | <path> | <path/name or reason inapplicable> | <path/name or reason inapplicable> |

## Verification evidence

| Stage | Revision/snapshot and environment | Command | Exit/status | Evidence |
| --- | --- | --- | --- | --- |
| Red | <HEAD + diff/untracked hashes> | <exact command> | <exit> | <expected and observed assertion> |
| Green | <snapshot> | <exact command> | <exit> | <summary/log location> |
| Full gate | <snapshot> | <exact command> | <exit> | <summary/log location> |

## Human approvals

Record exact proposed patch, reason, human decision/message, and applied patch
identity. Never generate an approval on behalf of the human. Record none if unused.

## Review iterations

| Finding | Severity / file:line | Standard and evidence | Destination | Resolution / verification |
| --- | --- | --- | --- | --- |
| <ID> | <priority/location> | <contract/reproduction> | <role> | <fix/test/evidence or open> |

## Final handoff

- Reviewer verdict and reviewed commit:
- Final checks/CI and verified commit:
- PR updated; open blockers, skipped checks, and limitations:
