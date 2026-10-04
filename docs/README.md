# Documentation

## Use the package

Start with the [quickstart](../README.md), then choose the guide for your task:

| Task | Guide |
| --- | --- |
| Send Logger events | [Logs](logs.md) |
| Count events and measure durations | [Metrics](metrics.md) |
| Configure trace export | [Trace setup and migration](migration.md) |
| Set endpoints, credentials, and limits | [Configuration](configuration.md) |
| Diagnose missing or rejected telemetry | [Troubleshooting](troubleshooting.md) |
| Check versions or upgrade | [Compatibility](compatibility.md) |
| Work with prepared records or named providers | [Advanced APIs](advanced.md) |

## Develop the package

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
MIX_ENV=test mix cucumber
mix credo --strict
mix dialyzer
mix hex.audit
mix docs --warnings-as-errors
scripts/package_smoke.sh
sh scripts/trace_consumer_smoke.sh
sh scripts/replacement_consumer_smoke.sh
```

Tests use a loopback Bandit collector and generated decoders, with no external
collector or production credentials. Run real Collector conformance separately with
a local Docker engine (not a remote Docker context):

```sh
docker pull otel/opentelemetry-collector@sha256:e495787f07dbe432ce763ebaf5bc3d113850e9eee2250ade7a3da6a882d0d69a
mix otlp_shipper.conformance
```

This pins official Collector **0.160.0**. The task uses an ephemeral loopback port,
a read-only configuration mount, and synthetic gzip logs, metrics, and SDK spans from a separate
VM with inherited `OTEL_*` variables removed. It checks the detailed debug exporter's
log body, severity, attributes, metric types, delta temporality, values, and histogram
buckets, SDK span parentage, scope/resource identity, event/status fields, and
log correlation. No credentials or backend account are needed. Docker commands have 30-second
deadlines; readiness/output checks allow 60 polls. Its own container is removed on
success or failure. If the VM is killed, remove the printed container name manually.
A missing image, stopped engine, or blocked bind mount causes the task to fail;
check Docker and the pull command first. Default tests and CI do not invoke Docker.
CI uses `.tool-versions`; local verification must report any different toolchain.

OTLP schema sources are vendored from `opentelemetry-proto` v1.5.0 with their
Apache-2.0 license and provenance in `priv/proto/`. gpb generates namespaced modules
at build time and is not a runtime application. Collector response decoding is
included to detect partial rejection; production does not ingest encoded telemetry.

Building a package does not publish it.


## Contributor reference

| Document | Use |
| --- | --- |
| [Architecture](architecture.md) | Components and dependency boundaries |
| [Testing](testing.md) | Test layers and consumer verification |
| [Elixir style](elixir-style.md) | Code conventions |
| [Interface design](interface-design.md) | Public API conventions |
| [Data handling](data-handling.md) | Credentials and telemetry privacy |
| [Product decisions](product-decisions.md) | Current scope and historical decisions |
| [Agent coordination](codex-agents.md) | Agent workflow |
| [Agent guardrails](agent-guardrails.md) | Hook activation and enforcement |
| [Release readiness](submission/readiness.md) | Release gates |
| [Build](submission/build.md) | Package inspection and publication |
| [Package listing](submission/package-listing.md) | Metadata checklist |
| [Reviewer notes](submission/reviewer-notes.md) | Release review |
| [0.2.2 evidence](submission/candidate-0.2.2.md) | Release verification |
| [Documentation approach](documentation-approach.md) | Research and writing choices |

Maintained source guides live in `docs/`; generated ExDoc output lives in `doc/`.
Dated phase and release records describe their original runs. See
[PLAN.md](../PLAN.md) for the implementation plan.
