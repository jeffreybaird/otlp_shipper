import Config

# The SDK exists only in tests to prove real span correlation. Never export traces.
if config_env() == :test do
  config :opentelemetry, traces_exporter: :none
end
