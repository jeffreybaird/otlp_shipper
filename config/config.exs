import Config

# Disable the default network exporter; compatibility probes own isolated providers.
if config_env() == :test do
  config :opentelemetry, traces_exporter: :none

  config :cucumberex, :config,
    paths: [
      "docs/features/cucumberex.feature",
      "docs/features/trace-compatibility.feature",
      "docs/features/trace-protocol.feature",
      "docs/features/trace-sdk.feature",
      "docs/features/trace-replacement.feature"
    ],
    strict: true
end

# Show known metadata during development. Tests deliberately exercise malformed
# metadata that the console formatter cannot print; retain its default there.
# This configuration is not packaged for consumers.
if config_env() == :dev do
  config :logger, :default_formatter,
    metadata: [:domain, :customer, :attempt, :otel_trace_id, :otel_span_id]
end
