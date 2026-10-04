# Compatibility and upgrades

Add the package to your `mix.exs` dependencies:

```elixir
{:otlp_shipper, "~> 0.2.2"}
```

Run `mix deps.get`. Add signal components to your existing application supervisor.

## Supported toolchains and dependencies

Elixir 1.19+ and OTP 28+ are the supported baseline. CI checks Elixir 1.19.0 / OTP
28.0 and the pinned Elixir 1.19.5 / OTP 28.5.0.2 pair; local release checks also use
Elixir 1.19.5 / OTP 29.0.1. The declared Elixir requirement permits future 1.x
versions, but those are not pre-certified.

Version 0.1.1 widens Finch from `~> 0.20.0` to `~> 0.20`, allowing versions
`>= 0.20.0` and `< 1.0.0`, including 0.21.x. No runtime behavior changed.

Dependency lower bounds are Finch 0.20.0, Mint 1.10.2, telemetry 1.3.0, telemetry_metrics 1.1.0,
gpb 4.21.7, and optional opentelemetry_api 1.3.0. Fresh production consumers exercise
the pinned Finch, telemetry, telemetry_metrics, gpb, and optional API minimums
with and without tracing. They resolve Mint independently; the repository test gate
uses Mint 1.10.2. gpb 4.21.0 cannot compile on OTP 29 and is
excluded. Optional API 1.3.0 works in the no-active-span smoke but emits an upstream
`link/2` warning on OTP 29; prefer API 1.5.0 there. SDK span integration is tested
with API 1.5.0 / SDK 1.7.0. gpb is a build dependency, absent at release runtime.

Version 0.2.2 requires Mint 1.10.2 or newer within 1.x to exclude versions affected
by CVE-2026-94194, CVE-2026-91043, and CVE-2026-92103. When upgrading an existing
consumer, run `mix deps.update otlp_shipper mint` and review the resulting lockfile.
The package's repository lockfile does not control consumer resolution.

## Trace support

The verified pair is OpenTelemetry SDK **1.7.0** / API **1.5.0**. Initialization
rejects unverified versions. Adding the SDK to an existing consumer requires
recompiling `otlp_shipper`; trace integration modules are selected at compilation.
Follow [trace setup and migration](migration.md).

## When to use another exporter

Use another exporter when you need trace protocols or SDK versions outside the
SDK/API pair above. Unsupported metric types and units are rejected at startup. Before adopting the logs handler, compare
[`opentelemetry_experimental`](https://hex.pm/packages/opentelemetry_experimental)
with this package's Logger integration and delivery contracts; avoid exporting each
event through both. The October 4, 2026 registry check found experimental 0.6.0.
Its runtime replacement compatibility has not been reevaluated here; the historical
0.5.1 investigation is not evidence that current upstream logs support is broken.
Do not use this package when durable or exactly-once log delivery is required.
