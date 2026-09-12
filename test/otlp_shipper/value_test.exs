defmodule OtlpShipper.ValueTest do
  use ExUnit.Case, async: true
  alias OtlpShipper.Value
  doctest Value

  test "preserves scalar types and signed integer boundaries" do
    for {input, type, expected} <- [
          {true, :bool_value, true},
          {false, :bool_value, false},
          {:ok, :string_value, "ok"},
          {nil, :string_value, "nil"},
          {1, :int_value, 1},
          {-9_223_372_036_854_775_808, :int_value, -9_223_372_036_854_775_808},
          {9_223_372_036_854_775_807, :int_value, 9_223_372_036_854_775_807},
          {9_223_372_036_854_775_808, :string_value, "9223372036854775808"},
          {2.5, :double_value, 2.5},
          {"hi", :string_value, "hi"},
          {<<255>>, :bytes_value, <<255>>},
          {{:ok, 1}, :string_value, "{:ok, 1}"}
        ] do
      assert Value.encode(input) == %{value: {type, expected}}
    end
  end

  test "normalizes keys deterministically with no duplicate OTLP attributes" do
    attrs = Value.attributes(%{:same => 1, "same" => 2, 3 => "number", <<255>> => "bytes"})

    assert [%{key: "3"}, %{key: "<<255>>"}, %{key: "same", value: %{value: {:int_value, 2}}}] =
             attrs

    assert Value.encode([]) == %{value: {:array_value, %{values: []}}}
    assert Value.encode(%{}) == %{value: {:kvlist_value, %{values: []}}}
  end

  test "all value types survive generated protobuf encoding" do
    values = ["hi", <<255>>, true, 1, 1.5, [2, "a"], %{healthy: true}]

    for value <- values do
      message = Value.encode(value)
      type = :"opentelemetry.proto.common.v1.AnyValue"
      binary = :otlp_shipper_logs_service.encode_msg(message, type)
      assert :otlp_shipper_logs_service.decode_msg(binary, type) == message
    end
  end
end
