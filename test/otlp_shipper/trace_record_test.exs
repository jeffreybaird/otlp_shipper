defmodule OtlpShipper.TraceRecordTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias OtlpShipper.{TraceFixtures, TraceRecord}

  test "TPC-02 converts SDK-independent identity and native timestamps faithfully" do
    event = %{
      name: "event",
      time: TraceFixtures.native(5),
      attributes: %{"answer" => 42},
      dropped_attributes_count: 2
    }

    link = %{
      trace_id: 3,
      span_id: 4,
      tracestate: [{"vendor", "linked"}],
      attributes: %{"linked" => true},
      dropped_attributes_count: 3
    }

    input =
      TraceFixtures.span(%{
        parent_span_id: 5,
        parent_span_is_remote: true,
        kind: :client,
        status: %{code: :error, message: "failure"},
        dropped_attributes_count: 4,
        dropped_events_count: 5,
        dropped_links_count: 6,
        events: [event],
        links: [link]
      })

    assert {:ok, converted} = TraceRecord.convert(input, TraceFixtures.offset())
    span = converted.span
    assert converted.scope == input.scope
    assert span.trace_id == <<1::128>>
    assert span.span_id == <<2::64>>
    assert span.parent_span_id == <<5::64>>
    assert span.trace_state == "vendor=value"
    assert span.start_time_unix_nano == 1_700_000_000_000_000_000
    assert span.end_time_unix_nano == 1_700_000_000_010_000_000
    assert span.kind == :SPAN_KIND_CLIENT
    assert span.status == %{code: :STATUS_CODE_ERROR, message: "failure"}
    assert span.flags == 769
    assert span.dropped_attributes_count == 4
    assert span.dropped_events_count == 5
    assert span.dropped_links_count == 6
    assert [encoded_event] = span.events
    assert encoded_event.name == "event"
    assert encoded_event.time_unix_nano == 1_700_000_000_005_000_000
    assert encoded_event.dropped_attributes_count == 2
    assert [encoded_link] = span.links
    assert encoded_link.trace_id == <<3::128>>
    assert encoded_link.span_id == <<4::64>>
    assert encoded_link.trace_state == "vendor=linked"
    assert encoded_link.dropped_attributes_count == 3
    assert Map.get(encoded_link, :flags, 0) == 0
  end

  test "TPC-02 root span and strict supported attribute values retain their types" do
    attributes = %{
      string: "value",
      atom: :ready,
      boolean: true,
      integer: -9_223_372_036_854_775_808,
      maximum: 9_223_372_036_854_775_807,
      float: 1.5,
      list: [1, 2],
      tuple: {"a", "b"}
    }

    assert {:ok, converted} =
             TraceRecord.convert(
               TraceFixtures.span(%{attributes: attributes}),
               TraceFixtures.offset()
             )

    values = Map.new(converted.span.attributes, &{&1.key, &1.value.value})
    assert converted.span.parent_span_id == ""
    assert values["string"] == {:string_value, "value"}
    assert values["atom"] == {:string_value, "ready"}
    assert values["boolean"] == {:bool_value, true}
    assert values["integer"] == {:int_value, -9_223_372_036_854_775_808}
    assert values["maximum"] == {:int_value, 9_223_372_036_854_775_807}
    assert values["float"] == {:double_value, 1.5}

    assert values["list"] ==
             {:array_value, %{values: [%{value: {:int_value, 1}}, %{value: {:int_value, 2}}]}}

    assert values["tuple"] ==
             {:array_value,
              %{values: [%{value: {:string_value, "a"}}, %{value: {:string_value, "b"}}]}}
  end

  test "TPC-02 malformed data returns field-specific errors without stringification" do
    cases = [
      {:trace_id, 0},
      {:trace_id, Integer.pow(2, 128)},
      {:span_id, 0},
      {:span_id, Integer.pow(2, 64)},
      {:parent_span_id, 0},
      {:name, <<255>>},
      {:kind, :invented},
      {:trace_flags, 256},
      {:parent_span_is_remote, :unknown},
      {:end_time, -1},
      {:attributes, %{bad: self()}},
      {:attributes, %{bad: nil}},
      {:attributes, %{bad: [1, "mixed"]}},
      {:attributes, %{bad: [[1]]}},
      {:attributes, %{:same => 1, "same" => 2}},
      {:attributes, %{bad: 9_223_372_036_854_775_808}},
      {:dropped_attributes_count, -1},
      {:dropped_attributes_count, 4_294_967_296},
      {:events, [%{name: "missing fields"}]},
      {:links, [%{trace_id: 0}]},
      {:scope, %{name: <<255>>, version: "", schema_url: ""}}
    ]

    for {field, invalid} <- cases do
      assert TraceRecord.convert(TraceFixtures.span(%{field => invalid}), TraceFixtures.offset()) ==
               {:error, :invalid_span, field}
    end
  end

  test "TPC-02 flags distinguish unknown and known remote state without inventing link flags" do
    for {remote, flags} <- [{nil, 1}, {false, 257}, {true, 769}] do
      assert {:ok, converted} =
               TraceRecord.convert(
                 TraceFixtures.span(%{parent_span_is_remote: remote}),
                 TraceFixtures.offset()
               )

      assert converted.span.flags == flags
    end
  end

  test "TPC-02 epoch timestamps and dropped counts respect protobuf integer boundaries" do
    assert {:ok, converted} =
             TraceRecord.convert(
               TraceFixtures.span(%{dropped_attributes_count: 4_294_967_295}),
               TraceFixtures.offset()
             )

    assert converted.span.dropped_attributes_count == 4_294_967_295
    assert TraceRecord.convert(TraceFixtures.span(), -1) == {:error, :invalid_span, :start_time}

    offset = System.convert_time_unit(Integer.pow(2, 64), :nanosecond, :native)

    assert TraceRecord.convert(TraceFixtures.span(), offset) ==
             {:error, :invalid_span, :start_time}
  end

  test "TPC-02 exact generated span bytes define the individual span limit" do
    input = TraceFixtures.span()
    assert {:ok, converted} = TraceRecord.convert(input, TraceFixtures.offset())

    bytes =
      :otlp_shipper_trace_service.encode_msg(converted.span, TraceFixtures.span_type(), [:verify])

    assert {:ok, _} = TraceRecord.convert(input, TraceFixtures.offset(), byte_size(bytes))

    assert TraceRecord.convert(input, TraceFixtures.offset(), byte_size(bytes) - 1) ==
             {:error, :span_too_large}

    assert TraceRecord.convert(
             TraceFixtures.span(%{name: String.duplicate("x", 100_000)}),
             TraceFixtures.offset(),
             128
           ) == {:error, :span_too_large}
  end
end
