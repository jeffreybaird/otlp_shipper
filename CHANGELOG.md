# Changelog

## Unreleased

- Phase 0: generated OTLP protobuf, validated configuration/resources, Finch transport,
  bounded ingress, and local collector tests.
- Replace the bootstrap greeting examples with package documentation.
- Decode bounded collector responses for partial acceptance and retry the full
  OTLP HTTP retryable status set (429/502/503/504).
- Phase 1: supervised Logger handler, bounded record conversion, optional span
  correlation, automatic recovery, and rate-limited nonrecursive diagnostics.
- Guard against stale process trace IDs after span detach and Finch teardown races.
- Bound charlist traversal, support struct reports, and deduplicate report keys.
- Preserve the recorded recipe's log payload contract; exercise log delivery in a
  fresh consumer release without the optional tracing API or build-time gpb.
- Phase 2: Telemetry.Metrics counters, sums, gauges, and explicit-bound delta
  histograms with transformed tags, units, filtering, bounded ingress/series, and
  supervised handler cleanup. Summaries are rejected in favor of distributions.
- Keep histogram bounds distinct after double conversion and copy small tag
  slices to prevent large backing-binary retention.
- Share Finch pool recovery between independent log and metric pipelines; verify
  both signals in the clean consumer release.
- Real Collector conformance and release preparation remain Phase 3.
