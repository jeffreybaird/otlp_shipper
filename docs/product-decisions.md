# Package scope and decisions

[../PLAN.md](../PLAN.md) is the intended design, not evidence of implemented features.
The user has authorized development, atomic commits, and a push after each commit.
Version 0.1.1 is the current public release; dated scaffold and phase sections preserve earlier
observations, with current release verification linked at the end.

## Planned scope

- One package with independent logger-handler and `Telemetry.Metrics` reporter
  components, plus a planned SDK-compatible trace exporter. Share transport,
  generated encoding, and configuration conventions; only logs/metrics share buffering.
- OTLP/HTTP protobuf logs and metrics are implemented. Trace export is planned in
  PLAN.md Phases 4–7; no replacement SDK/API, new instrumentation framework, or
  dependency on a particular hub or Phoenix application is included.
- Required `telemetry_metrics` and `telemetry`; optional, guarded
  `opentelemetry_api` for log correlation. Vendor protocol sources and generate
  encoders with gpb; do not depend on `opentelemetry_exporter` or reuse its codecs.
- Bounded batching, drop-oldest overflow for logs, bounded retries, drop-on-failure,
  and observable export/drop outcomes. Export must not take down the host application.
- Delta metrics: counters, sums, gauges, explicit-bound histograms; reject summaries
  at initialization. Apply tag and unit transformations before aggregation.
- First release: `0.1.0`, MIT, ExDoc, compatibility CI, audit and Dialyzer.
  MIT license text and matching package metadata are included.

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
Hex lists `jeffreybaird` as owner and publisher of 0.1.0 as of September 13, 2026.
HexDocs is public; GitHub source/support links remain private.

## Implementation decisions

Finch supplies pooled HTTP; the package owns retry scheduling and export policy.
The GitHub repository is currently private. The owner published 0.1.0 to public
Hex on September 13, 2026. This does not change GitHub visibility or authorize
further release uploads.

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

## Publication — September 13, 2026

The owner published 0.1.0 after Phase 3 merged. Hex metadata and the downloaded
archive match the reviewed candidate checksum, and versioned HexDocs returns HTTP
200. See [release verification](submission/release-0.1.0.md). Earlier phase notes
above describe the state at that phase, including prerequisites since resolved.

## Finch compatibility — 0.1.1

Version 0.1.1 was published September 13, 2026 at 15:47:57 UTC. It widens Finch
from `~> 0.20.0` to `~> 0.20`, allowing `>= 0.20.0` and `< 1.0.0`, including
consumers already using Finch 0.21.x. Other dependency requirements and runtime
behavior are unchanged. See [0.1.1 verification](submission/release-0.1.1.md).

## Tracing scope expansion — September 16, 2026 (planned)

The owner requested expanding PLAN.md to handle tracing. The approved direction is
an SDK-compatible OTLP/HTTP trace exporter, proposed as `OtlpShipper.TraceExporter`,
sharing the existing core. Preserve the tracing API/SDK and existing instrumentation.
The SDK owns batching, span lifecycle, sampling, and context; shipper owns conversion,
transport retries within a deadline, and exporter diagnostics. Do not add another
trace buffer or retain SDK-owned ETS data after the export callback.

SDK resources and instrumentation scopes remain authoritative for traces. Existing
logs/metrics APIs and optional tracing behavior stay intact. Tracing consumers supply
a supported SDK/API pair; non-tracing consumers must still compile and run without
them. The exact optional compilation, startup/cleanup, resource/configuration,
callback result, limit, and timeout contracts require evidence in Phase 4 before
their implementation. This planning change makes no dependency or runtime changes.

Phases 4–7 cover compatibility/contracts, protocol/core, SDK integration, and
replacement-consumer/Collector proof with migration and release preparation.
Each phase waits for its predecessor's merge. A full tracing SDK replacement,
gRPC, durable queues, metric exemplars, and global auto-configuration are deferred.
The current release remains 0.1.1 with logs/metrics only; a candidate tracing release
is a future readiness decision, not publication authorization.


## Phase 4 compatibility investigation — September 17, 2026

The [trace compatibility decision record](decisions/trace-compatibility.md) defines
the initial SDK 1.7.0/API 1.5.0 target and the proposed Phase 5–6 boundaries.
Test-only probes exercise real SDK batches, ownership, cancellation, flush, retry,
queue admission, restart, and record fidelity. A fresh consumer prototype proves
optional-SDK compilation with a dependency-ordering edge; the real package's SDK
dependency remains test-only until its guarded adapter is implemented.

The owner approved a consumer-configured delegating sampler wrapper to prevent
exporter HTTP feedback. Real Finch instrumentation probes verify marked requests
are not sampled and ordinary sampling resumes. The package must not install that
sampler into consumer configuration automatically. Supported instrumentation scope
and remaining implementation obligations are explicit in the decision record.

Phase 4 merged in PR #16 on September 17, 2026. Its probes implement no production
SDK exporter. Version 0.1.1 remains logs/metrics only.


## Phase 5 protocol core — unreleased

The trace core accepts normalized maps independently of SDK record definitions.
`TraceRecord` preserves supported fields and rejects malformed or oversized spans;
`TraceEncoder` groups original scope name, version, and schema under the authoritative
resource. Vendored v1.5.0 trace schemas generate a package-owned codec at build time.
No dependency change or canonical-exporter codec reuse is needed.

Trace-only `Config.transport/3` resolves request options without creating a resource
or borrowing log queue settings. `TraceBatch.export/6` consumes a finite enumerable
with its declared count, constructs count/byte-bounded requests, and returns accepted,
rejected, invalid, failed, and unsent counts. One linked worker bounds conversion,
enumeration, encoding, HTTP, retries, and diagnostics under a shared deadline.
A parent-owned ETS snapshot commits outcomes before synchronous telemetry callbacks.
Cancellation may omit diagnostics; it cannot erase an already committed acceptance.
Failed means submitted without confirmed acceptance, not proof of remote failure.

The core does not add a span queue. Accepted chunks are never replayed after later
failure. A late source-count mismatch retains prior delivery and returns an error.
Production SDK callbacks, lifecycle ownership, optional SDK compilation, and the
approved sampler wrapper remain Phase 6. The packaged-consumer smoke exercises
raw trace-core HTTP delivery without the SDK, canonical exporter, or runtime gpb;
it does not replace Phase 7's real-instrumentation migration proof.


## Phase 6 SDK integration — unreleased

The optional guarded exporter targets SDK 1.7.0 / API 1.5.0 and rejects unverified
version pairs at initialization. The SDK dependency is now optional instead of
test-only, providing the consumer compilation-order edge established in Phase 4.
Logs/metrics consumers still do not install it. Adding the SDK later requires
recompilation; the package does not hot-enable the adapter.

The consumer supplies a named Finch pool. `TraceExporter.pool_child_spec/1` uses the
existing bounded restart boundary; the consumer places it before the SDK provider
in a `:rest_for_one` tree. Export and shutdown own neither the pool nor another
span queue. A lazy ETS stream normalizes one source record at a time inside the
callback's shared deadline. ETS copies that source record before validation;
subsequent normalized allocation is bounded, but SDK retention is not.

The approved sampler wrapper delegates ordinary sampling and drops spans marked
inside actual shipper HTTP workers, including log/metric requests. It restores the
previous context and never installs itself globally. The supported feedback proof
uses synchronous Finch instrumentation 0.2.0; cross-process instrumentation is not
implicitly covered. SDK resources/scopes and exposed dropped counts remain
preserved. Scope attributes and link flags absent from these SDK records cannot be
exported. Original event/link order is restored from SDK storage order.

The SDK timeout should exceed the exporter budget by at least 2,000 ms. Flush
return remains asynchronous, and SDK termination may omit exporter shutdown.
Partial/invalid or already-partly-accepted batches map to permanent failure;
transient exhaustion before any confirmed acceptance maps to retryable failure,
without implying SDK requeue. Invalid-init diagnostics have a 100 ms internal
budget, so a blocked subscriber cannot hang provider startup. Real Collector trace
conformance and the complete replacement/migration proof remain Phase 7. Hex 0.1.1
still ships logs and metrics only; no new release has been published.


## Phase 7 release preparation — unpublished 0.2.0 candidate

The source includes the SDK exporter, migration guide, three-signal packaged
consumer, and pinned real Collector trace/correlation verification. The supported
SDK/API pair remains 1.7.0/1.5.0 in both shared-dependency modes. Representative
Finch instrumentation is a separate fixture dependency, not a new library runtime
dependency. The canonical exporter and runtime gpb are absent from that proof.

Consumers own the global SDK as an included application and start its Finch pool
first. The optional SDK dependency has `runtime: false`, preserving compilation
ordering without imposing application startup. The consumer makes startup ownership
explicit; its own direct SDK dependency must match the chosen ordinary/included
application arrangement. The SDK creates global application tracers normally.
The library never installs sampling or configuration globally. See the migration
guide for startup, resource consistency, and the verified SDK-specific boundary.

The candidate version is 0.2.0. It is not a public release; 0.1.1 remains the
published logs/metrics package. Release authorization, final merged revision,
publication and public-install verification are separate from development.
See the [Phase 7 work record](workflows/phase-7-trace-release.md) for current evidence.
Elapsed time, VM snapshots and dependency inventory are descriptive observations;
no comparative throughput, allocation, retained-memory, or package-size advantage
is claimed. API/SDK replacement, gRPC, durable storage, and global auto-configuration
remain outside scope.
