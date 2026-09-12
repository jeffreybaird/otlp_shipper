# Package scope and decisions

[../PLAN.md](../PLAN.md) is the intended design, not evidence of implemented features.
The user has authorized development, atomic commits, and a push after each commit.

## Planned scope

- One package with independent logger-handler and `Telemetry.Metrics` reporter
  components sharing configuration, resource/value encoding, transport, and buffering.
- OTLP/HTTP protobuf logs and metrics to configurable collectors. No trace exporter,
  full metrics/logs SDK, or dependency on a particular hub or Phoenix application.
- Required `telemetry_metrics` and `telemetry`; optional, guarded
  `opentelemetry_api` for log correlation. Vendor protocol sources and generate
  encoders with gpb; avoid `opentelemetry_exporter` except the documented fallback.
- Bounded batching, drop-oldest overflow for logs, bounded retries, drop-on-failure,
  and observable export/drop outcomes. Export must not take down the host application.
- Delta metrics: counters, sums, gauges, explicit-bound histograms; reject summaries
  at initialization. Apply tag and unit transformations before aggregation.
- Target first release: `0.1.0`, MIT, ExDoc, compatibility CI, audit and Dialyzer.
  MIT is the plan's selected license; its text/metadata have not yet been added.

See [architecture.md](architecture.md) and PLAN.md for detailed acceptance contracts.

## Observed scaffold — September 12, 2026

- OTP application `:otlp_shipper`; module `OtlpShipper`; version `0.1.0`.
- Elixir requirement `~> 1.19`; development pins `1.19.5-otp-28` / Erlang `28.5.0.2`.
- Greeting/format examples and their ExUnit/doctests are the only implementation.
- No dependencies or application callback; Logger is an extra application.
- CI fetches dependencies, checks formatting, compiles, and runs tests.
- Placeholder README/description, empty license metadata/links, no project license,
  no ExDoc, and no Dialyzer setup. No package release has been verified here.

## Confirmed owner decisions

These decisions supersede the corresponding open questions in PLAN.md:

- Package name: `otlp_shipper`.
- Distribution: public Hex.
- Metrics integration: `Telemetry.Metrics` reporter confirmed.
- HTTP client: Finch directly, confirmed.
- Module root: preserve the scaffold spelling `OtlpShipper`.

PLAN.md's `OTLPShipper` names are implemented under `OtlpShipper`.
Hex name availability/ownership and public source/support URLs still need verification.

## Implementation decisions

Finch supplies pooled HTTP; the package owns retry scheduling and export policy.
The GitHub repository is currently private. Public Hex is authorized as the intended
distribution, not a request to change GitHub visibility or publish a release now.

Also define concrete limits, retry budgets, shutdown deadlines, and supported version
combinations before implementing their behavior. Record choices and compatibility
impact here. No owner answers are needed just to finish this documentation task.

## Phase boundaries and evidence

Use one branch and PR per phase; do not start the next before the previous merges.
Read PLAN.md end to end before starting. Recheck the upstream logs SDK/exporter at
the start of Phase 1; if a working replacement has shipped, report back before building
the handler. The plan's ecosystem/version claims are research inputs to recheck,
not permanent facts this documentation independently verifies.

The plan references a handler recipe and binary fixture in `elixir_as_inf`; neither
was inspected or copied by this task. Verify access and provenance before reuse.
The plan reports the hub's metrics endpoint is not ready. Use the fake collector and
real OTel Collector for conformance instead of making the hub a development dependency.
