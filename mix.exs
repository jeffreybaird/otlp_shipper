defmodule OtlpShipper.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :otlp_shipper,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Everything below is metadata only — it costs nothing until there is
      # something to publish, and having it here means publishing is a
      # `mix hex.publish` away rather than a mix.exs rewrite.
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"}
    ]
  end

  defp description do
    "TODO: one sentence describing otlp_shipper."
  end

  # Fill in :licenses and :links, then `mix hex.publish`.
  defp package do
    [
      licenses: [],
      links: %{}
    ]
  end
end
