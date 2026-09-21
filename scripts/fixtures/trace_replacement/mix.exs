defmodule ReplacementConsumer.MixProject do
  use Mix.Project

  # The SDK/API pair is identical in minimum/current modes; only shared deps vary.
  def project do
    [
      app: :replacement_consumer,
      version: "0.0.0",
      elixir: "~> 1.19",
      config_path: "config.exs",
      deps:
        [
          {:otlp_shipper, path: System.fetch_env!("OTLP_REPLACEMENT_PACKAGE")},
          {:opentelemetry, "== 1.7.0", runtime: false},
          {:opentelemetry_api, "== 1.5.0"},
          {:opentelemetry_finch, "== 0.2.0"}
        ] ++ minimum_dependencies()
    ]
  end

  # The consumer owns the included SDK supervisor and its transport dependency.
  def application do
    [extra_applications: [:logger], included_applications: [:opentelemetry]]
  end

  # Match the package's declared minimum versions without changing its dependency tree.
  defp minimum_dependencies do
    case System.fetch_env!("OTLP_SMOKE_DEPENDENCY_SET") do
      "default" ->
        []

      "minimum" ->
        [
          {:finch, "== 0.20.0"},
          {:telemetry, "== 1.3.0"},
          {:telemetry_metrics, "== 1.1.0"},
          {:gpb, "== 4.21.7", runtime: false}
        ]
    end
  end
end
