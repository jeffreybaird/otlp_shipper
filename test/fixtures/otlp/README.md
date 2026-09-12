# Recorded recipe fixture

`elixir_fallback_logs.bin` is copied byte-for-byte from
`elixir_as_inf/test/fixtures/otlp/elixir_fallback_logs.bin`, inspected September 12,
2026. It contains six synthetic logs emitted by `examples/otlp_log_handler.ex`
through opentelemetry_exporter 1.10's generated encoder, with opentelemetry 1.7,
Elixir 1.20.4, and OTP 28.5. Two records carry span IDs; one has a structured body.

The source fixture README records capture through the hub's fixture-recording task.
No request headers or credentials are copied. Never hand-edit the binary. This is
recipe compatibility evidence; live OpenTelemetry Collector conformance is Phase 3.

SHA-256: `bb03ff0f55f82762de0af04e94fa1396ff7922e96e44d52035707dfb4c4ab064`.
