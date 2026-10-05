# Package metadata and consumer documentation

This is a preparation checklist, not ready-to-paste marketing copy. The package implements
OTLP/HTTP logs, metrics, and SDK-compatible traces, including real Collector conformance.

Keep `mix.exs`, README, public module docs, and release notes consistent:

| Field | Current state / required work |
| --- | --- |
| Application / intended package | `:otlp_shipper` / `otlp_shipper` on public Hex; publisher/owner `jeffreybaird` |
| Version | `0.2.2` current release; `0.2.3` candidate |
| Description | Metadata describes logs, metrics, and SDK-compatible trace export; release status is tracked in the readiness checklist |
| License | MIT text and matching metadata added |
| Links | Public Hex and versioned HexDocs available; GitHub source/support links are public |
| Elixir / OTP support | Elixir 1.19+ / OTP 28+ baseline; minimum and pinned CI plus local OTP 29 checks |
| Dependencies | Finch/telemetry required; Mint >= 1.10.2 and HPAX >= 1.0.4 within 1.x; gpb build-time; tracing API and SDK optional; SDK startup consumer-owned |

The README should explain installation, a working minimal example, configuration,
supervision if needed, errors, limitations, and upgrade notes. If the package exports
telemetry, state supported signals/transports and delivery guarantees precisely.
Document units and defaults. Keep examples free of credentials and invented APIs.

Verify source visibility and versioned HexDocs links against each published release. Package metadata conventions
are described in the [Hex publishing guide](https://hex.pm/docs/publish).
