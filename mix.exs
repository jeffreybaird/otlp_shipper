Code.require_file("mix/compile_otlp_protos.exs", __DIR__)

defmodule OtlpShipper.MixProject do
  use Mix.Project

  @version "0.2.2"

  def project do
    [
      app: :otlp_shipper,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      compilers: [:otlp_protos] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Bounded OTLP/HTTP logs, metrics, and SDK-compatible trace export for Elixir.",
      source_url: "https://github.com/jeffreybaird/otlp_shipper",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/jeffreybaird/otlp_shipper"},
        files:
          ~w(lib mix priv mix.exs .formatter.exs README.md LICENSE CHANGELOG.md docs/migration.md)
      ],
      dialyzer: [plt_add_apps: [:mix, :opentelemetry]],
      docs: [main: "readme", extras: ["README.md", "CHANGELOG.md", "docs/migration.md"]]
    ]
  end

  # The test project explicitly owns SDK startup; production consumers choose theirs.
  def application do
    applications = if Mix.env() == :test, do: [:logger, :opentelemetry], else: [:logger]
    [extra_applications: applications]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:finch, "~> 0.20"},
      {:mint, "~> 1.10 and >= 1.10.2"},
      {:hpax, "~> 1.0 and >= 1.0.4"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.1"},
      {:opentelemetry_api, "~> 1.3", optional: true},
      {:gpb, "~> 4.21 and >= 4.21.7", runtime: false},
      {:bandit, "~> 1.8", only: :test},
      {:cucumberex, "~> 0.2.1", only: :test},
      {:opentelemetry, "~> 1.7", optional: true, runtime: false},
      {:opentelemetry_finch, "== 0.2.0", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end
end
