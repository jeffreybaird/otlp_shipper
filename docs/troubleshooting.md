# Troubleshooting

## Nothing reaches the collector

Check these in order:

1. **Startup succeeded.** Logs and metrics require a nonempty `service_name` or
   `OTEL_SERVICE_NAME`. Invalid options prevent the component from starting.
2. **The receiver accepts HTTP/protobuf.** The local default is port `4318`.
   `endpoint` must include the signal path; `base_endpoint` appends it.
3. **An event was emitted after startup.** Logs must pass Logger's primary level
   and the handler level. Metrics need the matching event and a non-nil measurement.
4. **A batch had time to flush.** Logs and metrics default to one second. A flush
   request is not a delivery receipt; inspect the collector or the events below.
5. **The collector accepted the request.** Check authentication and export/drop
   diagnostics. HTTP 200 can still report partial rejection.

Explicit options override environment variables. Restart the component after
changing configuration. See [configuration](configuration.md).

## Metrics are missing or different from expected

| Symptom | Check |
| --- | --- |
| Reporter fails with `:unsupported_metric` | Replace `summary` with `distribution` and supply buckets. |
| A counter stays empty | Emit its event with a non-nil measurement; a counter counts events, not the measurement's value. |
| A duration is much too large | Convert native durations with `unit: {:native, :millisecond}`. |
| No point during an idle interval | Expected: empty intervals emit nothing, including gauges. |
| New tag combinations disappear | Check `max_series`, `max_pending`, and drop reasons. Avoid unbounded IDs as tags. |

See [metric behavior](metrics.md) for units, tags, and interval semantics.

## Traces are missing or keep multiplying

Use SDK **1.7.0** / API **1.5.0**, start Finch before the SDK, and set
`service.instance.id` to an explicit string. The SDK's generated integer can be
too large for an OTLP attribute. A named provider does not redirect the global
tracer used by existing instrumentation.

Wrap your sampler with `OtlpShipper.TraceSampler` when HTTP instrumentation traces
export requests. Keep the SDK export timeout at least 2,000 ms above the exporter
budget. The [migration guide](migration.md) has the complete setup.

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

## Delivery limits

Queues are in memory. Overload, crashes, and exhausted retries can lose telemetry;
a lost response can cause duplicates on retry. Increasing a queue does not provide
durability. See [queue limits and retries](configuration.md#queue-and-request-limits).
