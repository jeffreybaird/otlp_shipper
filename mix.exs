Code.require_file("mix/compile_otlp_protos.exs", __DIR__)

defmodule OtlpShipper.MixProject do
  use Mix.Project

  @version "0.1.1"

  def project do
    [
      app: :otlp_shipper,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      compilers: [:otlp_protos] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Bounded OTLP/HTTP log shipping and Telemetry.Metrics reporting for Elixir.",
      source_url: "https://github.com/jeffreybaird/otlp_shipper",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/jeffreybaird/otlp_shipper"},
        files: ~w(lib mix priv mix.exs .formatter.exs README.md LICENSE CHANGELOG.md)
      ],
      dialyzer: [plt_add_apps: [:mix]],
      docs: [main: "readme", extras: ["README.md", "CHANGELOG.md"]]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:finch, "~> 0.20"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.1"},
      {:opentelemetry_api, "~> 1.3", optional: true},
      {:gpb, "~> 4.21 and >= 4.21.7", runtime: false},
      {:bandit, "~> 1.8", only: :test},
      {:cucumberex, "~> 0.2.1", only: :test},
      {:opentelemetry, "~> 1.7", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end
end
