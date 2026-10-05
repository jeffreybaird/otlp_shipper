# 0.2.3 release candidate

## Scope

Security patch. Published 0.2.2 requires Mint `~> 1.10 and >= 1.10.2`, but Mint
1.10.2 still accepts HPAX `~> 0.1.1 or ~> 0.2.0 or ~> 1.0`, including versions
affected by CVE-2026-58226 (EEF-CVE-2026-58226, GHSA-jj2p-32j7-whj2, HIGH:
unbounded HPACK integer decoding denial of service; affected `>= 0.1.1 and < 1.0.4`,
fixed in 1.0.4). The package now declares a direct `{:hpax, "~> 1.0 and >= 1.0.4"}`
requirement. The package's own Finch pools use HTTP/1, so exposure mainly reaches
consumers using Mint or Finch over HTTP/2 elsewhere. No public API or runtime
behavior changes. Contract: DEP-03 and DEP-04 in
`docs/features/package-dependencies.feature` and
`test/otlp_shipper/package_dependencies_test.exs`. The user requested release
preparation; publication requires a separately authenticated upload.

## Registry check

On October 5, 2026, the public Hex API listed `otlp_shipper` 0.2.2 (published
October 4) as latest; 0.2.3 was not listed. Its metadata requires Mint but not HPAX.
HPAX 1.0.4 and 1.1.0 are published; Finch 0.24.0 still requires Mint `~> 1.8`.

## Verification

Elixir 1.19.5 (compiled OTP 28) / OTP 28.5.0.2, Hex 2.5.1, matching
`.tool-versions`. Base revision `e1ae0ee1abd7c28afd4f8ab667753921972a38b3` plus the
candidate diff (tracked diff SHA256 excluding `.agent-audit`
`bb42a95d29c49f83d70fca9c11b81bd1a304e6e62788db6da990bf4058062c41`). Accepted test
hashes were unchanged before and after the runs. Review then corrected packaged
documentation only (`README.md` version links, `docs/compatibility.md`,
`docs/migration.md`); format, ExDoc, Hex build and the publish dry run were rerun on
the final tree (tracked diff SHA256 excluding `.agent-audit`
`fd8bd74ec5397772c4771c8f90736daff99e7a74fccedad4016fbb2700ef0410`). No runtime,
build or test file changed, so the consumer and Collector checks were not repeated.

| Check | Result |
| --- | --- |
| Format and warnings-as-errors compile | Passed |
| ExUnit and doctests | 175 tests, 22 doctests; zero failures |
| Strict CucumberEx | 53 scenarios passed, including DEP-01 to DEP-04 |
| Strict Credo | No issues |
| Dialyzer | Zero errors or skips |
| `mix hex.audit` | No retired or advisory packages; not a comprehensive scan |
| ExDoc warnings-as-errors | Passed; generated docs report v0.2.3 |
| Hex build | Passed |
| `mix hex.publish --dry-run --yes` | Stopped at Hex authentication; not authenticated, nothing uploaded |
| Pinned real Collector 0.160.0 | Passed gzip logs, four metric types, SDK traces and correlation |

The minimum CI toolchain (Elixir 1.19.0 / OTP 28.0) was not run locally.

## Artifact inspection

Final `otlp_shipper-0.2.3.tar`: 95,232 bytes, SHA256
`da925fc231f00d662a0b68ca871ba450d7eca00e5c1af07cf30f7f7baffd0425`. It differs from
the matrix-tested archive (`5c61eb91…6e77`) only in those three documentation files;
`metadata.config` is byte-identical.
55 files, all byte-identical to source; MIT metadata. Requirements add
`hpax ~> 1.0 and >= 1.0.4` (non-optional); Mint and all other requirements are
unchanged from 0.2.2. The six extra files relative to 0.2.2's recorded 49 are the
consumer guides added to `package[:files]` before this change. Tests, scripts,
agent configuration and credentials are excluded.

## Fresh production consumers

All six commands passed (seven modes):

- `sh scripts/package_smoke.sh` (Finch 0.24.0, Mint 1.11.0, HPAX 1.1.0)
- `OTLP_SMOKE_DEPENDENCY_SET=minimum sh scripts/package_smoke.sh` (Finch 0.20.0, Mint 1.10.2, HPAX 1.0.4)
- `OTLP_SMOKE_DEPENDENCY_SET=minimum_with_tracing sh scripts/package_smoke.sh` (Mint 1.10.2, HPAX 1.0.4, API 1.3.0)
- `sh scripts/trace_consumer_smoke.sh` (SDK absent and present)
- `sh scripts/replacement_consumer_smoke.sh` (Mint 1.11.0, HPAX 1.1.0)
- `OTLP_SMOKE_DEPENDENCY_SET=minimum sh scripts/replacement_consumer_smoke.sh` (Finch 0.20.0, Mint 1.10.2, HPAX 1.0.4)

Replacement reports: [current](evidence-0.2.3/replacement-default.json) and
[minimum](evidence-0.2.3/replacement-minimum.json). Both report two logs, one
metric, two traces, correlated logs and zero feedback spans, without the canonical
exporter or runtime gpb.

## Publication boundary

Merge, tag, GitHub release and Hex upload have not been performed. Publication
requires the reviewed revision, green pinned/minimum CI, an authenticated
`mix hex.publish --dry-run`, and the owner's upload. Rebuild and recheck if
packaged contents change. After publication, verify exact-version consumer
installation and versioned HexDocs.
