# Package metadata and consumer documentation

This is a preparation checklist, not ready-to-paste marketing copy. PLAN.md targets
OTLP/HTTP logs and metrics; neither component is implemented yet.

Keep `mix.exs`, README, public module docs, and release notes consistent:

| Field | Current state / required work |
| --- | --- |
| Application / intended package | `:otlp_shipper` / `otlp_shipper` confirmed for public Hex; ownership unverified |
| Version | `0.1.0`; scaffold version, not evidence of a published release |
| Description | Replace TODO with an accurate statement of implemented behavior |
| License | MIT selected in PLAN.md; add text and matching metadata |
| Links | Empty; supply real source, docs, and support URLs |
| Elixir / OTP support | `~> 1.19` declared; verify and document tested combinations |
| Dependencies | None configured; document runtime versus optional integrations |

The README should explain installation, a working minimal example, configuration,
supervision if needed, errors, limitations, and upgrade notes. If the package exports
telemetry, state supported signals/transports and delivery guarantees precisely.
Document units and defaults. Keep examples free of credentials and invented APIs.

Do not present private repository links as publicly accessible source, or construct
HexDocs URLs as though publication has already occurred. Package metadata conventions
are described in the [Hex publishing guide](https://hex.pm/docs/publish).
