defmodule OtlpShipper.TraceReplacementCaptureTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias OtlpShipper.Conformance

  @capture File.read!(
             Path.expand("../fixtures/conformance/collector-three-signals-0.160.0.txt", __DIR__)
           )

  test "TRP-01 pinned Collector capture contains valid logs, metrics, spans, and correlation" do
    assert Conformance.verify(@capture) == :ok
    assert Conformance.verify_traces(@capture) == :ok
  end
end
