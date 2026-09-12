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
was inspected during the initial documentation pass. Phase 1 inspection and fixture
provenance are recorded below.
The plan reports the hub's metrics endpoint is not ready. Use the fake collector and
real OTel Collector for conformance instead of making the hub a development dependency.

## Phase 0 implementation record

Shared configuration/resource/value encoding, generated OTLP envelopes, Finch
transport, a bounded ingress ring, and the Bandit fake collector are implemented.
Bootstrap greeting functions/tests were intentionally replaced by the real package
example; they were not a product contract. Logger and metrics adapters are pending.

Use `Config.new/3` for pure resolution, `Config.load/2` for runtime environment
reads. `:endpoint` means an exact signal endpoint; `:base_endpoint` appends the
signal path. Defaults and limits are documented in the root README.

Pin Finch to the 0.20 series initially. Generate namespaced gpb modules from vendored
OTLP schemas v1.5.0. gpb is needed for consumer compilation, not release runtime.
Decode bounded collector responses to observe partial rejection; no telemetry
payload ingestion is implemented. This refines the plan's encoding-only shorthand.
Retry HTTP 502/504 as well as 429/503, following the OTLP specification.

The ingress ring uses fixed ETS slots and atomic sequence numbers. Producer
notifications are coalesced; batch export happens in a separate linked task with a
watchdog. A queue plus one in-flight batch is bounded; durability and strict
cross-producer ordering are not promised. Handles must be reacquired after restart.

## Phase 1 upstream recheck — September 12, 2026

The Hex package APIs still list `opentelemetry` 1.7.0 and
`opentelemetry_experimental` 0.5.1 as the latest releases:
[stable SDK](https://hex.pm/api/packages/opentelemetry) and
[experimental SDK](https://hex.pm/api/packages/opentelemetry_experimental).
No newer experimental release has replaced the version investigated by the recipe.
Proceed with the log handler as planned; recheck again before release.

Read the local `elixir_as_inf/examples/otlp_log_handler.ex` recipe and its fixture
provenance. Preserve its severity mapping, structured report bodies, and internal
metadata exclusions. Record conversion uses bounded AnyValue encoding, validates
complete trace/span ID pairs, and counts omitted attributes separately from
truncated values. The full SDK remains outside the runtime dependency graph.

## Phase 1 implementation record

The supervised Logger adapter and record conversion are implemented. See README for
startup ownership, independent instance names, byte/count defaults, and exclusions.
The original recipe fixture is copied unchanged under `test/fixtures/otlp` and
compared at the record level after generated encoding/decoding. Instrumentation scope
identifies `otlp_shipper` instead of the original copied handler's `Elixir.Logger`.

The tracing SDK is test-only; optional API calls remain guarded. A real-span test
exposed stale process metadata after detaching to an empty context in API 1.5.
Ignore inherited IDs in that case; a distinct event-level pair is still respected.

Finch's killed supervisor can leave named descendants briefly alive. Restart retries
for at most one second only after that tree successfully started once. Initial name
collisions remain failures. This prevents a tight restart-intensity failure loop.

## Phase 2 implementation record

MetricsReporter implements counters, sums, last-value gauges, and distributions.
Summaries return `{:error, :unsupported_metric, :use_distribution}`. Delta intervals
reset on snapshot regardless of export success; empty intervals emit nothing. Gauge
points use observation time and no start time. Sum monotonicity becomes false after
an accepted negative value and stays false until restart. Histogram sum is omitted
for negative observations, following the vendored schema's compatibility requirement.

Default bounds are 1000 active series and 2048 pending observations per reporter,
plus the shared point queue and batch limits. Series caps reset each interval; first
admitted series keep their slots and overflow is counted. Tags are limited to 32
scalar attributes / 4096 external bytes and never truncated. Duplicate names and
unsupported units/reporter options fail startup. Histograms require explicit buckets;
empty buckets mean one catch-all bucket and at most 256 finite bounds are accepted.

The installed Telemetry.Metrics 1.2.0 source confirms that constructors wrap unit
conversion into measurement functions; the reporter does not convert twice. Counters
still require a non-nil measurement. Keep executes first, then measurement and tags.
These contracts follow the [reporter guidance](https://hexdocs.pm/telemetry_metrics/writing_reporters.html).
Delta interval and gauge distinctions follow the
[OTel data model](https://opentelemetry.io/docs/specs/otel/metrics/data-model/).

No new dependency is introduced. Pool startup moved to the shared core so metrics
never import the Logger implementation. The consumer-release smoke exercises both
signals with the tracing API and SDK absent. Real Collector conformance remains
Phase 3; public Hex publication still requires authorization.

## Phase 3 conformance and release preparation

The opt-in Mix task uses official Collector 0.160.0, pinned by image digest, with
its detailed debug exporter. It sends synthetic data through both public components
in a separate VM after removing inherited OTEL configuration. Default CI remains
Docker-free. The real Collector's empty partial-success response exposed a transport
classification defect: empty means full success per the vendored schema; warning-only
responses still report partial status without a drop count.

Release consumer checks now cover minimum direct dependencies and optional API
presence/absence. gpb 4.21.0 failed on OTP 29's reserved `else`; the supported minimum
is 4.21.7. The optional API's 1.3.0 lower bound works for the no-active-span consumer
but warns about `link/2` on OTP 29. README recommends API 1.5.0 there. CI additionally
checks the minimum supported Elixir 1.19.0 / OTP 28.0 combination.

Public Hex intent does not authorize publishing, reserving the name, or changing
GitHub visibility. The name API returned 404 and the source remained private on
September 12, 2026. Upstream experimental's latest release remained 0.5.1. Candidate
checksums and final release prerequisites belong in `submission/`.
