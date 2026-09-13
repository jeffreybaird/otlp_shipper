# Changelog

## Unreleased

## 0.1.0 — 2026-09-13

Initial public Hex release.

- Supervised Logger handler with bounded buffering, structured OTLP bodies,
  severity and metadata conversion, optional span correlation, UTF-8 truncation,
  automatic registration recovery, and rate-limited diagnostics.
- Telemetry.Metrics counters, sums, gauges, and explicit-bound delta histograms,
  with converted units, transformed tags, filters, bounded ingress and series,
  interval reset, and final shutdown snapshots. Summaries are rejected.
- Shared Finch OTLP/HTTP transport with gzip, bounded deadlines and retries,
  Retry-After handling, partial-response decoding, and export/drop telemetry.
  Empty partial-success messages are treated as full success, matching real
  Collector responses and the OTLP schema.
- Namespaced protobuf generated from vendored OTLP v1.5.0 schemas. No full SDK,
  gRPC stack, or runtime gpb requirement; tracing API is optional.
- Opt-in Docker conformance against pinned OpenTelemetry Collector 0.160.0,
  checking decoded logs and all four metric types. Default tests remain local.
- Production consumer release checks with current and minimum dependency
  resolution, including optional tracing absence/presence. gpb requires 4.21.7
  or newer within 4.x because 4.21.0 fails to compile on OTP 29.

Delivery is best effort and in memory. Crashes, overload, and exhausted retries
lose data; retries can duplicate accepted data. Traces, durable queues, cumulative
metrics, gRPC, and custom certificate/mTLS environment settings are out of scope.

Elixir 1.19+ and OTP 28+ are the baseline. Breaking changes in the initial 0.x
series will increment the minor version and include migration notes.
