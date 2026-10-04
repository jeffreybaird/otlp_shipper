# Send logs

Add this child to the `children` list in your application's `start/2` callback:

```elixir
{OtlpShipper.LogHandler,
 service_name: "checkout",
 endpoint: "http://localhost:4318/v1/logs"}
```

Restart the application, then log an event:

```elixir
require Logger
Logger.info("checkout complete", order_id: "example-42")
```

With a reachable OTLP/HTTP collector, the next batch contains the body
`checkout complete`, severity INFO, and an `order_id` attribute under service
`checkout`. The default flush interval is one second. A console log alone does
not confirm export; check your collector or [export diagnostics](troubleshooting.md#diagnostics).

The handler starts its own pool and buffer. You do not need a separate Finch child
or the tracing SDK. See [configuration](configuration.md) for authentication,
resources, and queue limits.

## Lifecycle and multiple instances

The handler owns its Finch pool, buffer, and Logger registration. Configure headers,
compression, resources, and limits through the [shared configuration options](configuration.md).
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

## Message bodies, attributes, and limits

Plain messages become strings; map/keyword reports become OTLP key-value bodies.
All eight Erlang Logger severity levels map to OTLP severity numbers. Logger internals such as
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

### Correlate logs with spans

With the optional `opentelemetry_api`, logs inside a current span carry its 16-byte
trace ID, 8-byte span ID, and sampled flag. The SDK is optional and only required for SDK trace export.
A valid explicit `otel_trace_id` / `otel_span_id` pair on the event takes precedence;
raw bytes, fixed-width hex, and positive integers are accepted. IDs never become
ordinary attributes. Without tracing or valid metadata, IDs are empty.

API 1.5 can leave stale Logger process IDs after detaching a span. With the API
installed, inherited process IDs without an active span are ignored. For forwarded
logs without a current span, supply a distinct pair directly on the log event.
No tracing or Logger process configuration is changed by this handler.

## If logs are missing

Check both Logger's primary level and the handler's `level` (default `:info`).
Then check the collector URL and [troubleshooting](troubleshooting.md).
