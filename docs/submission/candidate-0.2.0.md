# 0.2.0 candidate evidence

Historical record: versions, visibility, and publication status below describe that
release check. See [current release readiness](readiness.md) for present status.


This is release preparation, not a public release. The published version remains
0.1.1. No package/docs upload, tag, or GitHub release has been performed.

## Scope

The candidate adds optional SDK 1.7.0/API 1.5.0 trace export to the existing logs
and metrics package. The SDK retains context, sampling, instrumentation, and queue
ownership. The migration guide is included in the archive and ExDoc extras.

The SDK dependency is optional and compile-time ordered with `runtime: false`;
consumers explicitly own ordinary or included SDK startup. Real replacement proof
uses the included SDK, a supervised pool-before-SDK sequence, and unchanged Finch
instrumentation 0.2.0. The sampler wrapper prevents shipper HTTP from producing
feedback spans. No canonical exporter or runtime gpb is included in that proof.

## Local evidence

Pinned Collector 0.160.0 passed logs, all four metrics, SDK spans, parentage,
resource/scope identity, status/event fields, and log correlation. The authentic
capture is `test/fixtures/conformance/collector-three-signals-0.160.0.txt`, SHA-256
`44ddf709e0527831f8b960a2336f9f50d1cac470a6277cf761df153954307cf3`.
The image digest is recorded by the conformance task; the capture contains only
synthetic data. Test fixtures validating report structure are separate from runtime
replacement evidence.

Local archive: `otlp_shipper-0.2.0.tar`, 90,624 bytes, SHA-256
`cab8b8b6a51b18786fdf653e726316414126a9113f01506d1fd1d507f4962c7b`.
Its 49 files include source, migration guide, schemas and licenses; development
fixtures, scripts, credentials, and agent configuration are excluded.
`mix hex.publish --dry-run --yes` passed its local package/documentation checks.
Hex's dry-run mode performs no upload, despite printing its normal publishing
stage labels.

All local gates and independent source review passed: 166 tests, 22 doctests,
37 strict Cucumber scenarios, strict Credo, Dialyzer (zero errors/skips), audit,
ExDoc, five existing consumer modes and two replacement modes. The known upstream
API 1.3.0 `link/2` warning on OTP 29 remains in the minimum optional-API smoke;
no warning suppression was added. Exact packaged source revision: `01ff8c1564224d39fc2ca1e07dcafcf83b684eb5`.
Independent reviewers approved their separate scopes on this commit. Remote CI
status is attached to [PR #19](https://github.com/jeffreybaird/otlp_shipper/pull/19);
subsequent evidence-only edits do not change the archive contents. See the [work record](../workflows/phase-7-trace-release.md).

## Publication boundary

Publishing requires separate owner authorization, review/merge, green CI on the
release revision, refreshed archive checksum, publisher authentication if needed,
and subsequent public-version installation verification. Local Hex build and
production consumers do not establish that anything was published.


## Actual replacement measurements

The reports are from successful fresh production releases, not the synthetic
validator fixture: [current](evidence-0.2.0/replacement-default.json) and
[minimum](evidence-0.2.0/replacement-minimum.json). Both use SDK 1.7.0/API 1.5.0 and
Finch instrumentation 0.2.0, deliver exactly two logs, one delta counter and two
spans, preserve IDs/resource identity, and observe zero feedback spans after
repeated flush and shutdown. A pool crash first replaces the included global SDK;
the proof then performs ordinary instrumentation and delivery.

| Observation | Current | Minimum |
| --- | --- | --- |
| Finch | 0.23.0 | 0.20.0 |
| telemetry / telemetry_metrics | 1.4.2 / 1.2.0 | 1.3.0 / 1.1.0 |
| Elapsed proof time | 359 ms | 387 ms |
| VM memory before | 60,592,262 bytes | 61,258,973 bytes |
| VM memory after | 65,949,263 bytes | 66,097,098 bytes |
| Loaded runtime applications, including OTP/consumer | 23 | 23 |
| Resolved build dependencies, including local package | 13 | 13 |

The canonical exporter is absent from build and runtime inventories. gpb remains
build-only. These single-run VM snapshots do not measure allocation volume,
retained heap after GC, steady-state throughput, or comparative dependency size.
No performance/footprint advantage is claimed. Both reports use local Elixir
1.19.5 / OTP 29.0.1; remote CI provides the pinned/minimum toolchain checks.


## Dependency audit follow-up

Remote CI additionally checks security advisories and caught locked Mint 1.10.0
([upstream advisory](https://github.com/elixir-mint/mint/security/advisories/GHSA-rj5m-69wp-cxq9)).
The repository lock is updated to patched 1.10.1. All fresh consumer reports already
use that version. Consumers retaining an older lock must upgrade Mint themselves;
this library's lock is not included in its archive. The archive hash and packaged
source revision above are unchanged. Final audit evidence is on PR #19.
