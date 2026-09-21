# 0.2.1 release candidate

## Scope

Patch release for the dynamic logs/metrics instrumentation scope version.
The hub already displays received metadata; the shipper now derives it from OTP
application metadata. No dependency or trace API change. Existing stored telemetry
is unchanged. User requested release preparation, not publication.

## Registry and upstream check

On September 21, 2026, the public Hex API reported `otlp_shipper` 0.2.0 as latest,
published at 15:44:25 UTC with docs. Version 0.2.1 was not listed.
[Package API](https://hex.pm/api/packages/otlp_shipper).

The experimental OpenTelemetry package now lists 0.6.0, published September 15,
2026, superseding the historical 0.5.1 observation. This maintenance patch retains
the existing Logger handler; it makes no claim that upstream 0.6.0 cannot export
logs and does not change or deprecate that public API. Upstream runtime replacement
compatibility was not reevaluated as part of this version metadata fix.
[Upstream package API](https://hex.pm/api/packages/opentelemetry_experimental).

## Verification

Checked with Elixir 1.19.5 (compiled OTP 28) / OTP 29 (ERTS 17.0.1).
Independent runner: gpt-5.6-luna. Frozen source base `c37057264d99635fe47f11a43726051e30f25b1e`,
tracked diff SHA256 `397c3c353cea1494c585d2771d8cba67376416b54005c97a2da28bdf523df355`.
Evidence-only updates do not enter the package archive.

| Check | Result |
| --- | --- |
| Format and warnings-as-errors compile | Passed |
| ExUnit and doctests | 171 tests, 22 doctests; zero failures |
| Strict CucumberEx | 42 scenarios passed |
| Strict Credo | No issues |
| Dialyzer | Zero errors or skips |
| Hex retirement audit | No retired dependencies; not a comprehensive security scan |
| ExDoc warnings-as-errors | Passed; v0.2.1 title and migration navigation checked |
| Hex build | Passed |
| `mix hex.publish --dry-run --yes` | Passed; no upload |
| Pinned real Collector 0.160.0 | Passed logs, four metric types, SDK traces, parentage and correlation |

The dry-run task prints its normal publishing-stage labels, but `--dry-run`
prevents upload. No authentication changes were made.

## Artifact inspection

`otlp_shipper-0.2.1.tar`: 90,624 bytes, SHA256
`61f34ffe6c6ae8d7c509eeee231875d3441d35e1e7a8b216653534b35ffff8ef`.
49 packaged files, MIT metadata, unchanged dependency constraints. Source, schema
provenance/licenses, generated-code build task, migration guide and conformance
assets are included. Tests, scripts, agent configuration, dependencies, caches and
credentials are excluded. Packaged version/source/docs/licenses match the reviewed
tree. Generated documentation reports version 0.2.1.

## Fresh production consumers

All six commands passed (seven modes; the trace script checks SDK absence and
presence). They build from fresh unpacked candidate archives into isolated
production releases and exercise real loopback HTTP:

- `sh scripts/package_smoke.sh`
- `OTLP_SMOKE_DEPENDENCY_SET=minimum sh scripts/package_smoke.sh`
- `OTLP_SMOKE_DEPENDENCY_SET=minimum_with_tracing sh scripts/package_smoke.sh`
- `sh scripts/trace_consumer_smoke.sh`
- `sh scripts/replacement_consumer_smoke.sh`
- `OTLP_SMOKE_DEPENDENCY_SET=minimum sh scripts/replacement_consumer_smoke.sh`

Actual replacement reports: [current](evidence-0.2.1/replacement-default.json)
and [minimum](evidence-0.2.1/replacement-minimum.json). Both report shipper 0.2.1,
SDK 1.7.0/API 1.5.0, two logs, one metric, two traces, correlated logs and zero
feedback spans. The canonical exporter and runtime gpb are absent. Finch versions
are 0.23.0 and 0.20.0 respectively. The minimum optional API smoke retains the
known upstream API 1.3.0 warning on OTP 29; no suppression or dependency change.

These reports are actual execution evidence, not the synthetic validator fixture.
The elapsed/memory measurements are descriptive and are not a benchmark.

The initial full matrix used archive SHA256
`b5b4e95c2c027ddc8f7d0e4b6984434acdd0fd187b519a3174ac8367099751bf`.
The user then requested installation examples require `~> 0.2.1`. Only packaged
`README.md` and `docs/migration.md` changed. All runtime/build/schema files remain
byte-identical to the matrix-tested archive. Rebuilt ExDoc, Hex archive and publish
dry run passed; all 49 final archive files match source. The final checksum is
recorded above. No runtime test changes or functionality changes occurred.

Final source revision, independent review and pinned/minimum CI status are attached
to [PR #22](https://github.com/jeffreybaird/otlp_shipper/pull/22). The candidate was
verified using the frozen source snapshot above; subsequent evidence-only edits
are excluded from the archive.

## Publication boundary

Package/docs upload, merge, tag, and GitHub release have not been performed.
Publication requires the reviewed revision, green pinned/minimum CI, and explicit
publication authorization. After publication, verify exact-version public consumer
installation and versioned HexDocs. Candidate testing alone does not prove a public release.
