# Package reviewer notes

Review one identified source revision and candidate archive. No collector account,
production key, or browser profile should be needed for deterministic verification.

1. Read the package decisions and compare the README's claims with actual APIs.
2. Run the current formatting, compilation, and ExUnit checks. Record tool versions
   and exact failures; scaffold tests do not establish shipping functionality.
3. Review public types, errors, defaults, compatibility, and documented limitations.
4. Where applicable, check process ownership, overload, retry safety, flush and
   shutdown behavior, and failure effects on the consuming application.
5. Inspect the archive and generated docs, then follow the fresh-consumer procedure
   in [build.md](build.md). Ensure runtime assets and dependencies are complete.
6. Review credentials/redaction and observability feedback paths if export exists.
7. Report actionable defects with file/line evidence, missing acceptance coverage,
   and release blockers. Distinguish mocked behavior from live interoperability.

A reviewer approves evidence for a candidate, not registry ownership or publication.
The release-readiness checklist remains incomplete until each item has real evidence.
