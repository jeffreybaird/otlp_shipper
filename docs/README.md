# Package development guide

These documents adapt Page Monitor's repository workflow for an Elixir Hex library
and carry over the applicable style from Marquee's `CLAUDE.md` and `.claude/` files.
[../PLAN.md](../PLAN.md) supplies the original package design. Phases 0–7 are
implemented; logs, metrics, and SDK-compatible trace export are available on Hex.
The source repository is public. The latest verified public release is 0.2.1
(September 30, 2026); this tree prepares 0.2.2. See the release checklist for status.
Dated phase and candidate records preserve evidence from their original runs.

| Document | Use |
| --- | --- |
| [Product decisions](product-decisions.md) | Current scope and historical implementation decisions |
| [Architecture](architecture.md) | Implemented core, logs, metrics, traces, and dependency boundaries |
| [Elixir style](elixir-style.md) | Functions, errors, documentation, side effects |
| [Interface design](interface-design.md) | Consumer API and compatibility |
| [Testing](testing.md) | ExUnit, adapters, processes, consumer checks |
| [Agent coordination](codex-agents.md) | Five-role specification, red/green, and review loop |
| [Agent guardrails](agent-guardrails.md) | Hook activation, human approval, and enforcement limits |
| [Data handling](data-handling.md) | Configuration, credentials, diagnostics |
| [0.2.2 candidate](submission/candidate-0.2.2.md) | Current preparation and verification |
| [Release readiness](submission/readiness.md) | Prerequisites and evidence |
| [Build](submission/build.md) | Local Hex package inspection and publication |
| [Package listing](submission/package-listing.md) | Metadata and README requirements |
| [Reviewer notes](submission/reviewer-notes.md) | Independent release review |

Page Monitor's UI design becomes API design; its store submission workflow becomes
Hex release preparation. Payment instructions and browser privacy declarations have
no direct counterpart here. Data handling replaces those product-specific privacy
claims. The plan selects MIT; no payment model, hosted service, or end-user privacy policy
is introduced.
Cucumber/Gherkin scenarios map to public API acceptance tests in ExUnit.

`docs/` contains maintained source guides. Generated ExDoc output belongs in `doc/`.
Project agent definitions and hook configuration live in `../.codex/`; hooks require
human trust before activation. These do not authorize publication.
