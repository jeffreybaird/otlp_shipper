# Changelog

## Unreleased

- Phase 0: generated OTLP protobuf, validated configuration/resources, Finch transport,
  bounded ingress, and local collector tests.
- Replace the bootstrap greeting examples with package documentation.
- Decode bounded collector responses for partial acceptance and retry the full
  OTLP HTTP retryable status set (429/502/503/504).
- Logger handler and metrics reporter are planned for subsequent phases.
