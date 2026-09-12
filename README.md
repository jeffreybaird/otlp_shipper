# otlp_shipper

An Elixir package for bounded OTLP/HTTP log shipping and `Telemetry.Metrics`
reporting. Finch provides HTTP connection pooling; the package owns buffering,
retry deadlines, and drop reporting. No full OpenTelemetry SDK is required.

**Status: Phase 0 core only.** The Logger handler and metrics reporter are not
implemented yet. This repository has not been published to Hex. Public Hex and MIT
are the intended distribution; the source repository is currently private.

## Shared core

- `OtlpShipper.Config`: validated options and OTEL environment precedence.
- `OtlpShipper.Resource` / `Value`: service identity and typed OTLP attributes.
- `OtlpShipper.Encoder`: generated protobuf envelopes for logs and metrics.
- `OtlpShipper.Transport`: Finch POST, gzip, bounded retries, partial-response handling.
- `OtlpShipper.Buffer`: fixed-capacity ingress and one supervised batch worker.

The core accepts OTLP message maps. It does not yet convert Logger events or
aggregate metric definitions. Logs and metrics will use the same core independently.
Trace export is outside this package's scope.

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
`:shutdown`. `count` on export is the attempted record/data-point count supplied to
transport. One stop event is emitted per logical export, not per HTTP retry. Callback
crashes/timeouts are reported by the buffer as drops. Custom export callbacks own
their ordinary failure diagnostics; `Transport.export/4` handles these for HTTP.
Never report these events back through the same exporter recursively. Response
bodies and credentials are not included in diagnostics.

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
collector or production credentials. Real OTel Collector conformance is Phase 3.
CI uses `.tool-versions`; local verification must report any different toolchain.

OTLP schema sources are vendored from `opentelemetry-proto` v1.5.0 with their
Apache-2.0 license and provenance in `priv/proto/`. gpb generates namespaced modules
at build time and is not a runtime application. Collector response decoding is
included to detect partial rejection; production does not ingest encoded telemetry.

Repository development and release guidance lives under `docs/`.
Building a package does not publish it. First release remains blocked on the
remaining phases and release verification.
