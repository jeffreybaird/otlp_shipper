# Send metrics

Add a reporter to the `children` list in your application's `start/2` callback:

```elixir
{OtlpShipper.MetricsReporter,
 service_name: "checkout",
 endpoint: "http://localhost:4318/v1/metrics",
 metrics: [
   Telemetry.Metrics.counter("checkout.request.count"),
   Telemetry.Metrics.distribution("checkout.request.duration",
     unit: :millisecond,
     reporter_options: [buckets: [5, 25, 100, 500]]
   )
 ]}
```

Restart the application and emit one event:

```elixir
:telemetry.execute([:checkout, :request], %{count: 1, duration: 42}, %{})
```

The last segment of each metric name selects the measurement; the preceding
segments select the event. Here, both metrics listen to `[:checkout, :request]`.
The duration is already in milliseconds.

After the next aggregation interval (one second by default), your collector should
receive a delta counter of `1` and a histogram with one `42 ms` observation in the
bucket ending at `100 ms`. Empty intervals emit nothing. If your event reports
native time units, use `unit: {:native, :millisecond}` instead.

The reporter owns its Finch pool and buffer. It can run independently of logs and
tracing. See [configuration](configuration.md) for endpoints and authentication.

## Choose a metric type

| Definition | OTLP result | Behavior |
| --- | --- | --- |
| `counter` | Monotonic delta Sum | One per accepted event; measurement must be non-nil |
| `sum` | Delta Sum | Sum of measurements; becomes nonmonotonic after an accepted negative value and stays so until restart |
| `last_value` | Gauge | Last observed value and observation timestamp in the interval |
| `distribution` | Delta Histogram | Explicit inclusive upper bounds, plus implicit positive infinity |
| `summary` | Startup error | `{:error, :unsupported_metric, :use_distribution}`; use `distribution` |

### Histogram buckets

Histogram `reporter_options[:buckets]` is required, in the converted output unit.
An empty list gives a single catch-all bucket. Up to 256 finite, strictly increasing
bounds are allowed; bounds must remain distinct as protobuf doubles. Histograms
include count, bucket counts, min, and max. Sum is omitted for an interval containing
negative observations, as required by the vendored OTLP schema.

### Names, units, and callbacks

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

## Tags and series limits

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

## Flushing and delivery

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

Completed points use the [shared queue limits](configuration.md#queue-and-request-limits): `max_queue` counts queued
points, `max_batch` limits points per export, and overflow drops oldest queued points.
Retention consists of bounded ingress, active series, queued points, and one in-flight
batch. Shutdown detaches handlers, takes a final snapshot, and drains export with
bounded waits. Crashes and restart gaps can lose observations or points. Registration,
aggregation, and buffer restart together as needed; each instance detaches only its
own handlers. Logs and metrics share pool startup code but do not depend on each other.

## Avoid feedback loops

Do not define metrics on `[:otlp_shipper, ...]` events; startup rejects them to avoid
feedback. Exporter-owned HTTP work and synchronous callback feedback are excluded.
Keep telemetry subscribers fast and avoid asynchronous self-reporting loops.
