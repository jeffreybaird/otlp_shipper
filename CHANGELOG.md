# Changelog

## 0.2.2 — 2026-10-04

- Refresh installation and migration examples for 0.2.2 and link the public source
  repository. Remove stale unpublished-release claims from consumer documentation.
- Align API and development documentation with shipped trace support and the
  0.2.1 instrumentation scope version fix. Runtime APIs are unchanged.
- Require Mint 1.10.2 or newer within 1.x in published dependency metadata, excluding
  versions affected by CVE-2026-94194, CVE-2026-91043, and CVE-2026-92103. Existing
  consumers should update both `otlp_shipper` and `mint` in their lockfiles.

## 0.2.1 — 2026-09-30

- Derive the logs and metrics instrumentation scope version from the installed
  `otlp_shipper` OTP application metadata instead of hardcoding `0.1.0`.
  Collectors and the hub now receive the actual package version for new telemetry.
  Existing stored records are unchanged; trace scopes retain their original
  instrumentation identity.
- Validate the current package scope version in Collector conformance checks.

## 0.2.0 — 2026-09-21

- Add the optional SDK 1.7.0/API 1.5.0 trace exporter, bounded callback conversion,
  consumer-owned pool lifecycle helper, and delegating sampler wrapper. SDK/API
  and instrumentation remain consumer-owned; the package does not configure them
  globally. Trace integration is available starting with this release.
- Leave SDK runtime startup explicitly with the consumer while preserving optional
  compilation order, enabling pool-before-SDK included application startup.
- Verify real SDK export, cancellation, correlation, restart, sampling feedback,
  and actual packaged SDK-present/absent releases.

- Add the trace protocol core: vendored generated schemas, transport-only trace
  configuration, strict normalized span conversion, resource/scope-preserving
  envelopes, and bounded chunk export under one shared deadline.
- Decode trace partial responses and preserve span accounting across retries,
  failures, and deadline cancellation. Extend collector and release-consumer proof
  while retaining logs/metrics contracts and optional tracing dependencies.
- Add a fresh production release proof with existing Finch instrumentation, all
  three signals, correlated logs, and canonical exporter/runtime gpb absence.
- Extend pinned Collector conformance to SDK spans, parentage, scope/resource
  identity, event/status fields, and log correlation. Add migration and rollback
  instructions.

## 0.1.1 — 2026-09-13

- Widen the Finch requirement from `~> 0.20.0` to `~> 0.20` (`>= 0.20.0` and
  `< 1.0.0`). The previous constraint capped Finch below 0.21.0, conflicting
  with consumers already on 0.21.x; `~> 0.20` matches the documented lower
  bound and the no-behaviour-change intent.

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
lose data; retries can duplicate accepted data. Traces were outside the 0.1.0 scope
and were added in 0.2.0. Durable queues, cumulative metrics, gRPC, and custom
certificate/mTLS environment settings remain out of scope.

Elixir 1.19+ and OTP 28+ are the baseline. Breaking changes in the initial 0.x
series will increment the minor version and include migration notes.
