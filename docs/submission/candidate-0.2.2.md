# 0.2.2 release evidence

The current release is 0.2.2. This record preserves the checks performed before
publication; registry observations below are dated evidence, not release status.

## Scope and pre-publication observations

Release date: October 4, 2026. Refresh consumer/API/development documentation, remove
stale private-source and unpublished-0.2.1 claims, and require Mint >= 1.10.2 within
1.x. The owner approved the dependency security floor during this release review.
Runtime APIs and trace configuration remain unchanged.

Unauthenticated public APIs confirmed the repository is public and Hex 0.2.1 was
published September 30, 2026 at 11:05:10 UTC with documentation. Version 0.2.2 was
not listed at the initial check. Experimental OpenTelemetry 0.6.0 is the current
registry release; runtime replacement compatibility was not reevaluated.

- [Package metadata](https://hex.pm/api/packages/otlp_shipper)
- [Source metadata](https://api.github.com/repos/jeffreybaird/otlp_shipper)
- [Experimental SDK metadata](https://hex.pm/api/packages/opentelemetry_experimental)

## Security review

The prior repository lockfile update already selected Mint 1.10.2. Hex does not
ship this lockfile, and Finch's allowed versions alone do not exclude older Mint.
The new direct dependency requirement applies that floor to consumer resolution.

Mint 1.10.2 fixes all three findings affecting the prior locked 1.10.1:

| Advisory | Affected versions | Exposure |
| --- | --- | --- |
| [CVE-2026-94194](https://cna.erlef.org/cves/CVE-2026-94194.html) | >= 0.1.0, < 1.10.2 | HTTP/1 response poisoning with attacker-influenced origin, intermediary, and reused connections |
| [CVE-2026-91043](https://cna.erlef.org/cves/CVE-2026-91043.html) | >= 1.1.0, < 1.10.2 | Malicious HTTP/2 server header expansion denial of service |
| [CVE-2026-92103](https://cna.erlef.org/cves/CVE-2026-92103.html) | >= 0.1.0, < 1.10.2 | Malicious HTTP/2 oversized buffering denial of service |

Actual exposure depends on collector trust, intermediaries, and pool/protocol
configuration. On October 4, `mix hex.audit` found no retired packages. A fresh
OSV query of all 36 locked Hex packages returned no findings. Neither result is a
proof that undisclosed vulnerabilities are absent.

## Dependency contract workflow

The independent runner demonstrated two failing ExUnit tests and five failing
Cucumber scenarios before the Mint declaration was added. Every failure identified
the missing direct security requirement. The reviewer accepted these contracts:
required production Hex dependency; reject 1.10.1, accept 1.10.2 and 1.11.0, reject
2.0.0. Frozen SHA-256 values:

- `test/otlp_shipper/package_dependencies_test.exs`:
  `6ec3ffd1a22c6ecbd522ca7820f81b4436026cf97c0b28ac799db679be098018`
- `features/step_definitions/package_dependencies_steps.ex`:
  `ff02d09593414197c4b3a9ba89a9f3d720e9aa41b5583916b15834a136005ff1`
- `docs/features/package-dependencies.feature`:
  `1c9f63c6287f4eec82a1c7215ddf916fe547a4dc52445573b929be023a0ac157`

## Verification

Independent runner used Elixir 1.19.5 (compiled for OTP 28), runtime OTP 29 / ERTS
17.0.1. This differs from the pinned CI OTP 28.5.0.2 toolchain.

| Check | Result |
| --- | --- |
| Formatting; warnings-as-errors compilation | Passed |
| ExUnit and doctests | 173 tests, 22 doctests, zero failures |
| Strict CucumberEx | 47 scenarios passed |
| Strict Credo; Dialyzer | Passed, no issues/errors/skips |
| Hex retirement audit | Passed |
| ExDoc warnings-as-errors | Passed; version 0.2.2 and generated migration links verified |
| Local Markdown links | 40 documents, zero broken local paths |
| Hex build and archive inspection | Passed; 49 packaged files |
| `mix hex.publish --dry-run --yes` | Passed; no upload or authentication changes |
| Pinned real Collector 0.160.0 | Passed logs, four metric types, SDK traces and correlation |

All six fresh consumer commands passed:

- `sh scripts/package_smoke.sh`
- `OTLP_SMOKE_DEPENDENCY_SET=minimum sh scripts/package_smoke.sh`
- `OTLP_SMOKE_DEPENDENCY_SET=minimum_with_tracing sh scripts/package_smoke.sh`
- `sh scripts/trace_consumer_smoke.sh` (SDK absent and present)
- `sh scripts/replacement_consumer_smoke.sh`
- `OTLP_SMOKE_DEPENDENCY_SET=minimum sh scripts/replacement_consumer_smoke.sh`

Actual replacement reports: [current](evidence-0.2.2/replacement-default.json) and
[minimum](evidence-0.2.2/replacement-minimum.json). Fresh resolution selected Mint
1.11.0; the repository gate used locked Mint 1.10.2. Minimum consumer mode pins
Finch 0.20.0 and the other declared minimum dependencies, but does not pin Mint to
1.10.2. The dependency contract separately verifies acceptance of 1.10.2 and
rejection of 1.10.1. Existing upstream API 1.3.0 warnings on OTP 29 remain disclosed
in the README; no diagnostics were suppressed.

Archive `otlp_shipper-0.2.2.tar` SHA-256:
`de0b1197ff8f1710b4ec23f387ad1a6a6842fdb70bb0b493e9bbd9a76bc95311`.
Version, required Mint floor, MIT metadata, source/build inputs, schema licenses,
migration guide, and conformance assets were inspected. Tests, scripts, agent/Git
configuration, caches, credentials, and the repository lockfile are excluded.

Independent review accepted the source/test/doc diff and generated documentation.
All accepted test hashes remain unchanged. Two shell-audit records overlap runner
and test-writer formatting activity; the reviewer inspected the commands and hashes
and found no evidence of the runner editing tests. No checks were weakened.

The source base is `8f64716`; the release branch is `codex/release-0.2.2`.
Remote pinned/minimum CI results are attached to PR #23 below.
These local checks and dry runs did not upload a package or documentation.


## Final documentation clarification

The complete local matrix initially checked archive
`080b211533b59c897b1c7a2c9ae8e2a5f6248993c8648b92726c309641a33460`.
Final review clarified which lower bounds the consumer scripts pin in README.
Rebuilt ExDoc, Hex archive, and publication dry run passed. Independent archive
comparison confirmed all packaged files except README are byte-identical, including
all source, build inputs, dependency metadata, and tests' runtime targets. The final
checksum is recorded above. Accepted test hashes remain unchanged; independent
review reports no remaining findings.

[PR #23](https://github.com/jeffreybaird/otlp_shipper/pull/23) carries the exact
reviewed revisions and pinned/minimum CI results. The owner publishes 0.2.2 upon
merge; consumer documentation describes the resulting release state.


## Release-state documentation

At the owner's request, current guides describe 0.2.2 as the current release for
publication upon merge. Earlier registry checks above remain historical evidence.
ExDoc with warnings as errors, Hex build, and the publication dry run passed after
this wording update. Comparing the rebuilt archive with the preceding archive
confirmed only README changed; dependency metadata and runtime/build files remain
byte-identical. The final archive checksum above reflects this update.
