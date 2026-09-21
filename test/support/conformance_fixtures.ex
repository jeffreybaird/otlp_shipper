defmodule OtlpShipper.ConformanceFixtures do
  @moduledoc false

  @doc false
  def current_scope_version(output) do
    version = :otlp_shipper |> Application.spec(:vsn) |> to_string()

    # Historical Collector captures remain untouched on disk. Only their shipper
    # scope version is adapted for current package validation; other instrumentation
    # identities and every payload field retain the recorded values.
    Regex.replace(
      ~r/^(InstrumentationScope otlp_shipper )[^\r\n]+$/m,
      output,
      fn _, prefix -> prefix <> version end
    )
  end
end
