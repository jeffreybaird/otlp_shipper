# Build and publish a Hex package

## Prepare locally

Run the verification commands in [../testing.md](../testing.md). Finish metadata,
license, and implementation work in [readiness.md](readiness.md) first. ExDoc is configured; `mix docs` generates local documentation.

Once configured, generate and inspect documentation:

```sh
mix docs
```

Check public examples, module navigation, source links, and referenced guide files.
Keep generated `doc/` output separate from maintained `docs/` sources.

Build in separate Mix invocations:

```sh
mix hex.build
mix hex.build --unpack --output /tmp/otlp_shipper-package-review
mix hex.publish --dry-run
```

Choose a fresh temporary output directory for each candidate. `hex.build` creates
a local archive; `--unpack` enables inspection of its source contents. The publish
dry run performs local checks without uploading. Consult installed task help if
options differ. See [Hex build](https://hex.hexdocs.pm/Mix.Tasks.Hex.Build.html)
and [Hex publish](https://hex.hexdocs.pm/Mix.Tasks.Hex.Publish.html).

## Inspect and reproduce

Review the archive's actual file list and metadata. Include all source, required
runtime assets, license text, README, and release notes. Exclude credentials,
environment files, caches, build output, and unrelated agent configuration. Set
`package[:files]` deliberately if the defaults omit required files; re-inspect after
changes. See the [Hex package configuration](https://hex.hexdocs.pm/Mix.Tasks.Hex.Build.html).

Keep a repository lockfile once dependencies exist to reproduce development checks.
Consumer resolution follows published dependency requirements; a library lockfile
cannot guarantee the versions a consuming application selects.

Create a separate temporary Mix project with a path dependency on the unpacked
package directory, not this repository. Fetch its dependencies, compile with
warnings as errors, and run an ExUnit smoke test using the documented public API.
Exercise startup and a representative operation if processes or transports exist.
Also compile the consumer in `MIX_ENV=prod` to detect development-only dependencies.
This check tests packaged source completeness, not Hex registry resolution.

Run `scripts/package_smoke.sh` to automate the clean consumer/release check. It
builds a local candidate, uses a disposable project, and verifies encoding and real log/metric loopback HTTP delivery without
gpb or optional tracing modules at runtime.

Record the archive's SHA-256 checksum and tested source revision. Do not edit the
candidate between review and publication; changed contents require renewed checks.

## Publish only when authorized

Authenticate through the publisher's normal Hex credential flow. Confirm the target
package, version, ownership, and final file list, then run `mix hex.publish` from
the reviewed source. This publishes the package and generated documentation;
`mix hex.publish docs` uploads documentation separately. See the official
[Hex publish task](https://hex.hexdocs.pm/Mix.Tasks.Hex.Publish.html).

After publication, use a fresh consumer with a Hex dependency on that exact version
and verify fetch, compilation, and the smoke test. Check the public package page and
versioned docs. Record the result. If there is a problem, stop further publication
and determine a fix; do not assume an existing release can always be replaced.
