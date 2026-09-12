defmodule OtlpShipper.TestLogCapture do
  @moduledoc false
  def log(%{meta: %{domain: [:otlp_shipper]}} = event, %{config: %{owner: owner}}),
    do: send(owner, {:diagnostic, event})

  def log(_, _), do: :ok
end
