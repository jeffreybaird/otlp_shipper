# 0.1.0 publication verification

Historical release record. [0.1.1](release-0.1.1.md) is now the current release.

Verified September 13, 2026 after the owner reported publication.

| Item | Verified result |
| --- | --- |
| Package | [otlp_shipper 0.1.0](https://hex.pm/packages/otlp_shipper/0.1.0), public Hex |
| Published | September 13, 2026 at 10:17:04 UTC |
| Publisher / owner | `jeffreybaird`, as reported by the Hex API |
| Documentation | [Versioned HexDocs](https://hexdocs.pm/otlp_shipper/0.1.0/), HTTP 200; Hex reports docs present |
| Phase 3 merge | PR #4 merged as `591dd30e00529dc73a3381c86cc58fe44df8bc4f` |
| Archive SHA-256 | `e761db3a774e28cd8a3cb2c8524416f4e1cff1cafee63277b09890b68229d325` |
| Candidate comparison | Downloaded public archive exactly matches the reviewed candidate checksum |
| Source visibility | GitHub remains private; public Hex/HexDocs access does not grant GitHub access |

Metadata was read from the [Hex release API](https://hex.pm/api/packages/otlp_shipper/releases/0.1.0)
and the checksum was independently calculated from the
[published tarball](https://repo.hex.pm/tarballs/otlp_shipper-0.1.0.tar).
The original source revision and pre-publication checks remain in
[candidate.md](candidate.md).

## Public Hex consumer check

A disposable consumer used `{:otlp_shipper, "== 0.1.0"}` from Hex, rather than a
path dependency or this checkout. On Elixir 1.19.5 / OTP 29.0.1, it successfully:

- Fetched the published package and resolved its dependencies.
- Compiled in production with warnings as errors and built a release.
- Started the Logger handler and delivered a decoded log over loopback HTTP.
- Started the metrics reporter and delivered an exact monotonic delta counter.
- Verified the optional tracing API and build-time gpb were absent at runtime.

The check reused the assertions in `scripts/package_smoke.sh` through a temporary
copy whose consumer dependency was changed to the exact Hex version. No production
collector, credentials, or release upload was involved. The maintained script still
checks locally built candidates for subsequent development.

## Repository follow-up

The README now installs from Hex, the changelog dates the 0.1.0 release, and current
release guidance no longer lists resolved publication prerequisites. This update
preserves the published version and historical candidate evidence. It does not
replace the published archive or upload revised HexDocs; those retain the content
that was published, including the earlier candidate wording.

Future package/docs publication and changes to GitHub visibility remain separate
owner actions. Runtime behavior and compatibility requirements are unchanged.
