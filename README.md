# otlp_shipper

An Elixir package for bounded OTLP/HTTP log shipping and `Telemetry.Metrics`
reporting. Finch provides HTTP connection pooling; the package owns buffering,
retry deadlines, and drop reporting. No full OpenTelemetry SDK is required.

**[0.1.1 is available on Hex](https://hex.pm/packages/otlp_shipper/0.1.1).**
[API documentation](https://hexdocs.pm/otlp_shipper/0.1.1/) is public. The GitHub
source repository is currently private.

## Metrics setup

Add a reporter to your application's supervision tree:

```elixir
import Telemetry.Metrics
metrics = [
  counter("checkout.request.count"),
  distribution("checkout.request.duration",
    unit: {:native, :millisecond}, reporter_options: [buckets: [5, 25, 100, 500]])
]
children = [{OtlpShipper.MetricsReporter, metrics: metrics, service_name: "checkout"}]
Supervisor.start_link(children, strategy: :one_for_one)
```

This listens to `[:checkout, :request]` events with `:count` and/or `:duration`
measurements. The default collector URL is `http://localhost:4318/v1/metrics`;
set `endpoint`, `base_endpoint`, or the OTEL variables below for another collector.
A reporter can run alongside the Logger handler or independently. Metrics definitions
and configuration are validated before processes or telemetry handlers start.

## Logger setup

Add the handler to your application's supervision tree:

```elixir
children = [
  {OtlpShipper.LogHandler,
   service_name: "checkout",
   endpoint: "http://localhost:4318/v1/logs"}
]

Supervisor.start_link(children, strategy: :one_for_one)
# Ordinary Logger calls now enter the bounded export queue.
require Logger
Logger.info("checkout complete", order_id: "example-42")
```

## Installation and compatibility

Add the package to your `mix.exs` dependencies:

```elixir
{:otlp_shipper, "~> 0.1.1"}
```

Run `mix deps.get`. The snippets above show standalone trees; in an application,
add each child to your existing supervisor instead of starting an extra root.

Elixir 1.19+ and OTP 28+ are the supported baseline. CI checks Elixir 1.19.0 / OTP
28.0 and the pinned Elixir 1.19.5 / OTP 28.5.0.2 pair; local release checks also use
Elixir 1.19.5 / OTP 29.0.1. The declared Elixir requirement permits future 1.x
versions, but those are not pre-certified.

Version 0.1.1 widens Finch from `~> 0.20.0` to `~> 0.20`, allowing versions
`>= 0.20.0` and `< 1.0.0`, including 0.21.x. No runtime behavior changed.

Dependency lower bounds are Finch 0.20.0, telemetry 1.3.0, telemetry_metrics 1.1.0,
gpb 4.21.7, and optional opentelemetry_api 1.3.0. Fresh production consumers exercise
these bounds with and without tracing. gpb 4.21.0 cannot compile on OTP 29 and is
excluded. Optional API 1.3.0 works in the no-active-span smoke but emits an upstream
`link/2` warning on OTP 29; prefer API 1.5.0 there. SDK span integration is tested
with API 1.5.0 / SDK 1.7.0. gpb is a build dependency, absent at release runtime.

## Metric behavior

| Definition | OTLP result | Behavior |
| --- | --- | --- |
| `counter` | Monotonic delta Sum | One per accepted event; measurement must be non-nil |
| `sum` | Delta Sum | Sum of measurements; becomes nonmonotonic after an accepted negative value and stays so until restart |
| `last_value` | Gauge | Last observed value and observation timestamp in the interval |
| `distribution` | Delta Histogram | Explicit inclusive upper bounds, plus implicit positive infinity |
| `summary` | Startup error | `{:error, :unsupported_metric, :use_distribution}`; use `distribution` |

Histogram `reporter_options[:buckets]` is required, in the converted output unit.
An empty list gives a single catch-all bucket. Up to 256 finite, strictly increasing
bounds are allowed; bounds must remain distinct as protobuf doubles. Histograms
include count, bucket counts, min, and max. Sum is omitted for an interval containing
negative observations, as required by the vendored OTLP schema.

Metric names join Telemetry.Metrics name segments with dots. Duplicate output names
are rejected, even for different types. Descriptions are preserved. Supported units
are `:unit` → `1`, seconds → `s`, milliseconds → `ms`, microseconds → `us`, nanoseconds
→ `ns`, bytes → `By`, kilobytes → `kBy`, megabytes → `MBy`, and percent → `%` (use
singular atoms such as `:second` and `:byte`). Convert `:native` explicitly, for example
`unit: {:native, :millisecond}`. Telemetry.Metrics wraps the measurement function with
the conversion; this reporter executes it once. Unsupported units/options fail startup.

Keep/drop predicates run before measurement and tag transformation. Measurement
functions with one or two arguments, `tag_values`, and function-valued `tags` are
supported. Missing measurements and filtered events are skipped. Invalid values or
callback failures emit a drop count without detaching event handlers. Numeric values
must fit signed 64-bit integers or finite doubles; arithmetic overflow drops the
observation while preserving the previous aggregate. Counter values are ignored
apart from the non-nil requirement.

Selected tags become typed attributes and identify a series. Missing selected tags
are omitted. Tag keys must be strings or atoms; values must be scalar strings, atoms,
booleans, or valid numbers. Tags are never truncated: truncation could merge unrelated
series. Values with invalid UTF-8, nested containers, more than 32 keys, or excessive
size are rejected. Small binary slices are copied to avoid retaining large source data.

| Reporter option | Default / meaning |
| --- | --- |
| `flush_ms` | 1,000 ms aggregation interval |
| `max_series` | 1,000 active series across all definitions per interval |
| `max_pending` | 2,048 pending observations across all definitions |
| `max_tag_bytes` | 4,096 bytes, measured as the selected tag map's Erlang external size |
| `finch_name` | `OtlpShipper.MetricsReporter.Finch`; use distinct atom constants for independent instances |
| `name` | Optional supervisor name |

The first series admitted in an interval retain their slots. At `max_series`, new
series are dropped and counted; existing series continue updating. Every snapshot
clears active series, including gauges. Empty intervals emit nothing. Sum monotonicity
history is retained by definition, not by individual tag set. Avoid user IDs, request
IDs, and other unbounded tag values even with these caps: they make exported metrics
expensive and can starve useful series.

The GenServer serializes aggregation in receipt order. Producers reserve a bounded
ingress slot before sending a sample; a full ingress queue drops the new observation.
No HTTP or synchronous server call runs in the telemetry producer. User measurement,
filter, and tag functions still execute there and must stay fast.

`OtlpShipper.MetricsReporter.flush(reporter)` closes the current interval and returns
once its points are queued, not delivered. Events already emitted by that calling
process are included; concurrent producers may enter either interval. Sums/histograms
carry contiguous interval timestamps. Gauge timestamps are their observation times.
An interval begins anew even if export later fails; failed data is never carried into
a later delta. Retry can duplicate remotely accepted data.

Completed points use the shared Buffer limits below: `max_queue` counts queued
points, `max_batch` limits points per export, and overflow drops oldest queued points.
Retention consists of bounded ingress, active series, queued points, and one in-flight
batch. Shutdown detaches handlers, takes a final snapshot, and drains export with
bounded waits. Crashes and restart gaps can lose observations or points. Registration,
aggregation, and buffer restart together as needed; each instance detaches only its
own handlers. Logs and metrics share pool startup code but do not depend on each other.

Do not define metrics on `[:otlp_shipper, ...]` events; startup rejects them to avoid
feedback. Exporter-owned HTTP work and synchronous callback feedback are excluded.
Keep telemetry subscribers fast and avoid asynchronous self-reporting loops.

## Logger lifecycle

The handler owns its Finch pool, buffer, and Logger registration. Configure headers,
compression, resources, and limits through the same child options listed below.
`OTEL_SERVICE_NAME` and OTEL endpoint variables can replace explicit service/endpoint
options. Missing `service.name` or invalid configuration prevents startup with a
tagged error. This package does not change the application's primary Logger level.

The default handler ID is `:otlp_shipper`; default process names are
`OtlpShipper.LogHandler.Finch` and `OtlpShipper.LogHandler.Buffer`. For multiple
instances, supply distinct atom constants as `:handler_id`, `:finch_name`, and
`:buffer_name`. An optional `:name` registers the supervisor. Do not install this
handler through `:logger.add_handler/3` directly; startup owns registration.

A buffer/pool restart refreshes the handler's producer handle. Pool restart allows
up to one second for old named descendants to finish shutting down. Shutdown
removes the handler first, then drains the queue within `shutdown_ms`. Crashes and
restart gaps can lose logs; this is not a durable audit-log sink. An operator removing
the Logger handler intentionally disables export until the component restarts.

## Log conversion and correlation

Plain messages become strings; map/keyword reports become OTLP key-value bodies.
The recipe's eight Erlang severity mappings are preserved. Logger internals such as
PID, source location, domain, and report callbacks are omitted from attributes.
Remaining metadata becomes typed attributes. Report callbacks are not executed.

| Logger option | Default / behavior |
| --- | --- |
| `level` | `:info`; Logger's primary level also applies |
| `max_body_bytes` | 16,384 encoded AnyValue bytes |
| `max_attribute_bytes` | 1,024 encoded AnyValue bytes per value; separate key byte limit |
| `max_attributes` | 64; zero excludes and counts all eligible attributes |
| `diagnostic_interval_ms` | 60,000; first failure and at most one warning per interval |

Byte limits must be at least 32. Strings truncate at UTF-8 boundaries. Nested
containers stop at the byte budget, 64 entries per container, or depth eight;
charlist traversal has a bounded step budget. Normalized duplicate keys retain the
first entry. Oversized keys and excess/colliding attributes increment
`dropped_attributes_count`; value truncation and deliberately excluded Logger
internals do not. Body truncation has no OTLP dropped-attributes counter. Total
record/request limits still apply, so records or batches can be dropped even after
individual values fit. These limits are not secret redaction: filter sensitive data
before logging it.

With the optional `opentelemetry_api`, logs inside a current span carry its 16-byte
trace ID, 8-byte span ID, and sampled flag. The full SDK is only a test dependency.
A valid explicit `otel_trace_id` / `otel_span_id` pair on the event takes precedence;
raw bytes, fixed-width hex, and positive integers are accepted. IDs never become
ordinary attributes. Without tracing or valid metadata, IDs are empty.

API 1.5 can leave stale Logger process IDs after detaching a span. With the API
installed, inherited process IDs without an active span are ignored. For forwarded
logs without a current span, supply a distinct pair directly on the log event.
No tracing or Logger process configuration is changed by this handler.

## When to use another exporter

For version 0.1.1, use the OpenTelemetry SDK/exporter for traces. Unsupported metric
types and units are rejected at startup. Before adopting the logs handler, compare
[`opentelemetry_experimental`](https://hex.pm/packages/opentelemetry_experimental)
with this package's Logger integration and delivery contracts; avoid exporting each
event through both. The September 12, 2026 release-preparation recheck still found 0.5.1, the
release assessed during Phase 1. Recheck before adopting or publishing; this
package does not claim that every newer upstream development snapshot is broken.
Do not use this package when durable or exactly-once log delivery is required.

## Shared core

- `OtlpShipper.Config`: validated options and OTEL environment precedence.
- `OtlpShipper.Resource` / `Value`: service identity and typed OTLP attributes.
- `OtlpShipper.Encoder`: generated protobuf envelopes for logs and metrics.
- `OtlpShipper.Transport`: Finch POST, gzip, bounded retries, partial-response handling.
- `OtlpShipper.Buffer`: fixed-capacity ingress and one supervised batch worker.

The core accepts OTLP message maps. `OtlpShipper.LogHandler` converts Logger events;
`OtlpShipper.MetricsReporter` aggregates metric definitions. Both signals use the core independently.
Version 0.1.1 does not export traces. An SDK-compatible trace exporter is planned
in the repository's `PLAN.md`; it is not yet implemented. The planned adapter keeps
the existing tracing API, SDK, and instrumentation.

## Core example

Start a dedicated Finch pool and buffer under your application's supervisor. This
example sends prepared OTLP log records; it does not install a Logger handler.

```elixir
{:ok, config} = OtlpShipper.Config.load(:logs,
  service_name: "checkout",
  endpoint: "http://localhost:4318/v1/logs"
)

export = fn records ->
  with {:ok, body} <- OtlpShipper.Encoder.encode(:logs, records, config.resource) do
    OtlpShipper.Transport.export(config, Checkout.OtlpFinch, body, length(records))
  end
end

children = [
  {Finch, name: Checkout.OtlpFinch, pools: %{default: [size: 1, count: 1]}},
  {OtlpShipper.Buffer, name: Checkout.OtlpBuffer, config: config, export: export}
]

# Add children to your application's supervision tree, in this order.
# Once started, obtain a handle for this buffer incarnation:
handle = OtlpShipper.Buffer.handle(Checkout.OtlpBuffer)
OtlpShipper.Buffer.enqueue(handle, %{body: OtlpShipper.Value.encode("ready")})
OtlpShipper.Buffer.flush(handle)
```

`enqueue/2` success means queued, not delivered. Acquire a new handle if the buffer
restarts. `flush/1` requests work asynchronously. Retention is in memory only.
Do not invoke `Transport.export/4` from a Logger or telemetry event callback.

## Configuration

Explicit options take precedence over signal-specific OTEL variables, which take
precedence over generic variables. Empty environment settings are treated as unset.
`OtlpShipper.Config.new/3` accepts an explicit environment map for deterministic resolution;
`OtlpShipper.Config.load/2` reads environment once at startup. Restart to change configuration.

| Option | OTEL variable suffix / source | Default |
| --- | --- | --- |
| `endpoint` | `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` / `METRICS_ENDPOINT` | Exact signal URL |
| `base_endpoint` | `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318`, appending `/v1/logs` or `/v1/metrics` |
| `headers` | Signal-specific then generic `HEADERS` | Empty; percent-encoded `key=value` pairs in environment |
| `compression` | Signal-specific then generic `COMPRESSION` | `:none`; `:gzip` supported |
| `timeout` | Signal-specific then generic `TIMEOUT` | 10,000 ms total per export including retries |
| `resource` | `OTEL_RESOURCE_ATTRIBUTES` | Map of extra attributes |
| `service_name` | `OTEL_SERVICE_NAME`, then resource attributes | Required, nonempty string |
| `service_version`, `service_instance_id` | Resource attributes | Unset |

Only `http/protobuf` is supported; an explicitly configured different OTEL protocol
is rejected. Credentials belong in runtime options/environment; no endpoint userinfo
or redirects. Reserved transport headers cannot be overridden. TLS uses Finch/Mint
verification defaults. Custom certificate/mTLS environment settings are not yet
implemented; no full SDK configuration compatibility is claimed.

| Limit | Default |
| --- | --- |
| `max_retries` | 3 retries after the initial attempt |
| `retry_base_ms`, `retry_max_ms` | 200 / 5,000 ms jittered exponential backoff |
| `max_response_bytes` | 65,536 bytes |
| `max_queue`, `max_batch` | 2,048 queued items / 512 items per batch |
| `max_item_bytes`, `max_batch_bytes` | 65,536 / 1,048,576 bytes |
| `flush_ms`, `shutdown_ms` | 1,000 / 5,000 ms |

Ingress measures item size with Erlang external size; transport separately checks
encoded request bytes before gzip. Envelope overhead can make an otherwise permitted
batch exceed the wire limit; such a batch is dropped with an error. One in-flight
batch exists in addition to the bounded queue. Overflow replaces old queued items.
Shutdown flush is best effort within a deadline; crashes can lose queued data.

Retries cover 429/502/503/504 and transport errors. `Retry-After` is honored; if its
wait exceeds the export deadline, the batch is dropped instead of retried early.
Permanent errors, redirects, and partial acceptance are not retried. A lost response
can cause duplicate delivery. An HTTP 200 with partial rejection is reported as
`{:ok, :partial, rejected_count}`, with rejected records counted as dropped.

## Diagnostics

| Event | Measurements | Metadata |
| --- | --- | --- |
| `[:otlp_shipper, :export, :stop]` | `count`, `duration` (ms), `byte_size` (before gzip) | `signal`, `status` (`:ok`, `:partial`, `:error`) |
| `[:otlp_shipper, :export, :exception]` | `count` | `signal`, `status`, bounded `reason` atom |
| `[:otlp_shipper, :dropped]` | `count` | `signal`, `reason` |

Drop reasons include `:queue_full`, `:export_failed`, `:item_too_large`, and
`:shutdown`, `:invalid_log_event`, and `:unavailable`. Metrics also report
`:series_limit`, `:invalid_measurement`, `:invalid_tags`, `:invalid_keep_result`,
`:callback_failed`, and `:numeric_overflow`. Metrics ingress/aggregation drops count
observations; queued/exported drops count data points. `count` on export is the attempted record/data-point count supplied to
transport. One stop event is emitted per logical export, not per HTTP retry. Callback
crashes/timeouts are reported by the buffer as drops. Custom export callbacks own
their ordinary failure diagnostics; `Transport.export/4` handles these for HTTP.
Never report these events back through the same exporter recursively. Response
bodies and credentials are not included in diagnostics.

The Logger adapter emits rate-limited warnings through domain `[:otlp_shipper]`.
It excludes this domain, its own implementation, and Finch/Mint/NimblePool internal
logs from export. Synchronous telemetry subscribers that log during ingress cannot
re-enter the handler. HTTP work runs with the excluded domain too. Other Logger
handlers still receive diagnostics. Subscriber code must not create asynchronous
feedback loops or perform slow work in a logging callback.

## Development

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix dialyzer
mix hex.audit
mix docs --warnings-as-errors
scripts/package_smoke.sh
```

Tests use a loopback Bandit collector and generated decoders, with no external
collector or production credentials. Run real Collector conformance separately with
a local Docker engine (not a remote Docker context):

```sh
docker pull otel/opentelemetry-collector@sha256:e495787f07dbe432ce763ebaf5bc3d113850e9eee2250ade7a3da6a882d0d69a
mix otlp_shipper.conformance
```

This pins official Collector **0.160.0**. The task uses an ephemeral loopback port,
a read-only configuration mount, and synthetic gzip logs and metrics from a separate
VM with inherited `OTEL_*` variables removed. It checks the detailed debug exporter's
log body, severity, attributes, metric types, delta temporality, values, and histogram
buckets. No credentials or backend account are needed. Docker commands have 30-second
deadlines; readiness/output checks allow 60 polls. Its own container is removed on
success or failure. If the VM is killed, remove the printed container name manually.
A missing image, stopped engine, or blocked bind mount causes the task to fail;
check Docker and the pull command first. Default tests and CI do not invoke Docker.
CI uses `.tool-versions`; local verification must report any different toolchain.

OTLP schema sources are vendored from `opentelemetry-proto` v1.5.0 with their
Apache-2.0 license and provenance in `priv/proto/`. gpb generates namespaced modules
at build time and is not a runtime application. Collector response decoding is
included to detect partial rejection; production does not ingest encoded telemetry.

Repository development and release guidance lives under `docs/`.
Version 0.1.1 was published on September 13, 2026. See
`docs/submission/release-0.1.1.md` for published-artifact verification and
`docs/submission/readiness.md` for future release guidance. Building a package
does not publish it; further uploads require release authorization.
