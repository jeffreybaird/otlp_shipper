# PLAN.md — OTLP logs, metrics, and traces for Elixir

A package build plan. The five-role workflow in AGENTS.md and
[docs/codex-agents.md](docs/codex-agents.md) governs agent coordination. Read it end to end before starting; the
packaging decision in §2 and the dependency decision in §4 shape everything after.

## Current scope and status — September 20, 2026

`otlp_shipper` is one Hex package, under the `OtlpShipper` module root, providing
Elixir-native collection and a shared OTLP/HTTP protobuf export layer. Logs and
metrics shipped in 0.1.0; 0.1.1 widened Finch compatibility. Phases 0–3 are complete.
[Product decisions](docs/product-decisions.md) and the
[release record](docs/submission/release-0.1.1.md) describe implemented behavior.

The owner has expanded the planned scope to **SDK-compatible trace export**.
Phases 4–6 have merged. Phase 7 implements replacement proof, migration, and
preparation of an unpublished 0.2.0 candidate on its phase branch. The public 0.1.1 release still provides logs/metrics
only. Development does not publish a release or authorize replacing the tracing SDK.

Confirmed decisions:

- Keep one package and Finch directly; share transport, protocol generation,
  configuration conventions, and diagnostics across signals.
- Preserve `OtlpShipper.LogHandler` and `OtlpShipper.MetricsReporter` behavior.
- Add a proposed `OtlpShipper.TraceExporter` through the existing SDK exporter
  interface. Retain `opentelemetry_api`, the tracing SDK, and existing instrumentation.
- The SDK owns span creation, sampling, context propagation, and trace batching.
  Shipper owns conversion, OTLP/HTTP requests, bounded transport retries, and
  exporter diagnostics. Do not add a second trace queue.
- Logs-only and metrics-only consumers must remain usable without the tracing SDK
  or `opentelemetry_exporter`. Trace consumers supply the supported SDK/API pair.
- Public Hex distribution and atomic commits/pushes remain authorized. Each new
  phase has its own branch/PR and waits for the preceding phase to merge.
  Publication remains separately authorized.

Original `OTLPShipper` names in the completed-phase design below mean
`OtlpShipper`. Original recipe/ecosystem observations are historical, not current
compatibility evidence. The tracing contract and phase gates in §§12–16 supersede
any original two-signal design assumptions.

---

## 1. What this is

Three planned entry points send telemetry from an Elixir app to an OTLP/HTTP
collector. The implemented logs/metrics components do not run the OpenTelemetry
SDK's logs or metrics machinery:

- **`OTLPShipper.LogHandler`** — a `:logger` handler that batches log events and POSTs
  them as `ExportLogsServiceRequest`. Records logged inside an `opentelemetry` span
  carry that span's ids, so logs and traces correlate.
- **`OTLPShipper.MetricsReporter`** — a `Telemetry.Metrics` reporter (the same shape as
  `TelemetryMetricsPrometheus` / `TelemetryMetricsStatsd`) that aggregates metric
  definitions over an interval and POSTs them as `ExportMetricsServiceRequest`.
- **`OtlpShipper.TraceExporter` (planned)** — an SDK exporter adapter that converts
  completed spans and sends `ExportTraceServiceRequest` to `/v1/traces`.

The initial replacement target is the canonical exporter's **OTLP/HTTP trace
export role**, not the entire OTel stack. Existing Phoenix/Ecto/HTTP instrumentation
continues to use the OTel API and SDK. The Logger/Telemetry.Metrics pipelines are
alternatives to the experimental logs/metrics SDK, not implementations of its APIs.

The immediate consumer is `elixir_as_inf` (a personal OTLP hub) and the apps that feed
it — Marquee and residency-schedule — but nothing in the package may assume that hub.
It targets the OTLP/HTTP spec, so it works against an OTel Collector, Grafana Alloy,
Honeycomb, or anything else that speaks the protocol.

---

## 2. One package or two? — **One.**

Keep a single package exposing three independent signal components. Shared
configuration, generated protobuf infrastructure, Finch transport, response handling,
retry policy, and conformance fixtures remain the principal reason for one package.
Adapters depend on shared core, never on one another. Trace integration must not
make the full SDK mandatory for logs or metrics consumers.

The log handler is no longer scheduled for automatic removal merely because
upstream support improves. Evaluate continued value, migration costs, and consumer
needs before proposing any deprecation. Recheck upstream before making compatibility
or performance claims. Split a component only if independent maintenance or release
cadence provides a concrete benefit.

---

## 3. Original motivation and current direction

The following bullets record the original September 12, 2026 investigation. They
are not claims that all present or future upstream versions fail:

- `opentelemetry` 1.7.0 ships **no logs handler** — there is no `otel_log_handler` in
  its `src/`.
- `opentelemetry_experimental` is the package that would carry logs and metrics SDKs.
  Its released version (0.5.1) predates `opentelemetry_exporter` 1.10's logs entry
  point and raises `undef` on export; the unreleased 0.6.0 on main hands a map to an
  exporter that expects an ETS table and raises `badarg`. Neither path emits a request.
- `telemetry_metrics` 1.2.0 has reporters for Prometheus, StatsD and others, but **none
  for OTLP**.

Those findings motivated an alternative logs/metrics path. A working
~200-line `:logger` handler already exists as a copy-into-your-app recipe at
`elixir_as_inf/examples/otlp_log_handler.ex`; this package is that recipe hardened,
tested, and joined by the metrics half.

Phase 1's recheck and subsequent release evidence are in product-decisions.md.
For tracing, compete on a coherent export layer and explicit operational contracts;
do not assume the stable upstream trace exporter is broken. Phase 4 rechecks current
SDK/exporter releases and their actual integration surfaces before choosing a
supported version matrix.

---

## 4. The dependency decision: do not depend on `opentelemetry_exporter`

Do not depend on `opentelemetry_exporter` or reuse its generated message modules.
Vendor OTLP schemas with provenance/licenses and generate namespaced encoders with
gpb. This is already implemented for logs and metrics; extend it to traces.
Bounded export-response decoding is required for partial rejection. Production does
not ingest encoded telemetry. There is no remaining encoder fallback to the
canonical exporter.

| Dependency | Role | Contract |
| --- | --- | --- |
| Finch | Pooled OTLP/HTTP transport | Required; existing compatible range |
| telemetry / telemetry_metrics | Diagnostics and metrics definitions | Required; unchanged |
| gpb | Generated protobuf codecs | Build-time, absent at release runtime |
| opentelemetry_api | Existing optional log correlation; trace API | Remains optional for non-tracing consumers |
| opentelemetry | Trace SDK and exporter boundary | Currently test-only; trace consumers supply it; Phase 4 proves optional compilation strategy |
| opentelemetry_exporter | Replacement target | Absent from replacement consumer and dependency tree |

Do not infer dependency savings from historical claims about upstream's mandatory
or optional gRPC dependencies. Inspect the selected versions and measure the actual
consumer tree. HTTP/protobuf remains the only transport; gRPC is outside this plan.
No dependency change is made by this planning update.

---

## 5. The shared core

`OTLPShipper.Config`
: Resolve endpoint, headers, timeout, gzip and resource from explicit options over
  `OTEL_EXPORTER_OTLP_*` environment variables, per the OTLP spec's precedence rules
  (signal-specific `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` beats generic
  `OTEL_EXPORTER_OTLP_ENDPOINT`; note the spec's path-appending rule differs between the
  two). Pure, doctested.

`OTLPShipper.Resource`
: Build the `Resource` message from `service.name`, `service.version`,
  `service.instance.id` and arbitrary extra attributes, honouring
  `OTEL_RESOURCE_ATTRIBUTES`. `service.name` is required; refuse to start without it
  rather than shipping `unknown_service` for the existing logs/metrics components.
  Traces preserve the resource supplied by the SDK; see §12.

`OTLPShipper.Value`
: `AnyValue` / `KeyValue` encoding for strings, atoms, booleans, integers, floats,
  lists, maps, and a last-resort `inspect/1`. Existing logs/metrics helpers remain
  shared; trace conversion must preserve the SDK's supported attribute types.

`OTLPShipper.Transport`
: POST an encoded body with content type, bearer or arbitrary headers, optional gzip,
  a timeout, and retry with exponential backoff and jitter on `429`/`502`/`503`/`504` and transport
  errors — honouring `Retry-After` when present. Gives up after a bounded number of
  attempts and **drops the batch**. HTTP stays off Logger/telemetry producer paths.
  Trace export runs synchronously inside the SDK export worker, within a deadline;
  expected errors are mapped to the required SDK callback results.

`OTLPShipper.Buffer`
: The batching behaviour the logs/metrics components share: accumulate, flush on `max_batch` items
  or `flush_ms`, flush on terminate. **Bounded** — see §6. Traces use SDK batching.

Every export outcome emits `:telemetry`: `[:otlp_shipper, :export, :stop]` with
`%{count:, duration:, byte_size:}` and `%{signal:, status:}`, plus
`[:otlp_shipper, :export, :exception]` and `[:otlp_shipper, :dropped]` with a count and
a reason (`:queue_full | :export_failed`). Without these, a silently broken exporter is
indistinguishable from a quiet app — which is the failure mode the existing recipe has.

---

## 6. Phase 1 — the logger handler (completed original design)

Start from `elixir_as_inf/examples/otlp_log_handler.ex`. It works and its output is a
recorded fixture (`test/fixtures/otlp/elixir_fallback_logs.bin`), so the encoding is
already validated against a real consumer. Extraction is mostly hardening. **These are
defects in the existing recipe and each needs a test:**

1. **Unbounded mailbox.** `log/2` does a `GenServer.cast` per event with no
   backpressure; a log storm grows the queue until the VM dies. Bound the buffer, drop
   the oldest on overflow, count the drops, and emit them. (This mirrors the hub's own
   "drop before you fall over" principle — an exporter must never be the thing that
   takes an app down.)
2. **Unsupervised.** `adding_handler/1` calls `GenServer.start` unlinked; if that
   process dies, logging silently stops forever with the handler still installed. Put it
   under a supervisor the host app starts, or have the handler re-establish it.
3. **Silent failure.** `:httpc.request` results are ignored — a 401 from a bad token
   looks exactly like success. Emit telemetry, and log the first failure (and only the
   first, at a rate limit) through a handler-filtered path so it cannot recurse.
4. **No gzip, no retry, no timeout.**
5. **Recursion risk.** The exporter's own log output must never re-enter the handler.
   Tag it with a `domain` the handler drops.
6. **Truncation.** A single enormous log body can blow the collector's request limit.
   Cap attribute and body length, and set `dropped_attributes_count` honestly.

Keep from the original: the severity mapping, the structured-report `kvlist` body, the
`otel_trace_id` metadata handling, and dropping the internal `:logger` metadata keys.

**Acceptance:** a `Logger.info` inside an `opentelemetry` span produces an
`ExportLogsServiceRequest` whose record carries the right severity number, body shape,
attributes and the span's 16-byte trace id and 8-byte span id; the same outside a span
carries empty ids; a 10,000-event burst drops rather than growing unboundedly and
reports how many it dropped; a collector returning 503 twice then 200 results in one
delivered batch.

---

## 7. Phase 2 — the metrics reporter (completed original design)

The larger and less charted half. `use GenServer`, `start_link(metrics: [...], ...)`,
attach to each metric's event, aggregate in ETS or state, export on an interval.

**Mapping from `Telemetry.Metrics` to OTLP:**

| `Telemetry.Metrics` | OTLP                                    | Notes                                       |
|---------------------|-----------------------------------------|---------------------------------------------|
| `counter/2`         | `Sum`, monotonic                        | count of events                             |
| `sum/2`             | `Sum`, monotonic unless negatives seen   | sums the measurement                        |
| `last_value/2`      | `Gauge`                                  |                                             |
| `distribution/2`    | `Histogram`, explicit bounds             | bounds from `reporter_options[:buckets]`    |
| `summary/2`         | **refuse at init**                       | no OTLP equivalent; `Summary` is legacy/deprecated |

Refusing `summary` loudly at `start_link` is better than silently dropping it at
runtime. Say so in the error, and name `distribution` as the fix.

**Decisions to make and document:**

- **Temporality: delta.** Reset accumulators each interval; `start_time_unix_nano` is
  the start of the interval, `time_unix_nano` the end. Delta is far simpler to get right
  than cumulative and is accepted by every major backend. Cumulative can come later
  behind an option; do not build both now.
- **Tags become attributes.** `tag_values/1` runs before aggregation, as it does in other
  reporters. Cardinality is the user's problem, but document the footgun and consider a
  configurable series cap that drops-and-counts rather than exploding.
- **Units.** `Telemetry.Metrics` unit conversion (`{:native, :millisecond}`) happens
  before aggregation; the OTLP `unit` field takes the converted unit as a UCUM string
  (`ms`, `s`, `By`, `1`).
- **An interval with no events emits nothing** for that series. Do not send zeros.

**Acceptance:** a fixture app emitting known `telemetry` events produces an
`ExportMetricsServiceRequest` with exact counts, sums, gauge values and histogram bucket
counts; two consecutive intervals show delta semantics (the second does not include the
first's events); a metric with `tags` produces one data point per tag combination with
the tags as attributes; `summary/2` is refused at `start_link` with a message naming the
alternative.

---

## 8. Phase 3 — conformance, docs, release (completed original design)

- **A fake collector for tests.** A Bandit/Plug server started in the test suite that
  accepts `POST /v1/{logs,metrics}`, decodes the body with gpb and hands the decoded
  message to the test. This is the backbone of every acceptance criterion above — build
  it first in Phase 0, not here.
- **Conformance against a real collector.** A `mix` task, excluded from CI by default,
  that boots an OTel Collector in Docker with a debug exporter and asserts both signals
  arrive and parse. The fake collector proves you encode what you think; only a real one
  proves the wire format is right.
- **Docs:** a README that opens with the 10-line setup for each component, an
  `OTEL_*` configuration table, the telemetry events, the cardinality and truncation
  warnings, and an honest "when not to use this" pointing at
  `opentelemetry_experimental` for the day it works.
- **Hex release:** `0.1.0`, MIT, ExDoc, CI on the Elixir/OTP pair in `.tool-versions`,
  `mix hex.audit` and `mix dialyzer` clean.

---

## 9. Delivery order

| Phase | Outcome | Status / dependency |
| --- | --- | --- |
| 0 | Shared core and fake collector | Complete |
| 1 | Supervised Logger handler | Complete |
| 2 | Telemetry.Metrics reporter | Complete |
| 3 | Conformance, docs, release | Complete; 0.1.1 published |
| 4 | SDK compatibility probe and approved trace contracts | Complete; [decision record](docs/decisions/trace-compatibility.md), PR #16 merged |
| 5 | Trace schemas, configuration, encoding, and HTTP conformance | Complete; PR #17 merged |
| 6 | SDK exporter, bounded lifecycle, correlation | Complete; PR #18 merged |
| 7 | Replacement consumer, real Collector, migration/release preparation | Local implementation/verification complete; PR pending; [work record](docs/workflows/phase-7-trace-release.md) |

Each phase is a focused branch and PR. Do not start its successor until it merges.
Use the five-role harness for implementation: Gherkin/failing tests, independent red,
implementation, independent verification, and review. This documentation-only scope
update needs content/link checks, not invented runtime tests. Do not begin Phase 4
implementation as part of merely writing this plan.

Develop against the fake collector and official Collector, with no dependency on
a particular hub's feature schedule or production service. Phase 7 requires all
three signals in a consumer with the canonical exporter absent.

---

## 10. Original pre-Phase-0 questions (resolved)

Resolved: `otlp_shipper`, Finch directly, public Hex, and a Telemetry.Metrics reporter.
The new trace integration decisions are bounded by Phase 4, rather than reopening
these choices. See product-decisions.md for dated decisions and release evidence.

---

## 11. Conventions for the agent

The owner's house style, carried over from `elixir_as_inf` and expected here:

- Every public function has an `@doc` with at least one real doctest (exempt: functions
  that do I/O). Pure helpers — config resolution, value encoding, severity mapping,
  bucket layout — must carry doctests with real values, never placeholders.
- Every addition that adds behaviour comes with a test that validates that behaviour.
  Every `case`/`cond`/`if` arm gets a test.
- Fallible functions return tagged tuples: `{:error, :unauthorized}`,
  `{:error, :overloaded}`, `{:error, :transport, reason}`. Never a bare
  `{:error, changeset}`, never a string message from a public function.
- One function, one job. Private functions are named for what they do to the data
  (`reject_internal_metadata/1`, not `filter/1`).
- Atomic commits, conventional prefixes (`feat:`, `fix:`, `refactor:`, `test:`), linear
  history, no merge commits. A full check (`format --check-formatted`, `compile
  --warnings-as-errors`, `test`, `dialyzer`) passes before code commits.
  Documentation-only changes use content/link checks as required by AGENTS.md.
- **Never modify an existing test to make it pass**, never weaken an assertion, never
  delete a test to resolve a failure. If a test looks wrong, flag it and ask.
- Never hand-write protobuf encoding. Generate it.
- No `IO.inspect` in committed code.

Work phase by phase. Each phase is a branch and a PR; do not start the next before the
previous is merged.

---

## 12. Planned tracing contract

### Boundaries and compatibility

`OtlpShipper.TraceExporter` is the proposed public adapter name. Implement the
supported SDK's `:otel_exporter_traces` behaviour (`init/1`, `export/3`, `shutdown/1`)
without replacing its API, tracer provider, sampler, propagation, or instrumentation.
Keep ordinary conversion/configuration functions separately testable and preserve
required callback return shapes at the adapter boundary. Do not add a convenience
span-creation API or support the simple processor unless separately justified.
The initial integration target is the SDK batch processor.

The installed SDK 1.7.0/API 1.5.0 pair is a starting compatibility candidate, not
a promise to support every version allowed by a broad dependency constraint.
Phase 4 records supported minimum/current pairs, record layouts, toolchain versions,
and a consumer compilation strategy that works with the optional SDK absent.
Never silently assume that an upstream Erlang record layout is stable.

### Data fidelity and configuration

- Preserve trace/span IDs, parent ID, trace state, supported flags, name, kind,
  start/end nanosecond timestamps, status, attributes, events, links, and their
  dropped counts. Preserve resource/scope attributes and schema URLs supported by
  the selected SDK and vendored schema. Record fields the SDK cannot supply.
- The resource passed to the exporter is authoritative, including any SDK default
  service identity. Do not rebuild or overwrite it from shipper resource options
  or OTEL resource variables. Preserve original instrumentation scopes instead of
  labeling all spans as `otlp_shipper`. Logs/metrics resource validation stays intact.
- Add trace-specific endpoint, headers, compression, timeout, and protocol settings
  using the package's explicit-option > signal-environment > generic-environment
  precedence. Generic endpoints append `/v1/traces`; signal endpoints remain exact.
  Read environment at initialization; changes require restart. Keep HTTP/protobuf.
- Separate transport resolution from resource creation for the adapter. Phase 4
  specifies how existing Config APIs grow without weakening logs/metrics validation
  or accepting trace-only resource options that would silently be ignored.
- Document supported configuration, defaults, and incompatibilities. Custom CA/mTLS
  support and complete canonical-exporter configuration parity are deferred; do not
  advertise a universal drop-in replacement or silently accept unsupported options.

### Batching, limits, retries, and ownership

The SDK owns pending spans and batch scheduling. The adapter reads/converts/exports
within `export/3`; it does not enqueue a second batch or retain the SDK's ETS table
after returning. Materialize only bounded chunks for encoding. Initial proposed
shipper limits reuse 512 spans per request, 65,536 bytes per span, 1,048,576 encoded
request bytes before gzip, and 65,536 response bytes; Phase 4 specifies the span-size
measurement and envelope accounting before these become public contracts.

An oversized SDK batch is processed as bounded requests under one callback deadline.
Drop an individually oversized/invalid span with an honest count; never fabricate
IDs, split one span across requests, or silently change its meaning to make it fit.
Define accounting for unsent chunks after a timeout and for partial success across
chunks. A sent chunk must not be replayed just because a later chunk failed.

Use one total callback budget covering conversion, requests, and all retry waits;
the proposed default is 10,000 ms with at most three transport retries per request.
Coordinate that budget with the SDK export-worker timeout; do not reset the total
deadline for each chunk. Phase 4 must prove enforcement during conversion as well
as HTTP, choose the required timeout margin, and document SDK configuration.
Retry only the shared policy's retryable errors; honor Retry-After. Do not retry
partial rejection, permanent failure, or successful chunks. Lost responses can
still cause duplicate delivery; no durable or exactly-once promise is made.

Keep SDK queue limits separate from shipper request limits. The inspected SDK checks
queue size periodically: its setting is not a strict bound guaranteed by shipper.
Measure burst behavior and disclose the total retention boundary. Do not claim
that introducing an exporter fixes the SDK's queue admission behavior.

Finch ownership, startup ordering, independent instance names, restart behavior,
and cleanup must be specified and demonstrated in Phase 4. All owned processes
must be supervised; do not rely on an unlinked process or another application's
global Finch configuration. The package must not mutate the consumer's SDK or
application environment to register itself. Publish a tested consumer-owned startup
sequence before exposing an operational configuration example.

### SDK results, flush, shutdown, and diagnostics

The inspected SDK's exporter contract returns `{:ok, state} | :ignore` from init,
`:ok | :success | :failed_not_retryable | :failed_retryable` from export, and `:ok`
from shutdown. Internal helpers keep specific tagged errors. Phase 4 records the
exact mapping for invalid configuration, encoding errors, exhausted retries,
deadline expiry, full success, and partial success; diagnostics must remain bounded
and must not contain credentials or span payloads.

Local SDK 1.7.0 inspection found four integration constraints to verify in the probe:

1. Its batch worker deletes the ETS table after the exporter returns.
2. The processor can kill the export worker at its configured deadline; no orphaned
   shipper conversion/retry task may survive cancellation. A request already sent
   can still be processed remotely; cancellation cannot establish non-delivery.
3. Returning `:failed_retryable` does not itself requeue spans in this processor.
   Own retries inside the transport budget; do not depend on that callback result.
4. Its force-flush call is asynchronous, and its termination path does not guarantee
   invoking exporter shutdown. Do not equate flush return with delivery or depend
   solely on `shutdown/1` to release owned resources.

Emit the existing export/drop diagnostics with `signal: :traces`, counting spans
rather than requests or bytes. Phase 4 defines per-request versus per-callback
accounting and maps partial rejection without double-counting drops. Reuse recursion
guards and prevent exporter HTTP work from creating an endless stream of spans
under supported HTTP instrumentation. Keep bounded shutdown best effort and expose
its limits; do not promise delivery after a process/node crash.

## 13. Phase 4 — compatibility probe and contract decisions

**Goal:** prove that this adapter can integrate safely before committing to a public
lifecycle/dependency contract. No replacement SDK work.

Deliver a decision record with a minimal synthetic SDK consumer/probe, supported
version matrix, and evidence for the constraints in §12. Inspect current upstream
releases, callbacks, records, retry behavior, flush/shutdown, queue behavior, and
the transport suppression API. Verify without production services or credentials.

Resolve these implementation gates:

| Decision | Required evidence / result |
| --- | --- |
| Optional SDK compilation | Logs/metrics consumer compiles and releases with tracing dependencies absent; select guarded adapter or another explicit isolation strategy |
| SDK startup and Finch lifetime | Tested initialization order, supervised ownership, two independent instances, teardown even when exporter shutdown is not called |
| Resource/scope conversion | Mapping table for supported record/proto fields; preserve SDK identity; proposed pure conversion and encoding API shapes |
| Callback outcomes | Exact SDK return/diagnostic matrix, partial success, chunk failure, invalid data, timeout and exhausted retry policy |
| Limits and deadlines | Numeric defaults, units, memory/queue scope, byte measurement, chunking, cancellation, and SDK timeout margin |
| Feedback suppression | Exporter HTTP does not create new exportable spans with supported instrumentation; logs/metrics guards remain effective |

Write Gherkin scenarios mapped to the acceptance IDs in §16 and tests/probes for
actual observed behavior. New behavior tests go red before implementation. A probe
must not become a hidden runtime dependency or a production tracing implementation.
Ask the owner only if evidence requires changing the agreed public scope; settle
routine details autonomously. Phase 4 is complete when these decisions have
evidence, no unresolved public-contract blocker remains, and its PR is merged.

## 14. Phase 5 — trace protocol and shared core

**Goal:** fake-collector-verified trace requests through the existing HTTP core.

- Vendor trace/service schema inputs with provenance and generate namespaced codecs.
  Decode bounded trace responses, including rejected-spans counts.
- Add pure span conversion and scope-aware envelopes; support multiple original
  scopes without changing the current logs/metrics encoding contract.
- Extend trace configuration and transport signal handling according to Phase 4.
  Add fake collector `/v1/traces`, deterministic retry/partial-response cases, and
  exact decoded-payload assertions, including boundary values and rejected inputs.
- Implement bounded request construction/chunking and propagate a shared deadline
  through conversion and transport. Preserve accounting when some chunks succeed.
- Keep all current logs/metrics checks and fresh non-tracing consumer checks green.

**Exit:** TRC-01, 03–05, and protocol portions of TRC-07/08 pass; generated codecs
work without gpb at release runtime. This phase does not claim a usable SDK adapter
or update release documentation to imply tracing has shipped. Merge before Phase 6.

## 15. Phase 6 — SDK adapter and correlated operation

**Goal:** existing SDK instrumentation exports via `OtlpShipper.TraceExporter`.

Implement the approved callbacks and supervised lifecycle, keeping export
synchronous inside the SDK worker. Integrate callback result mapping, deadline and
cancellation handling, request limits, diagnostics, and instrumentation suppression.
Use real supported SDK versions in integration tests, not only handcrafted record
maps or mocks. Retain API/SDK/instrumentation ownership outside shipper.

Prove root/nested/remote-parent relationships, sampled versus unsampled behavior,
exceptions/status, events/links, multiple scopes, concurrent producers, repeated
flushes, restarts, timeout, and shutdown. Test Logger correlation with an active span
and context cleanup afterward. A flush initiation must not be asserted as successful
delivery; observe the collector/export outcome to establish completion.

**Exit:** TRC-02 and 06–10 pass with the chosen SDK/API matrix. No HTTP runs in span
producer callbacks under the supported batch configuration; no ETS handle or retry
work survives export completion/cancellation. Publish tested startup instructions
and all lifecycle limitations. Merge before Phase 7.

## 16. Phase 7 — replacement proof, migration, and release preparation

**Goal:** prove the advertised replacement in a real packaged application.

Run a fresh production consumer with `opentelemetry_exporter` absent that emits all
three signals. Exercise at least one representative existing instrumentation library
in a separate consumer fixture; any Phoenix/Ecto/HTTP fixture dependencies must not
enter the library runtime dependency tree. Include supported minimum/current SDK
pairs and non-tracing consumers. Extend opt-in real Collector conformance to spans
and correlated logs; assert payload values/relationships, not merely HTTP 200.

Provide migration guidance showing retained API/SDK/instrumentation dependencies,
exporter replacement, consistent resource configuration, endpoint precedence,
startup/flush/shutdown, retry duplicates, limitations, and rollback to the canonical
exporter. Keep its dependency out of the replacement proof even if a separate
comparison fixture uses it. Record throughput, allocation/retention, and dependency
measurements before claiming a performance or size advantage.

Prepare a candidate additive release (working target `0.2.0`, confirmed during
readiness) following [release readiness](docs/submission/readiness.md). Run the
normal package gate, audit, ExDoc, package build/smokes, and real Collector checks.
Update README/CHANGELOG and product-decisions.md to distinguish implemented features
from remaining plans. Publishing to Hex or uploading documentation still requires
release authorization.

| ID | Acceptance contract | Required proof |
| --- | --- | --- |
| TRC-01 | Existing logs/metrics operation and optional-dependency behavior preserved | Fresh production release with SDK/API/exporter absent; regression suite |
| TRC-02 | SDK exporter interface works without replacing instrumentation | Real supported SDK/API matrix and callback assertions |
| TRC-03 | Span fields and dropped counts retain their meaning | Conversion boundaries and decoded fake-collector messages |
| TRC-04 | Trace endpoint/env/options use documented precedence | Pure configuration and HTTP boundary tests |
| TRC-05 | SDK resources/scopes stay distinct and authoritative | Multiple resources/providers and scopes in decoded requests |
| TRC-06 | SDK owns batching; no borrowed ETS data survives callback | Real SDK completion/table-lifetime/cancellation tests |
| TRC-07 | Errors, partial acceptance, limits, and drops are honest | Deterministic collector and callback/telemetry assertions |
| TRC-08 | Conversion, chunks, HTTP, and retries have one bounded budget | Slow/failed collector, retry exhaustion, oversized spans, cancellation |
| TRC-09 | Initialization, independence, restart, flush, and teardown work | Supervised lifecycle tests and observed delivery/cleanup |
| TRC-10 | Existing spans correlate with logs and preserve parentage | Instrumentation + SDK + Logger integration, context cleanup |
| TRC-11 | Three signals export with canonical exporter absent | Fresh packaged consumer and real Collector conformance |

All IDs must pass with recorded evidence before claiming the tracing feature ready.
The package replaces an OTLP/HTTP export role, not every protocol/configuration
option or the APIs of experimental logs/metrics SDKs.

## 17. Deferred scope and sources

A replacement tracing SDK, custom span/propagation API, replacement instrumentation
packages, gRPC/HTTP-JSON export, durable queues, tail sampling, metric exemplars,
cumulative metrics, and a global auto-configuration layer are outside Phases 4–7.
Consider them only through a separate scoped plan. A replacement SDK would need its
own demonstrated limitation, compatibility contract, sampling/context/lifecycle
conformance suite, and maintenance case; the trace exporter alone does not justify it.

Reference inputs (recheck versions at Phase 4; standards are not proof of a specific
SDK implementation's behavior):

- [OTel Erlang/Elixir status](https://opentelemetry.io/docs/languages/erlang/)
- [Trace exporter behaviour](https://hexdocs.pm/opentelemetry/otel_exporter_traces.html)
- [Tracing SDK specification](https://opentelemetry.io/docs/specs/otel/trace/sdk/)
- [OTLP exporter configuration](https://opentelemetry.io/docs/specs/otel/protocol/exporter/)
- Installed `opentelemetry` 1.7.0 `otel_batch_processor.erl` and
  `otel_exporter_traces.erl`, inspected September 16, 2026; Phase 4 must record
  reproducible source/version evidence and integration results.
