# Package metadata and consumer documentation

This is a preparation checklist, not ready-to-paste marketing copy. PLAN.md targets
OTLP/HTTP logs and metrics; both components and real Collector conformance are implemented.

Keep `mix.exs`, README, public module docs, and release notes consistent:

| Field | Current state / required work |
| --- | --- |
| Application / intended package | `:otlp_shipper` / `otlp_shipper` on public Hex; publisher/owner `jeffreybaird` |
| Version | `0.1.0`, published September 13, 2026 |
| Description | Metadata and README describe implemented logs and metrics |
| License | MIT text and matching metadata added |
| Links | Public Hex and versioned HexDocs available; GitHub source/support links remain private |
| Elixir / OTP support | Elixir 1.19+ / OTP 28+ baseline; minimum and pinned CI plus local OTP 29 checks |
| Dependencies | Finch and telemetry required; gpb build-time; tracing API optional |

The README should explain installation, a working minimal example, configuration,
supervision if needed, errors, limitations, and upgrade notes. If the package exports
telemetry, state supported signals/transports and delivery guarantees precisely.
Document units and defaults. Keep examples free of credentials and invented APIs.

Do not present private repository links as publicly accessible source, and verify versioned
HexDocs links against each published release. Package metadata conventions
are described in the [Hex publishing guide](https://hex.pm/docs/publish).
