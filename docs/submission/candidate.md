# 0.1.0 candidate evidence

Preparation date: September 12, 2026. This is local release preparation, not a
published version. Publication prerequisites are in [readiness.md](readiness.md).

## Identified artifact

- Packaged source revision: `7d520261729d9eebe5990b25d1687ed0fbb421b6`.
- Version: `0.1.0`; MIT; Mix package with five declared dependencies, tracing API
  optional and gpb build-time only.
- Local artifact: `/tmp/otlp_shipper-0.1.0-phase3.tar` (temporary, not uploaded).
- Archive SHA-256:
  `e761db3a774e28cd8a3cb2c8524416f4e1cff1cafee63277b09890b68229d325`.
- Archive inspection: 36 source files, including the protobuf compiler, schemas
  and their Apache-2.0 license/provenance, conformance task/config/emitter, README,
  MIT license, and changelog. No tests, development scripts, agent instructions,
  repository docs, CI files, build output, or credentials are included.

Subsequent edits confined to repository `docs/` do not enter this archive. Rebuild
and compare checksums after merge or any source change before publication.

## Executed checks

Local toolchain: Elixir 1.19.5 / OTP 29.0.1, macOS arm64.

| Check | Result |
| --- | --- |
| Formatter and warnings-as-errors compilation | Passed |
| ExUnit | 91 tests and 19 doctests passed |
| Dialyzer | Passed, zero errors |
| ExDoc with warnings as errors | Passed; README quickstarts and module navigation inspected |
| Local Markdown links and whitespace | Passed |
| Hex retirement audit | Passed; not a comprehensive vulnerability scan |
| Real Collector 0.160.0 | Passed gzip logs, counter 3, sum 21, gauge 12, histogram `[1, 1, 1]` at `[5, 10]` |
| Fresh resolved-dependency production release | Passed loopback logs/metrics; tracing API and runtime gpb absent |
| Minimum dependencies without tracing | Passed loopback logs/metrics; runtime gpb absent |
| Minimum dependencies with API 1.3.0 | Passed loopback logs/metrics; API present, no active span; runtime gpb absent |
| Hex archive and metadata inspection | Passed |
| `mix hex.publish --dry-run --yes` | Stopped at publisher authentication; no upload performed |

Collector image: `otel/opentelemetry-collector@sha256:e495787f07dbe432ce763ebaf5bc3d113850e9eee2250ade7a3da6a882d0d69a`.
The task removed its containers; no conformance container remained after checks.
The separate fixture VM removes inherited OTEL settings and starts only the library.

CI is attached to [Phase 3 PR #4](https://github.com/jeffreybaird/otlp_shipper/pull/4/checks).
Require successful checks on the final PR head before merging/releasing: the pinned
Elixir 1.19.5 / OTP 28.5.0.2 job runs the complete gate, and the Elixir 1.19.0 /
OTP 28.0 job runs the suite and both minimum-dependency production consumers.
Local success is not a substitute for those exact-head results.

## Findings and limits

The Collector exposed empty partial-success responses being misclassified. A
failing regression preceded the fix; both signals now treat zero rejected items
and an empty warning as full success. Warning-only responses remain partial.

Minimum gpb 4.21.0 failed to compile on OTP 29 with `syntax error before: 'else'`.
The minimum is now 4.21.7. Minimum API 1.3.0 emits an upstream `link/2` warning on
OTP 29 despite passing the consumer smoke; prefer API 1.5.0 there. Active-span
integration uses the locked API 1.5.0 / SDK 1.7.0 pair, not API 1.3.0.

Hex's installed dry-run task still requires an authenticated publisher and stopped
with `No authenticated user found. Run mix hex.user auth`. Authentication was not
attempted. Package building, inspection, documentation, and consumer validation were
completed independently; the publish dry run is not reported as passing.

The public package API returned 404 for `otlp_shipper`; ownership is unverified.
GitHub still reports the source repository as private. Upstream experimental's
latest released version remained 0.5.1. These are September 12 observations, not
name reservations, public source access, or guarantees about future releases.

No public Hex install test is possible before publication. No release tag, public
repository change, Hex/docs upload, or GitHub release was created. Data remains
best effort and in memory; overload/crashes may lose it and retries may duplicate it.
