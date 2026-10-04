# 0.1.1 publication verification

Historical record: versions, visibility, and publication status below describe that
release check. See [current release readiness](readiness.md) for present status.


Verified September 15, 2026 against the public release and merged repository.

| Item | Verified result |
| --- | --- |
| Package | [otlp_shipper 0.1.1](https://hex.pm/packages/otlp_shipper/0.1.1), public Hex |
| Published | September 13, 2026 at 15:47:57 UTC |
| Publisher / owner | `jeffreybaird`, as reported by the Hex API |
| Documentation | [Versioned HexDocs](https://hexdocs.pm/otlp_shipper/0.1.1/), HTTP 200 |
| Release change | PR #6, merged as `89bd9a1`; release commit `c0896c9b1485023eba8979ef54cc77f0ec22b307` |
| Archive SHA-256 | `00e7a4b9478a0ed4722e5f7e2b29a2412fb995c2a192904bdeaf439839553144` |
| Source visibility | GitHub remains private; public Hex and HexDocs are accessible independently |

Metadata comes from the [Hex release API](https://hex.pm/api/packages/otlp_shipper/releases/0.1.1).
The checksum was independently calculated from the
[published tarball](https://repo.hex.pm/tarballs/otlp_shipper-0.1.1.tar) and matches
Hex's release metadata. This is a different archive from the historical
[0.1.0 release](release-0.1.0.md); its candidate checksum is not reused.

## Compatibility change

The Finch requirement widened from `~> 0.20.0` to `~> 0.20`: versions
`>= 0.20.0` and `< 1.0.0` are now allowed. This resolves dependency conflicts for
consumers using Finch 0.21.x. Other dependency requirements and runtime code are
unchanged by the release. Allowing a version range does not establish testing of
all future Finch versions within it.

A disposable consumer fetched `{:otlp_shipper, "== 0.1.1"}` from Hex alongside
`{:finch, "== 0.21.0"}`. On Elixir 1.19.5 / OTP 29.0.1, it compiled in production
with warnings as errors, built a release, and passed the maintained package smoke
assertions: a decoded log and exact monotonic delta counter delivered over loopback
HTTP, with tracing API and runtime gpb absent.

The check reused `scripts/package_smoke.sh` through a temporary copy that selected
the exact public package and Finch versions instead of a local path dependency.
No production collector or credentials were involved. The maintained script and
CI retain their local-candidate and minimum-dependency coverage.

## Repository update

README installation and versioned links target 0.1.1; changelog dates and current
release guidance match the registry. Historical 0.1.0 verification is retained.
The package version and runtime implementation are unchanged by this documentation
update. Revised repository documentation does not replace the published archive or
upload revised HexDocs. Further publishing and source visibility changes remain
separate owner actions.
