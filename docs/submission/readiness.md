# Hex release readiness

**0.1.0 is published**, as of September 13, 2026. Hex lists `jeffreybaird` as owner
and publisher, and versioned HexDocs is available. See
[release verification](release-0.1.0.md) for the downloaded archive checksum and
public Hex consumer check. [candidate.md](candidate.md) preserves the earlier
pre-publication evidence, including the unauthenticated dry-run limitation.

The source repository remains private. Public consumers can fetch the Hex source
archive and read HexDocs, but the configured GitHub source/support links require
repository access. A visibility change is a separate owner action.

## Subsequent releases

1. Obtain authorization for the target version and finish review/merge. Prior
   publication does not authorize another upload.
2. Update version, changelog, README, and public API docs consistently. Recheck
   upstream experimental logs support before deciding whether this handler is
   still needed.
3. Run formatting, warnings-as-errors compilation, ExUnit/doctests, Dialyzer,
   ExDoc, and Hex retirement audit. Require green CI on the release revision for
   both the pinned and minimum supported toolchains. Retirement audit is not a
   comprehensive vulnerability scan.
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
