# OTLP architecture

This guide describes the implemented shared core, Logger adapter, metrics reporter,
and SDK-compatible trace exporter. Logs and metrics shipped in 0.1.0; trace export
shipped in 0.2.0. See [../PLAN.md](../PLAN.md) for the original phase contracts and
[release readiness](submission/readiness.md) for current publication status.
Confirmed: `otlp_shipper`, module root `OtlpShipper`, public Hex, Finch directly.

## One package, independent signals

The log handler and metrics reporter share the core and never depend on each other.
Keep the log handler replaceable if upstream SDK support makes it unnecessary.
The consumer chooses which components to start. Trace export integrates
with the existing OTel SDK batch processor; it does not replace that SDK or add
another shipper queue for spans.

| Component | Responsibility |
| --- | --- |
| Config | Explicit options over OTEL environment configuration; per-signal settings and endpoint rules |
| Resource | Logs/metrics service identity and attributes; require `service.name` at startup; traces preserve the SDK resource |
| Value | Shared generated-message inputs for AnyValue, KeyValue, and Resource |
| Transport | OTLP/HTTP POST, headers, gzip, timeouts, bounded retry and failure reporting |
| Buffer | Logs/metrics batching, periodic/size flush, bounded retention, shutdown flush |
| LogHandler | Logger event conversion, severity, correlation, metadata filtering and truncation |
| MetricsReporter | Telemetry.Metrics attachment, tag/unit conversion, interval aggregation |
| TraceRecord / TraceEncoder | SDK-independent conversion and generated, resource/scope-preserving request encoding |
| TraceBatch | Bounded synchronous trace requests under one conversion/HTTP/retry deadline |
| TraceExporter / TraceSDKRecord | Guarded SDK callbacks and version-specific normalization within bounded synchronous export |
| TraceSampler / TraceSuppression | Consumer-configured sampling delegation and actual HTTP-worker feedback suppression |

Separate environment reads from pure configuration resolution for deterministic
doctests. Validate the OTLP endpoint path and signal-specific precedence against the
spec when implementing; generic and signal endpoints have different path semantics.

## Dependency and packaging constraints

Vendor the needed `.proto` sources with upstream version/provenance and notices.
Generate protobuf code; never hand-write encoding. The plan prefers gpb at build time
with `runtime: false`. That flag alone does not prove generated code has no runtime
dependency: verify the generated encoders in a production consumer. Include every
input and build step needed when Hex compiles the package outside this checkout.

Keep `telemetry_metrics` and `telemetry` required, and `opentelemetry_api` optional
with guarded use. Do not load the full SDK or gRPC stack by default. Do not depend
on the canonical exporter or reuse its generated codecs. Finch is the
selected HTTP client. Keep its supervised pools isolated from host configuration.

## Resource limits and errors

Bound ingress/mailboxes as well as stored batches: truncating GenServer state does
not bound pending casts. Logs drop oldest on overflow and count losses. Cap log
bodies and attributes and report dropped attributes accurately. Define the metrics
series limit decision explicitly; tag cardinality can otherwise exhaust memory.

Transport retries 429/502/503/504 and transport errors using exponential backoff
with jitter and `Retry-After`, then drops after bounded attempts. Keep work off the caller's
logging/event path. A lost response can cause duplicate delivery; document that
boundary. Shutdown flush is bounded best effort, not durable delivery after a crash.

Emit export stop/exception and dropped telemetry events. Document
measurement units, status values, reasons, and what the counts mean. Diagnostics
use a filtered domain and rate limiting so an export failure cannot feed itself.
Exclude the reporter's own diagnostics from configurations that would recurse.

## Metrics contract

Counters become monotonic sums; sums track whether negative measurements occur;
last values become gauges; distributions use explicit histogram bounds. Refuse
summaries at initialization with a stable tagged error naming the unsupported type;
consumer-facing documentation explains using distributions instead.

Use delta aggregation with interval start/end timestamps. Transform tag values and
units before aggregation. Convert output units as specified in the plan. Emit
nothing for a series with no events. Document gauge handling separately from delta
sum/histogram temporality, and test consecutive intervals.

## Logger lifecycle

The consumer starts `OtlpShipper.LogHandler`, a rest-for-one supervisor owning Finch,
a named Buffer, and registration. Registration is last so shutdown removes ingress
before draining and buffer restarts replace the handler handle. A per-tree token
prevents registration from replacing another owner's handler. Killed registration
can reinstall its own handler; pool startup tolerates a bounded descendant teardown
race after a successful first start. Names are explicit atom options per instance.

LogRecord is the pure conversion boundary. The handler reads optional current-span
context in the logging process and rejects inherited stale process IDs after span
detach. Buffer enqueue uses ETS directly; HTTP stays in the batch worker. Diagnostics
are rate limited with shared atomics and an excluded Logger domain. HTTP implementation
logs are filtered, and a process-local ingress guard prevents synchronous telemetry
subscribers from recursively exporting their own log messages.

## Metrics lifecycle and bounds

MetricsReporter owns a rest-for-one tree: shared Pool startup, Buffer, a GenServer
Worker, and telemetry Registration. Startup shares anonymous handles through a
per-instance ETS table. Producers receive the worker's ingress handle at attach
time; they never query that table or make GenServer calls during events.

Atomic ingress credits bound pending samples. Worker state holds at most max_series
active definition/tag combinations. Each completed series becomes one buffered point;
export groups compatible points into metric messages. Snapshot clears interval state
before HTTP, while sum nonmonotonicity history remains bounded by definition count.
Timers carry incarnation tokens so an already-delivered old tick cannot create a
second interval schedule after explicit flush. Registration detaches first on
shutdown and replaces its own stable IDs after worker or registration failure.

Metric definitions reject internal exporter events, duplicate names, unsupported
units, and malformed buckets. Sampling handles keep/drop and measurement/tag
callbacks safely, with no double unit conversion. Tags retain their meaning by
rejecting excessive data instead of truncating; copied binary slices bound retained
memory. Histogram bounds are validated after double conversion as well as before
export. Numeric overflow is an observed drop, never wrapped arithmetic.

## Trace boundary

The guarded `OtlpShipper.TraceExporter` implements the SDK's exporter callbacks.
The SDK owns span lifecycle, sampling, propagation, and batching. Export runs in
the SDK worker and must finish consuming its temporary ETS table before returning.
Preserve SDK resources, original instrumentation scopes, and supported span fields;
do not stamp the logs/metrics envelope scope onto every span.

Use bounded requests and one total conversion/HTTP/retry deadline, coordinated with
SDK cancellation. Do not add a second span queue, replay accepted chunks after a
later failure, or promise that SDK flush return acknowledges delivery. Finch must
have explicit supervised ownership and cleanup independent of assumptions about
SDK shutdown callbacks. Prevent exporter HTTP instrumentation from feeding traces
back into itself. SDK queue limits and shipper request limits are separate contracts.

Phase 4 proved the compatibility contracts in the
[decision record](decisions/trace-compatibility.md). The Phase 5 core uses normalized
maps and an explicit native clock offset, with no SDK record imports. Trace-only
configuration leaves resource ownership with the caller. The batch worker constructs
one bounded request at a time and keeps coherent outcome counters in a parent-owned
ETS table. Transport commits each result there before emitting diagnostics, so a
blocked telemetry subscriber cannot erase confirmed delivery when the worker is killed.
Forced cancellation can omit final diagnostics; returned counters retain committed
outcomes. The caller supplies the source count to account for an unvisited suffix
without evaluating a blocked enumerable.

Phase 6 integrates SDK callbacks and the approved consumer-configured sampler.
The consumer owns its rest-for-one pool/provider tree; exporter initialization
validates a preexisting named pool and never mutates SDK configuration. The optional
SDK dependency supplies compilation ordering. Initialization diagnostics are bounded
to 100 ms, and the SDK callback deadline starts before normalization. Raw source
record retrieval remains part of the SDK memory boundary.
Phase 7 proves a packaged three-signal consumer with real instrumentation and the
canonical exporter absent. See PLAN.md §§12–16 for acceptance IDs.
