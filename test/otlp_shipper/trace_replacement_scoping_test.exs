defmodule OtlpShipper.TraceReplacementScopingTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias OtlpShipper.Conformance

  @fixture File.read!(
             Path.expand("../fixtures/conformance/collector-traces-0.160.0.txt", __DIR__)
           )

  test "TRP-02 an event attribute cannot substitute for the required span attribute" do
    misplaced =
      @fixture
      |> String.replace("     -> conformance.span: Bool(true)\n", "")
      |> String.replace(
        "          -> conformance: Bool(true)",
        "          -> conformance: Bool(true)\n          -> conformance.span: Bool(true)"
      )

    assert Conformance.verify_traces(misplaced) == {:error, :collector_trace_output_mismatch}
  end

  test "TRP-02 a link attribute cannot substitute for the required event attribute" do
    misplaced =
      String.replace(@fixture, "          -> conformance: Bool(true)", """
      Links:
      SpanLink #0
           -> Trace ID: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
           -> ID: aaaaaaaaaaaaaaaa
           -> Attributes::
                -> conformance: Bool(true)
      """)

    assert Conformance.verify_traces(misplaced) == {:error, :collector_trace_output_mismatch}
  end

  test "TRP-01 the remote span retains the incoming remote trace identity" do
    changed_trace =
      String.replace(
        @fixture,
        "00000000000000000000000000000043",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      )

    assert Conformance.verify_traces(changed_trace) == {:error, :collector_trace_output_mismatch}
  end
end
