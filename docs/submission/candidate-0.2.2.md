# 0.2.2 release candidate

## Scope

Security patch. Mint 1.10.1 and earlier are affected by EEF-CVE-2026-91043 (HIGH,
HTTP/2 HPACK cookie headers bypass `max_header_list_size`), EEF-CVE-2026-92103
(MEDIUM, oversized HTTP/2 frames buffered before `max_frame_size` enforcement) and
EEF-CVE-2026-94194 (MEDIUM, HTTP/1 chunked framing response smuggling). Mint 1.10.2
fixes all three. Finch, through 0.24.0, still accepts Mint `~> 1.8`, so the package
declares a direct `{:mint, "~> 1.10 and >= 1.10.2"}` requirement. Mint 1.10.2 still
accepts HPAX versions affected by EEF-CVE-2026-58226 (HIGH, unbounded HPACK integer
decoding; fixed in 1.0.4), so the package also declares
`{:hpax, "~> 1.0 and >= 1.0.4"}`. No public API, runtime behavior, or trace contract
changes. Contract: DEPS-01 to DEPS-06 in
`docs/features/dependency-requirements.feature` and
`test/otlp_shipper/dependency_requirements_test.exs`. The user requested release
preparation, not publication.

## Registry check

On October 3, 2026, the public Hex API listed `otlp_shipper` 0.2.1 as latest,
published September 30, 2026 at 11:05:10 UTC. Version 0.2.2 was not listed.
Mint 1.10.2 and 1.11.0 are published; finch 0.24.0 requires Mint `~> 1.8`.

## Verification

Checked with Elixir 1.19.5 (compiled OTP 28) / OTP 28 (ERTS 16.4.0.2), Hex 2.5.1,
matching `.tool-versions`. Base revision `dd748dfd0f78856543e50290551f8d678d8bf62f`
plus the uncommitted candidate diff (tracked diff SHA256 excluding `.agent-audit`
`93ae4ac522fd0bb75933a2142127af1b5a13d344ab952d041b0e5ba8e8e94213`).
Accepted test hashes were unchanged before and after the runs.

| Check | Result |
| --- | --- |
| Format and warnings-as-errors compile | Passed |
| ExUnit and doctests | 177 tests, 22 doctests; zero failures |
| Strict CucumberEx | 60 scenarios passed, including DEPS-01 to DEPS-06 |
| Strict Credo | No issues |
| Dialyzer | Zero errors or skips |
| `mix hex.audit` | No retired or advisory packages; no other scanner run |
| ExDoc warnings-as-errors | Passed; generated docs report v0.2.2 |
| Hex build | Passed |
| `mix hex.publish --dry-run --yes` | Stopped at Hex authentication; not authenticated, nothing uploaded |
| Pinned real Collector 0.160.0 | Passed gzip logs, four metric types, SDK traces and correlation |

The minimum CI toolchain (Elixir 1.19.0 / OTP 28.0) was not run locally; it is
covered by CI on the release revision.

## Artifact inspection

`otlp_shipper-0.2.2.tar`: 91,648 bytes, SHA256
`d4872f54a83e5f4028cb97b994a77203eefaa297c49f26cc8af2679ca94dc60f`.
49 files, all byte-identical to source; MIT metadata. Requirements add
`mint ~> 1.10 and >= 1.10.2` and `hpax ~> 1.0 and >= 1.0.4` (both non-optional);
all other requirements are unchanged.
Tests, scripts, agent configuration and credentials are excluded.

## Fresh production consumers

All six commands passed (seven modes), building fresh production releases from the
candidate archive and exercising real loopback HTTP:

- `sh scripts/package_smoke.sh` (Finch 0.24.0, Mint 1.11.0, HPAX 1.1.0)
- `OTLP_SMOKE_DEPENDENCY_SET=minimum sh scripts/package_smoke.sh` (Finch 0.20.0, Mint 1.10.2, HPAX 1.0.4)
- `OTLP_SMOKE_DEPENDENCY_SET=minimum_with_tracing sh scripts/package_smoke.sh` (Mint 1.10.2, HPAX 1.0.4, API 1.3.0)
- `sh scripts/trace_consumer_smoke.sh` (SDK absent and present)
- `sh scripts/replacement_consumer_smoke.sh`
- `OTLP_SMOKE_DEPENDENCY_SET=minimum sh scripts/replacement_consumer_smoke.sh` (Mint 1.10.2, HPAX 1.0.4)

Replacement reports: [current](evidence-0.2.2/replacement-default.json) and
[minimum](evidence-0.2.2/replacement-minimum.json). Both report shipper 0.2.2,
SDK 1.7.0/API 1.5.0, two logs, one metric, two traces, correlated logs and zero
feedback spans, without the canonical exporter or runtime gpb. The minimum optional
API smoke retains the known upstream API 1.3.0 `link/2` warning.

## Publication boundary

Package/docs upload, merge, tag, and GitHub release have not been performed.
Publication requires the reviewed revision, green pinned/minimum CI, an
authenticated `mix hex.publish --dry-run`, and explicit publication authorization.
Rebuild and recheck if packaged contents change. After publication, verify
exact-version public consumer installation and versioned HexDocs.
