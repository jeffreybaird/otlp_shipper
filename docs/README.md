# Package development guide

These documents adapt Page Monitor's repository workflow for an Elixir Hex library
and carry over the applicable style from Marquee's `CLAUDE.md` and `.claude/` files.
The source repositories remain unchanged. [../PLAN.md](../PLAN.md) supplies the
package design; Phase 2 metrics development is authorized. Phase 3 remains next
after this phase is merged.

| Document | Use |
| --- | --- |
| [Product decisions](product-decisions.md) | Known scope, scaffold facts, unresolved contracts |
| [Architecture](architecture.md) | Implemented core, logs, metrics, and dependency boundaries |
| [Elixir style](elixir-style.md) | Functions, errors, documentation, side effects |
| [Interface design](interface-design.md) | Consumer API and compatibility |
| [Testing](testing.md) | ExUnit, adapters, processes, consumer checks |
| [Agent coordination](codex-agents.md) | Bounded assignments and review handoffs |
| [Data handling](data-handling.md) | Configuration, credentials, diagnostics |
| [Release readiness](submission/readiness.md) | Prerequisites and evidence |
| [Build](submission/build.md) | Local Hex package inspection and publication |
| [Package listing](submission/package-listing.md) | Metadata and README requirements |
| [Reviewer notes](submission/reviewer-notes.md) | Independent release review |

Page Monitor's UI design becomes API design; its store submission workflow becomes
Hex release preparation. Payment instructions and browser privacy declarations have
no direct counterpart here. Data handling replaces those product-specific privacy
claims. The plan selects MIT; no payment model, hosted service, or end-user privacy policy
is introduced.
Marquee's Gherkin/UI pathways become public API acceptance tests in ExUnit.

`docs/` contains maintained source guides. Generated ExDoc output belongs in `doc/`.
This documentation does not install tools, configure agents, or enforce release gates.
