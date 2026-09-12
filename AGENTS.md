# AGENTS.md — Elixir Hex Package

Instructions for working in `otlp_shipper`. Follow the user's task and applicable
higher-priority instructions. Preserve existing conventions and unrelated work.
[PLAN.md](PLAN.md) defines the intended package and phased implementation. Read it
end to end before development. [docs/product-decisions.md](docs/product-decisions.md)
distinguishes those plans from implemented behavior; examples in these instructions do not authorize new features.

## Project and stack

This is an Elixir library distributed as a Hex package. Use Mix, ExUnit, doctests,
and the repository's formatter. `mix.exs` declares `:otlp_shipper`, version
`0.1.0`, and Elixir `~> 1.19`; `.tool-versions` pins the development toolchain.
The planned product ships logs and metrics over OTLP/HTTP; traces are out of scope.
The shared core and supervised Logger handling are implemented; metrics aggregation
remains Phase 2. Real Collector conformance and release preparation remain Phase 3.
Development is authorized. Use Finch directly for HTTP and publish atomic commits
to the phase branch after checks pass. Public Hex publication requires release authorization.

Keep dependencies small. Add processes, persistence, transport libraries, or
instrumentation only for concrete package behavior. Do not import Marquee's
Phoenix, Ecto, tenant, billing, deployment, or browser-test infrastructure.

## Workflow

The primary agent owns scope, public contracts, architecture, integration, and
final verification. Establish the package's purpose and acceptance criteria
before implementing consequential behavior. Follow the plan in order: Phase 0 core
and fake collector, Phase 1 logs, Phase 2 metrics, Phase 3 conformance/docs/release.
Each phase gets a branch and PR; wait for its merge before beginning the next. Make routine implementation choices
autonomously; ask when an unresolved choice changes the public contract.

Build a working scaffold and test harness before splitting implementation. Use
[docs/codex-agents.md](docs/codex-agents.md) when delegation is requested or otherwise
authorized. No project-specific agent definitions are installed by these docs.
Keep `mix.exs`, dependency changes, and shared public types under one owner at a
time. Integrate the combined result before final checks.

## Architecture and Elixir style

Read [docs/elixir-style.md](docs/elixir-style.md) when writing Elixir and
[docs/interface-design.md](docs/interface-design.md) when changing public APIs.

- Keep functions focused on one responsibility. Use pipes for multistep data
  transformations, with named values when reuse or clarity warrants them.
- Keep core operations in ordinary functions. Public library modules own domain
  rules; Mix tasks, adapters, and OTP callbacks translate inputs and call them.
- Give private functions intent-revealing names such as `reject_invalid_options`.
- Document public APIs with `@moduledoc`, `@doc`, `@spec`, and useful types. Every
  public function gets a happy-path doctest, except effectful functions and
  required callbacks, which need focused ExUnit coverage.
- Return specific tagged errors for expected failures. Do not make callers parse
  human-readable strings. Preserve required OTP and third-party callback shapes.
- Use behaviours for real external boundaries or interchangeable implementations,
  not for every module. Prefer explicit inputs over global operation context.
- No committed `IO.inspect` debugging. Use structured Logger metadata, with no
  string interpolation or secrets in log calls.

## Library and OTP constraints

The package is `otlp_shipper`; use the existing idiomatic module root `OtlpShipper`.
PLAN.md's `OTLPShipper` names refer to this root. Namespace modules consistently.
Define Mix tasks under `Mix.Tasks` only if needed.
Do not assume a web request, tenant, database, or interactive terminal exists.
Runtime code must work inside a consumer release without Mix installed.

Accept configuration through documented options where practical. Validate at the
boundary and state defaults, units, precedence, and whether changes require a
restart. Read runtime configuration at runtime. Do not mutate another application's
environment or globally configure Logger, OpenTelemetry, or HTTP clients.

Use processes for concurrency, lifecycle, or owned mutable state. Supervise them;
document startup ownership and child specifications. Avoid mandatory global names
when independent instances are useful. Bound queues, batches, concurrency, retries,
and shutdown waits. Define overflow and loss behavior before implementing a buffer.
Do not introduce a durable queue without a durability requirement.

Follow [docs/architecture.md](docs/architecture.md) for the planned shared core and
dependency constraints. Generate protobuf encoders; never hand-write wire encoding.

Give external calls timeouts and explicit error mapping. A timeout does not prove
remote failure; retry only under a documented duplicate-delivery policy. Never
invent idempotency support for a protocol. Do not let exporter diagnostics feed
back into the exporter indefinitely. See [docs/data-handling.md](docs/data-handling.md).

## Tests are a contract

Every added behavior needs a test. Cover meaningful branches, declared errors,
and boundary cases. For reproducible bugs, first demonstrate the expected behavior
with a failing regression test, then fix the root cause.

Do not weaken assertions, delete tests, skip checks, or change expectations to hide
regressions. Update tests for an intentional contract change and explain it. If an
existing specification appears wrong and the task does not resolve it, flag that
ambiguity before changing its meaning.

Use the cheapest layer that proves behavior: doctests, ExUnit public API tests,
adapter tests, process integration, then a consumer package smoke test. Keep tests
deterministic and isolated; no live provider requests or production credentials.
Read [docs/testing.md](docs/testing.md) for setup and verification details.

## Commands and delivery

These are the current CI checks, run from the repository root:

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Also run `mix dialyzer` before code commits. CI runs `mix hex.audit`,
`mix docs --warnings-as-errors`, and `mix hex.build` as well. There is no custom
verification alias or Credo setup. Do not claim unavailable or skipped checks passed.
Before handoff, run relevant checks and report failures, skipped checks, and gaps.
Documentation-only edits need link/content checks, not new behavior tests.

Keep commits atomic, focused, and independently valid. Follow trunk-based
conventions with short-lived branches, a linear history, and no merge commits.
Use conventional commit prefixes (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).
Run applicable checks before committing. Preserve others' changes; never force-push
or rewrite shared history. The user explicitly authorizes atomic commits and a push
after each completed commit. Keep each phase on its branch and open a PR.

Before a release, follow [docs/submission/readiness.md](docs/submission/readiness.md).
Packaging and dry runs are local preparation. Publish to Hex or upload documentation
only when requested or already authorized; a Git push does not authorize publishing.
