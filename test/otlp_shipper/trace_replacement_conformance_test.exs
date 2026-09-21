defmodule OtlpShipper.TraceReplacementConformanceTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias OtlpShipper.{Conformance, ConformanceFixtures}

  @fixture File.read!(
             Path.expand("../fixtures/conformance/collector-traces-0.160.0.txt", __DIR__)
           )
  @old_fixture File.read!(Path.expand("../fixtures/conformance/collector-0.160.0.txt", __DIR__))

  test "TRP-01 trace verification recognizes exact span relationships and log correlation" do
    assert Conformance.verify_traces(@fixture) == :ok
    assert Conformance.verify(ConformanceFixtures.current_scope_version(@old_fixture)) == :ok
    assert Conformance.verify_traces(@old_fixture) == {:error, :collector_trace_output_mismatch}
    assert Conformance.verify_traces("") == {:error, :collector_trace_output_mismatch}
  end

  test "TRP-02 incorrect identity, scope, resource, event, or status is rejected" do
    for {before, replacement} <- [
          {"service.name: Str(otlp-shipper-conformance)", "service.name: Str(wrong)"},
          {"Resource SchemaURL: https://otlp-shipper.dev/conformance/resource",
           "Resource SchemaURL: https://wrong"},
          {"ScopeSpans SchemaURL: https://otlp-shipper.dev/conformance/scope",
           "ScopeSpans SchemaURL: https://wrong"},
          {"InstrumentationScope conformance.sdk 1.0", "InstrumentationScope wrong 1.0"},
          {"Name: conformance-event", "Name: other-event"},
          {"Status code    : Error", "Status code    : Ok"},
          {"Status message : synthetic failure", "Status message : wrong"},
          {"conformance.span: Bool(true)", "conformance.span: Bool(false)"},
          {"Parent ID      : 0000000000000042", "Parent ID      : 0000000000000099"}
        ] do
      mutated = String.replace(@fixture, before, replacement)
      refute mutated == @fixture
      assert Conformance.verify_traces(mutated) == {:error, :collector_trace_output_mismatch}
    end

    wrong_log = Regex.replace(~r/^Span ID: [0-9a-f]+$/m, @fixture, "Span ID: 9999999999999999")
    assert Conformance.verify_traces(wrong_log) == {:error, :collector_trace_output_mismatch}
  end

  test "TRP-02 child trace and parent IDs must refer to the actual root span" do
    for {field, value} <- [
          {"Trace ID", "99999999999999999999999999999999"},
          {"Parent ID", "9999999999999999"},
          {"ID", "0000000000000000"}
        ] do
      changed =
        change_span(@fixture, "otlp-shipper-conformance-child", fn block ->
          Regex.replace(
            Regex.compile!("(?m)^(\\s*#{field}\\s*:) [^\\n]*$"),
            block,
            "\\1 #{value}"
          )
        end)

      refute changed == @fixture
      assert Conformance.verify_traces(changed) == {:error, :collector_trace_output_mismatch}
    end
  end

  test "TRP-02 correct values in unrelated records cannot rescue a wrong child span" do
    changed =
      change_span(@fixture, "otlp-shipper-conformance-child", fn block ->
        String.replace(block, "Status code    : Error", "Status code    : Unset")
      end)

    decoy = changed <> "\nStatus code    : Error\nStatus message : synthetic failure\n"
    assert Conformance.verify_traces(decoy) == {:error, :collector_trace_output_mismatch}

    changed_event =
      change_span(@fixture, "otlp-shipper-conformance-child", fn block ->
        String.replace(block, "Name: conformance-event", "Name: wrong-event")
      end)

    assert Conformance.verify_traces(changed_event <> "\nName: conformance-event\n") ==
             {:error, :collector_trace_output_mismatch}
  end

  test "TRP-02 missing, duplicate, or prefix-matching span names do not pass" do
    for output <- [
          change_span(@fixture, "otlp-shipper-conformance-child", fn _ -> "" end),
          @fixture <> child_block(@fixture),
          String.replace(
            @fixture,
            "otlp-shipper-conformance-child",
            "otlp-shipper-conformance-child-extra"
          )
        ] do
      assert Conformance.verify_traces(output) == {:error, :collector_trace_output_mismatch}
    end
  end

  # Mutate the named record without depending on its emitted index or ID values.
  defp change_span(output, name, change) do
    output
    |> then(&Regex.split(~r/(?=^Span #\d+\n)/m, &1))
    |> Enum.map_join(fn block ->
      if String.contains?(block, ": " <> name <> "\n"), do: change.(block), else: block
    end)
  end

  # Preserve the complete emitted record for the duplicate-name rejection case.
  defp child_block(output) do
    output
    |> then(&Regex.split(~r/(?=^Span #\d+\n)/m, &1))
    |> Enum.find(&String.contains?(&1, ": otlp-shipper-conformance-child\n"))
  end
end
