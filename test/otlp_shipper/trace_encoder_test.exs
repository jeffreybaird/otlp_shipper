defmodule OtlpShipper.TraceEncoderTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias OtlpShipper.{Encoder, TraceFixtures, TraceRecord}

  test "TPC-03 generated envelopes preserve authoritative resource and original scopes" do
    first = TraceFixtures.span()

    second =
      TraceFixtures.span(%{
        span_id: 3,
        scope: %{name: "other", version: "2", schema_url: "https://other"}
      })

    assert {:ok, first_record} = TraceRecord.convert(first, TraceFixtures.offset())
    assert {:ok, second_record} = TraceRecord.convert(second, TraceFixtures.offset())
    resource = TraceFixtures.resource(%{attributes: %{}, dropped_attributes_count: 2})
    assert {:ok, body} = Encoder.encode(:traces, [first_record, second_record], resource)
    assert %{resource_spans: [envelope]} = TraceFixtures.decode(body)
    assert envelope.resource.attributes == []
    assert envelope.resource.dropped_attributes_count == 2
    assert envelope.schema_url == resource.schema_url
    scopes = Map.new(envelope.scope_spans, &{&1.scope.name, &1})
    assert Map.keys(scopes) |> Enum.sort() == ["example", "other"]
    assert scopes["example"].scope.version == "1.0"
    assert scopes["example"].schema_url == "https://schema/scope"
    assert scopes["other"].scope.version == "2"
    assert scopes["other"].schema_url == "https://other"
    assert Enum.map(scopes["example"].spans, & &1.span_id) == [<<2::64>>]
    assert Enum.map(scopes["other"].spans, & &1.span_id) == [<<3::64>>]
  end

  test "TPC-03 same name with different schema stays in separate scope envelopes" do
    for_schema = fn schema ->
      input = TraceFixtures.span(%{scope: %{name: "same", version: "1", schema_url: schema}})
      assert {:ok, converted} = TraceRecord.convert(input, TraceFixtures.offset())
      converted
    end

    assert {:ok, body} =
             Encoder.encode(:traces, Enum.map(["a", "b"], for_schema), TraceFixtures.resource())

    [envelope] = TraceFixtures.decode(body).resource_spans
    assert Enum.map(envelope.scope_spans, & &1.schema_url) |> Enum.sort() == ["a", "b"]
  end

  test "TPC-03 invalid resource and payload receive distinct errors without default identity" do
    assert {:ok, converted} = TraceRecord.convert(TraceFixtures.span(), TraceFixtures.offset())

    for resource <- [
          nil,
          %{},
          %{attributes: %{bad: self()}},
          %{attributes: %{}, dropped_attributes_count: -1}
        ] do
      assert Encoder.encode(:traces, [converted], resource) == {:error, :invalid_resource}
    end

    assert Encoder.encode(:traces, [%{invalid: :record}], TraceFixtures.resource()) ==
             {:error, :invalid_payload}
  end
end
