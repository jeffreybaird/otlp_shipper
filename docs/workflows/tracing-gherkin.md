# Tracing acceptance specifications

## Scope

The owner requested Gherkin after expanding the tracing plan and installing
CucumberEx. [Tracing scenarios](../features/tracing.feature) describe PLAN.md's
TRC-01–11 contracts across Phases 4–7. This change writes specifications only;
it does not implement tracing or claim passing exporter acceptance tests.

Base: `d23c249`, the merged CucumberEx integration on `codex/trace-export-plan`.
Branch: `codex/tracing-gherkin`. The orchestrator owns this record and delivery;
the spec writer owns the feature; the runner validates syntax and the reviewer
checks contract coverage. No production implementation role is needed for this
specification-only task.

## Execution handoff

Each scenario carries a unique ID, an acceptance-contract tag, and a phase tag.
Phase 4 probes establish compatibility and record unresolved contracts before
later phases implement the exporter. Proposed numeric defaults in PLAN.md remain
proposals; scenarios use configured or approved limits rather than inventing them.

During each implementation phase, add real CucumberEx step definitions and
register its ready feature files in `config/config.exs`, splitting this specification
by phase if necessary while preserving IDs. Establish meaningful failing assertions
before implementing behavior. Keep strict undefined/pending-step handling enabled.
Do not use empty step definitions, skip tags, or passing placeholders.

This planned feature is not registered in the currently executable configuration
suite. Parser validation proves Gherkin syntax only. It is not evidence that tracing
works. Lower-level ExUnit and real-SDK/collector tests must be mapped at each phase;
no nonexistent test filenames or green results are claimed here.

## Coverage and verification

The specification contains 53 scenarios with stable `TRC-XX-YY` names.

| Acceptance ID | Scenarios | Coverage |
| --- | ---: | --- |
| TRC-01 | 3 | Optional dependencies and logs/metrics preservation |
| TRC-02 | 3 | SDK compatibility, callbacks, sampling |
| TRC-03 | 4 | Field mapping, IDs, timestamps, typed values |
| TRC-04 | 6 | Configuration, precedence, HTTP settings, restart |
| TRC-05 | 2 | SDK resources and instrumentation scopes |
| TRC-06 | 3 | SDK batching, ETS lifetime, producer isolation |
| TRC-07 | 9 | Acceptance, rejection, limits, diagnostics, feedback |
| TRC-08 | 8 | Retry budgets, deadlines, cancellation, duplicates |
| TRC-09 | 7 | Startup, independence, recovery, flush, shutdown |
| TRC-10 | 4 | Correlation, parentage, exceptions, instrumentation |
| TRC-11 | 4 | Packaged replacement, real Collector, migration, release |

Each scenario's phase tag determines its implementation handoff. No production,
test-runner configuration, existing tests, or dependency files changed.

## Validation and review

The installed CucumberGherkin parser returned 55 envelopes, 53 scenario pickles,
and zero parse errors. Scenario names are unique and tags cover TRC-01–11.
Feature SHA-256: `4569980580450a64b552e343c896a61b881166443e5c76b2881ae78c68c929d9`.
The runner used `MIX_ENV=test mix run --no-start` and `CucumberGherkin.parse_path/2`;
no tracing scenario was executed. `git diff --check` and local document links passed.
Runtime tests were not rerun for this specification-only change.

Independent review found one missing Phase 4 suppression probe (GHR-01).
TRC-07-09 adds that gate without changing the Phase 6 scenario. Re-review resolved
the finding with no further contract or coverage issues.
