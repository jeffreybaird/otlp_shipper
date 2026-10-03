# Hex release readiness

**0.2.1 is published**, verified through the public Hex API on October 3, 2026.
The registry lists its publication on September 30, 2026 at 11:05:10 UTC.
See [Hex release metadata](https://hex.pm/api/packages/otlp_shipper/releases/0.2.1).
Earlier [0.2.1](candidate-0.2.1.md) and [0.2.0](candidate-0.2.0.md) candidate
evidence describes pre-publication checks.

The current source prepares **0.2.2**, a security patch declaring direct Mint
1.10.2 and HPAX 1.0.4 floors. See [candidate evidence](candidate-0.2.2.md). Preparation does not
upload a package or documentation.

The source repository remains private. Public consumers can fetch the Hex source
archive and read HexDocs; GitHub source/support links require repository access.
A visibility change is a separate owner action.

## Subsequent releases

1. Obtain authorization for the target version and finish review/merge. Prior
   publication does not authorize another upload.
2. Update version, changelog, README, and public API docs consistently. Recheck
   upstream experimental logs support before deciding whether this handler is
   still needed.
3. Run formatting, warnings-as-errors compilation, ExUnit/doctests, strict
   CucumberEx acceptance tests (`MIX_ENV=test mix cucumber`), Dialyzer, strict Credo
   analysis (`mix credo --strict`), ExDoc, and Hex retirement audit. Require green
   CI on the release revision for both the pinned and minimum supported toolchains.
   Retirement audit is not a comprehensive vulnerability scan.
4. Run opt-in real Collector conformance and fresh production consumer checks with
   resolved/minimum dependencies and optional tracing absent/present. Follow
   [build.md](build.md); inspect source assets, licenses, metadata, and archive files.
5. Record the exact source revision and archive SHA-256. Rebuild and recheck if
   packaged contents change. Authenticate through the authorized publisher flow
   for a publication dry run; local builds do not require publisher authentication.
6. Publish the reviewed package/docs only when authorized. Verify versioned HexDocs
   and a fresh consumer fetching the exact public version, then record the results.

Known behavior limits and compatibility caveats remain in the README. Changes to
repository visibility, release tags, and GitHub releases require their own task scope.

There is no automated deployment or Hex publication workflow. Both CI toolchain
jobs require strict Credo analysis before package checks; publishing remains a
separately authorized action after this readiness procedure passes.
