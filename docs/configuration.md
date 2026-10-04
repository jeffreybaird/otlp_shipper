# Configure export

Pass options to `OtlpShipper.LogHandler` or `OtlpShipper.MetricsReporter` in your
supervision tree. For example, a log handler with gzip:

```elixir
{OtlpShipper.LogHandler,
 service_name: "checkout",
 base_endpoint: "http://localhost:4318",
 compression: :gzip}
```

`base_endpoint` appends the signal path. `endpoint` is the complete URL, including
`/v1/logs`, `/v1/metrics`, or `/v1/traces`; no path is appended to it.

To configure logs and metrics through the environment, omit their explicit service
and endpoint options and set:

```sh
export OTEL_SERVICE_NAME=checkout
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

Supply authentication through runtime options (`headers: [{"authorization", token}]`)
or the OTEL header variables below. Obtain `token` from your runtime secret source;
never put credentials in source or endpoint URLs.

## Options and environment precedence

Explicit options take precedence over signal-specific OTEL variables, which take
precedence over generic variables. Empty environment settings are treated as unset.
`OtlpShipper.Config.new/3` accepts an explicit environment map for deterministic resolution;
`OtlpShipper.Config.load/2` reads environment once at startup. Restart to change configuration.

For logs, signal variables start with `OTEL_EXPORTER_OTLP_LOGS_`; for metrics,
`OTEL_EXPORTER_OTLP_METRICS_`. Generic variables start with `OTEL_EXPORTER_OTLP_`.
Append the uppercase suffix shown below (for example, `OTEL_EXPORTER_OTLP_METRICS_HEADERS`).

| Option | OTEL variable suffix / source | Default |
| --- | --- | --- |
| `endpoint` | Signal-specific `ENDPOINT` | Local base URL plus signal path |
| `base_endpoint` | `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318`, appending `/v1/logs` or `/v1/metrics` |
| `headers` | Signal-specific then generic `HEADERS` | Empty; percent-encoded `key=value` pairs in environment |
| `compression` | Signal-specific then generic `COMPRESSION` | `:none`; `:gzip` supported |
| `timeout` | Signal-specific then generic `TIMEOUT` | 10,000 ms total per export including retries |
| `resource` | `OTEL_RESOURCE_ATTRIBUTES` | Map of extra attributes |
| `service_name` | `OTEL_SERVICE_NAME`, then resource attributes | Required, nonempty string |
| `service_version`, `service_instance_id` | Resource attributes | Unset |

## Protocol and credentials

Only `http/protobuf` is supported; an explicitly configured different OTEL protocol
is rejected. Credentials belong in runtime options/environment; no endpoint userinfo
or redirects. Reserved transport headers cannot be overridden. TLS uses Finch/Mint
verification defaults. Custom certificate/mTLS environment settings are not yet
implemented; no full SDK configuration compatibility is claimed.

## Queue and request limits

These queue and flush settings apply to logs and metrics. Traces use the SDK queue;
see [trace setup](migration.md) for its timeout and ownership requirements.

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

## Retries and delivery

Retries cover 429/502/503/504 and transport errors. `Retry-After` is honored; if its
wait exceeds the export deadline, the batch is dropped instead of retried early.
Permanent errors, redirects, and partial acceptance are not retried. A lost response
can cause duplicate delivery. An HTTP 200 with partial rejection is reported as
`{:ok, :partial, rejected_count}`, with rejected records counted as dropped.

## Trace configuration

Pass transport options alongside `pool` in the SDK exporter configuration.
Trace-specific environment variables use `OTEL_EXPORTER_OTLP_TRACES_` followed by
`ENDPOINT`, `HEADERS`, `COMPRESSION`, `TIMEOUT`, or `PROTOCOL`. The generic fallback
uses `OTEL_EXPORTER_OTLP_` with the same suffixes. The default trace URL is
`http://localhost:4318/v1/traces`.

Trace resource identity comes from the SDK. Do not pass `service_name`, `resource`,
`max_queue`, `flush_ms`, or `shutdown_ms` to the trace exporter. Follow the
[migration guide](migration.md) for startup order, sampling, and SDK timeouts.
