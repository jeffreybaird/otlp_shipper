defmodule OtlpShipper do
  @moduledoc """
  Bounded OTLP/HTTP shipping for Elixir.

  Phase 0 provides `OtlpShipper.Config`, `OtlpShipper.Resource`,
  `OtlpShipper.Value`, `OtlpShipper.Encoder`, `OtlpShipper.Transport`, and
  `OtlpShipper.Buffer`. Logger handling and metric aggregation follow in later
  phases. Core interfaces are pre-release and may change before publication.

  Resolve configuration before starting a component:

      iex> {:ok, config} = OtlpShipper.Config.new(:logs, service_name: "checkout")
      iex> config.endpoint
      "http://localhost:4318/v1/logs"
  """
end
