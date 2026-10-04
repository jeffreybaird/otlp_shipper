# otlp_shipper: shared project guidance

This is the canonical project guidance for both Codex and Claude. Read it before
working in this repository. `AGENTS.md` and `CLAUDE.md` are equivalent entry points;
maintain project rules here rather than duplicating them in those files.

Read [the agent workflow](agent-workflow.md) for every behavior change. It owns
role assignments, test-contract review, and enforcement limits, and supersedes
legacy workflow instructions in supporting documents. Project domain, privacy,
coverage, static-analysis, deployment, and release constraints still apply.
Project-specific rules take precedence over generic framework/template examples;
examples do not authorize new features or infrastructure.

Paths in backticks are relative to the repository root. Supporting guidance in
`.claude/`, `.codex/`, and `docs/` applies to both platforms when relevant, regardless
of the directory name. Read the referenced guidance for the area being changed.
Read any directory-specific `AGENTS.md` or `CLAUDE.md` before working in that
directory; its project rules apply to both platforms. Native tool names, model
choices, slash commands, and hook settings remain platform-specific: use the
documented procedure with your platform's tools, not another platform's commands.

Before committing, follow the correction and security-review requirements in
[the shared agent workflow](agent-workflow.md#precommit-corrections).
Run `mix format --force` before the remaining repository verification checks.

# Project rules

Instructions for working in `otlp_shipper`. Follow the user's task and applicable
higher-priority instructions. Preserve existing conventions and unrelated work.
[PLAN.md](../PLAN.md) defines the intended package and phased implementation. Read it
end to end before development. [docs/product-decisions.md](../docs/product-decisions.md)
distinguishes those plans from implemented behavior; examples in these instructions do not authorize new features.

## Project and stack

This is an Elixir library distributed as a Hex package. Use Mix, ExUnit, doctests,
and the repository's formatter. `mix.exs` declares `:otlp_shipper`, version
`0.2.2`, and Elixir `~> 1.19`; `.tool-versions` pins the development toolchain.
Logs, metrics, and SDK-compatible traces are implemented over OTLP/HTTP through
PLAN.md Phases 0–7, including opt-in real Collector conformance and packaged
consumer checks. Tracing shipped in 0.2.0; 0.2.1 corrected log/metric instrumentation
scope versions. Retain the OTel API, tracing SDK, and existing instrumentation;
replacing them is outside scope. GitHub is public. Version 0.2.1 was published to
public Hex on September 30, 2026; this tree prepares 0.2.2. See
[release readiness](../docs/submission/readiness.md) for evidence and current gates.
Publication requires release authorization.
Development is authorized. Use Finch directly for HTTP and publish atomic commits
to the phase branch after checks pass. Public Hex publication requires release authorization.

Keep dependencies small. Add processes, persistence, transport libraries, or
instrumentation only for concrete package behavior. Do not import Marquee's
Phoenix, Ecto, tenant, billing, deployment, or browser-test infrastructure.

## Workflow

The primary agent owns scope, public contracts, architecture, integration, and
final verification. Establish the package's purpose and acceptance criteria
before implementing consequential behavior. Follow the plan in order: Phase 0 core
and fake collector, Phase 1 logs, Phase 2 metrics, Phase 3 conformance/docs/release
(complete), then Phase 4 trace compatibility/contracts, Phase 5 trace protocol/core,
Phase 6 SDK adapter, and Phase 7 replacement proof/migration/release preparation.
Each phase gets a branch and PR; wait for its merge before beginning the next. Make routine implementation choices
autonomously; ask when an unresolved choice changes the public contract.

Follow the shared agent workflow for feature and bug-fix work. The spec
writer first writes Cucumber/Gherkin specifications and failing unit or
integration tests. The runner establishes red and the reviewer accepts
the tests before the implementer changes source. Schedule roles in stages
when concurrency is limited. Route findings to the responsible role and
repeat verification and independent review until they are resolved.
The orchestrator coordinates commits, pushes, and PR updates. Keep
`mix.exs`, dependency changes, and shared public types under one owner.

**Do not change existing tests to accommodate defective new code, or bypass static
analysis to make verification pass.** Check the original contract and failing code
before changing expectations, fixtures, helpers, skips, or coverage. Fix the code
when it violates that contract. If a contract change is necessary but not already
authorized by the user, present the exact change and reason for human review.
New coverage, stronger assertions, formatting, renames, contract-preserving
refactors, and test changes required by an authorized behavior change do not need
separate approval. Do not disable analysis rules, exclude offending code, or mask
failed checks instead of fixing their diagnostics. Any necessary analysis
exception needs explicit human authorization; agents cannot approve one another.
See the shared agent workflow for the current direct-edit guard and audit limits. Static-analysis requirements above remain project policy.

## Architecture and Elixir style

Read [docs/elixir-style.md](../docs/elixir-style.md) when writing Elixir and
[docs/interface-design.md](../docs/interface-design.md) when changing public APIs.

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

Follow [docs/architecture.md](../docs/architecture.md) for the implemented shared core and
dependency constraints. Generate protobuf encoders; never hand-write wire encoding.

Give external calls timeouts and explicit error mapping. A timeout does not prove
remote failure; retry only under a documented duplicate-delivery policy. Never
invent idempotency support for a protocol. Do not let exporter diagnostics feed
back into the exporter indefinitely. See [docs/data-handling.md](../docs/data-handling.md).

## Tests are a contract

Every added behavior needs a test. Cover meaningful branches, declared errors,
and boundary cases. For reproducible bugs, first demonstrate the expected behavior
with a failing regression test, then fix the root cause.

Do not weaken assertions, delete tests, skip checks, or change expectations to hide
regressions. For an authorized contract change, the spec writer revises the tests and the reviewer accepts them again; explain the changed contract. Ask for human review only when the expected behavior remains unresolved or exceeds the user's authorization. If an
existing specification appears wrong and the task does not resolve it, flag that
ambiguity before changing its meaning.

Use the cheapest layer that proves behavior: doctests, ExUnit public API tests,
adapter tests, process integration, then a consumer package smoke test. Keep tests
deterministic and isolated; no live provider requests or production credentials.
Read [docs/testing.md](../docs/testing.md) for setup and verification details.

## Commands and delivery

These are the current CI checks, run from the repository root:

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
MIX_ENV=test mix cucumber
mix credo --strict
```

Also run `mix dialyzer` before code commits. CI runs `mix hex.audit`,
`mix docs --warnings-as-errors`, and `mix hex.build` as well. Strict Credo analysis
is required before code commits and runs in both CI toolchain jobs before package
checks. There is no custom verification alias. Do not claim unavailable or skipped
checks passed.
Before handoff, run relevant checks and report failures, skipped checks, and gaps.
Documentation-only edits need link/content checks, not new behavior tests.

Keep commits atomic, focused, and independently valid. Follow trunk-based
conventions with short-lived branches, a linear history, and no merge commits.
Use conventional commit prefixes (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).
Run applicable checks before committing. Preserve others' changes; never force-push
or rewrite shared history. The user explicitly authorizes atomic commits and a push
after each completed commit. Keep each phase on its branch and open a PR.

Before a release, follow [docs/submission/readiness.md](../docs/submission/readiness.md).
Packaging and dry runs are local preparation. Publish to Hex or upload documentation
only when requested or already authorized; a Git push does not authorize publishing.
