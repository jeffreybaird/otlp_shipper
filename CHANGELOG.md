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
- Metrics aggregation remains Phase 2; real Collector conformance remains Phase 3.
