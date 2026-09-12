# Hex release readiness

Status: **Phase 3 implementation and local preparation complete; publication pending**.
This is a 0.1.0 candidate, not a published release. See [candidate.md](candidate.md)
for the exact reviewed source/archive and check results.

## Prepared

- MIT license, package metadata, README quickstarts for each component, configuration
  and telemetry tables, API documentation, and initial release notes.
- Bounded Logger and Telemetry.Metrics implementations, generated protobuf, and
  deterministic HTTP/process/regression coverage.
- Opt-in `mix otlp_shipper.conformance`: real Collector 0.160.0 parses synthetic
  gzip logs and all four metric types and exposes the expected decoded values.
- Formatting, compilation with warnings as errors, ExUnit/doctests, Dialyzer,
  ExDoc, and Hex retirement audit. Retirement audit is not a vulnerability scan.
- Fresh production release delivery with no runtime gpb, with optional tracing
  absent, and at declared dependency lower bounds with API 1.3.0 present.
- CI on the pinned Elixir 1.19.5 / OTP 28.5.0.2 pair plus minimum Elixir 1.19.0 /
  OTP 28.0. Consult the candidate's exact CI result before publishing.
- Deliberate archive file list, vendored protocol provenance/license, and local
  source/archive inspection. Follow [build.md](build.md) to reproduce.

## Before publication

1. Obtain explicit release authorization and finish the Phase 3 review/merge.
2. Confirm the publishing account and name ownership/availability. The public
   [Hex package API](https://hex.pm/api/packages/otlp_shipper) returned 404 on
   September 12, 2026. That is a read-only availability observation, not a name
   reservation or proof of permission to publish.
3. Resolve public source/support access. GitHub currently reports this repository
   as **private**. The configured source links will not work for public consumers.
   Making the repository public is a separate owner action.
4. Recheck [upstream experimental releases](https://hex.pm/packages/opentelemetry_experimental)
   before publishing. The API still reported 0.5.1 on September 12, 2026; no newer
   released replacement was available for reassessment. Do not generalize the
   Phase 1 findings to all development snapshots.
5. Rebuild from the approved release revision and repeat checks if packaged contents
   changed. Record the new archive checksum and source revision; do not assume a
   merge commit creates the identical candidate without comparing it.
6. Follow the publisher's normal authentication flow, publish only the reviewed
   package/docs, and verify a fresh consumer fetching the exact public Hex version.

No Hex credential changes, publication, source visibility changes, release tags,
or GitHub release uploads are part of this preparation. Known behavior limits and
compatibility caveats are documented in the README and candidate evidence.
