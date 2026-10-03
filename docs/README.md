# Package development guide

These documents adapt Page Monitor's repository workflow for an Elixir Hex library
and carry over the applicable style from Marquee's `CLAUDE.md` and `.claude/` files.
The source repositories remain unchanged. [../PLAN.md](../PLAN.md) supplies the package design. Implementation through Phase 7 is recorded in product decisions;
publication still requires separate authorization.

Version 0.2.1 is the latest public Hex release, published September 30, 2026; the
source prepares the 0.2.2 security patch. See [release readiness](submission/readiness.md).

| Document | Use |
| --- | --- |
| [Product decisions](product-decisions.md) | Known scope, scaffold facts, unresolved contracts |
| [Architecture](architecture.md) | Implemented core, logs, metrics, and dependency boundaries |
| [Elixir style](elixir-style.md) | Functions, errors, documentation, side effects |
| [Interface design](interface-design.md) | Consumer API and compatibility |
| [Testing](testing.md) | ExUnit, adapters, processes, consumer checks |
| [Agent coordination](codex-agents.md) | Five-role specification, red/green, and review loop |
| [Agent guardrails](agent-guardrails.md) | Hook activation, human approval, and enforcement limits |
| [Data handling](data-handling.md) | Configuration, credentials, diagnostics |
| [0.2.2 candidate](submission/candidate-0.2.2.md) | Current security patch evidence |
| [0.1.1 release](submission/release-0.1.1.md) | Published artifact and consumer verification |
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
