defmodule OtlpShipper.LogRecordTest do
  use ExUnit.Case, async: true
  alias OtlpShipper.LogRecord
  doctest LogRecord

  test "preserves all recipe severity mappings" do
    levels = [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency, :unknown]
    assert Enum.map(levels, &LogRecord.severity/1) == [5, 9, 10, 13, 17, 18, 19, 21, 0]
  end

  test "reports, formatting, chardata and metadata become bounded records" do
    for report <- [%{ready: true}, [ready: true]] do
      assert {:ok, record} = LogRecord.new(event({:report, report}, %{pid: self(), count: 2}))

      assert record.body == %{
               value:
                 {:kvlist_value,
                  %{values: [%{key: "ready", value: %{value: {:bool_value, true}}}]}}
             }

      assert record.attributes == [%{key: "count", value: %{value: {:int_value, 2}}}]
      assert record.dropped_attributes_count == 0
    end

    assert {:ok, %{body: %{value: {:string_value, "hello 42"}}}} =
             LogRecord.new(event({~c"hello ~p", [42]}))

    assert {:ok, %{body: %{value: {:string_value, "héllo"}}}} =
             LogRecord.new(event({:string, [~c"hé", "llo"]}))

    assert {:ok, %{body: %{value: {:string_value, "[invalid chardata]"}}}} =
             LogRecord.new(event({:string, [0xD800]}))

    assert {:error, :invalid_log_event} = LogRecord.new(event({~c"~p", []}))
    assert {:error, :invalid_log_event} = LogRecord.new(%{})
  end

  test "bounds encoded values, preserves UTF-8 and counts omitted attributes only" do
    {:ok, limits} =
      LogRecord.limits(max_body_bytes: 64, max_attribute_bytes: 32, max_attributes: 2)

    meta = %{a: String.duplicate("é", 200), b: true, c: 3, pid: self()}
    {:ok, record} = LogRecord.new(event({:string, String.duplicate("é", 10_000)}, meta), limits)
    assert byte_size(encode(record.body)) <= 64
    assert {:string_value, text} = record.body.value
    assert String.valid?(text)
    assert :binary.referenced_byte_size(text) == byte_size(text)
    assert length(record.attributes) == 2
    assert record.dropped_attributes_count == 1
    assert Enum.all?(record.attributes, &(byte_size(encode(&1.value)) <= 32))

    {:ok, record} =
      LogRecord.new(
        event({:report, Map.new(1..1000, &{&1, %{nested: Enum.to_list(1..100)}})}, %{
          String.duplicate("x", 33) => 1
        }),
        limits
      )

    assert byte_size(encode(record.body)) <= 64
    assert record.attributes == []
    assert record.dropped_attributes_count == 1
  end

  test "nested values and invalid binaries are bounded" do
    nested = Enum.reduce(1..30, :end, fn _, acc -> %{next: acc} end)

    for value <- [nested, Enum.to_list(1..1000), <<255, 0>>, self(), String.duplicate("a", 5000)] do
      {:ok, record} = LogRecord.new(event({:report, %{value: value}}))
      assert byte_size(encode(record.body)) <= 16_384
    end
  end

  test "validates limits including zero attributes" do
    for opts <- [
          [max_body_bytes: 31],
          [max_attribute_bytes: -1],
          [max_attributes: -1],
          [nope: 1],
          [max_attributes: "2"],
          :invalid
        ] do
      assert {:error, :invalid_log_limits} = LogRecord.limits(opts)
    end

    {:ok, limits} = LogRecord.limits(max_attributes: 0)

    assert {:ok, %{attributes: [], dropped_attributes_count: 1}} =
             LogRecord.new(event({:string, "x"}, %{a: 1}), limits)
  end

  test "correlation validates widths, prefers metadata and clears absent or malformed IDs" do
    ctx = %{otel_trace_id: 1, otel_span_id: 2, otel_trace_flags: 1}

    metadata = %{
      otel_trace_id: String.duplicate("a", 32),
      otel_span_id: String.duplicate("B", 16),
      otel_trace_flags: "01"
    }

    {:ok, record} = LogRecord.new(event({:string, "x"}, metadata), limits(), ctx, 123)
    assert record.trace_id == :binary.copy(<<170>>, 16)
    assert record.span_id == :binary.copy(<<187>>, 8)
    assert record.flags == 1
    assert record.observed_time_unix_nano == 123
    assert record.attributes == []
    {:ok, record} = LogRecord.new(event({:string, "x"}), limits(), ctx)
    assert record.trace_id == <<1::128>>
    assert record.span_id == <<2::64>>

    for bad <- [nil, -1, 0, Integer.pow(2, 128), "xyz", String.duplicate("z", 32), <<0::128>>] do
      {:ok, record} = LogRecord.new(event({:string, "x"}, %{otel_trace_id: bad, otel_span_id: 2}))
      assert {record.trace_id, record.span_id, record.flags} == {"", "", 0}
    end

    {:ok, record} =
      LogRecord.new(
        event({:string, "x"}, %{otel_trace_id: <<1::128>>, otel_span_id: <<2::64>>, time: -1})
      )

    assert record.time_unix_nano == 0
    assert record.flags == 0
  end

  test "chardata stops traversing once the byte budget is exhausted" do
    {:ok, limits} = LogRecord.limits(max_body_bytes: 32)
    input = [String.duplicate("x", 1000), {:must_not_visit, :truncated_tail}]
    assert {:ok, record} = LogRecord.new(event({:string, input}), limits)
    assert record.body.value == {:string_value, String.duplicate("x", 24)}
  end

  test "structured reports support structs and keep normalized keys unique" do
    assert {:ok, record} = LogRecord.new(event({:report, URI.parse("https://example.test")}))
    assert {:kvlist_value, %{values: values}} = record.body.value
    assert Enum.find(values, &(&1.key == "host")).value.value == {:string_value, "example.test"}
    assert {:ok, record} = LogRecord.new(event({:report, [{:a, 1}, {"a", 2}]}))
    assert {:kvlist_value, %{values: [%{key: "a"}]}} = record.body.value
  end

  defp event(msg, meta \\ %{}), do: %{level: :info, msg: msg, meta: meta}
  defp limits, do: elem(LogRecord.limits(), 1)

  defp encode(value),
    do: :otlp_shipper_logs_service.encode_msg(value, :"opentelemetry.proto.common.v1.AnyValue")
end
