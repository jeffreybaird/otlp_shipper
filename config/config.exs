import Config

# The SDK exists only in tests to prove real span correlation. Never export traces.
if config_env() == :test do
  config :opentelemetry, traces_exporter: :none

  config :cucumberex, :config,
    paths: ["docs/features/cucumberex.feature"],
    strict: true
end

# Show known metadata during development. Tests deliberately exercise malformed
# metadata that the console formatter cannot print; retain its default there.
# This configuration is not packaged for consumers.
if config_env() == :dev do
  config :logger, :default_formatter,
    metadata: [:domain, :customer, :attempt, :otel_trace_id, :otel_span_id]
end
