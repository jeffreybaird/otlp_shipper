defmodule OtlpShipper.Metrics.DefinitionTest do
  use ExUnit.Case, async: true
  import Telemetry.Metrics
  alias OtlpShipper.Metrics.Definition
  doctest Definition

  test "validates supported definitions, units and bounds" do
    assert {:ok, defs} =
             Definition.new([
               counter("web.count"),
               sum("web.bytes", unit: :byte),
               last_value("web.active"),
               distribution("web.duration", reporter_options: [buckets: [-1, 0, 10]])
             ])

    assert Enum.map(defs, & &1.kind) == [:counter, :sum, :gauge, :histogram]
    assert Enum.at(defs, 1).unit == "By"

    for bounds <- [nil, [1, 1], [2, 1], [:bad], Enum.to_list(1..257)] do
      assert {:error, :invalid_histogram_buckets} =
               Definition.new([distribution("web.time", reporter_options: [buckets: bounds])])
    end

    assert {:ok, [_]} =
             Definition.new([distribution("web.time", reporter_options: [buckets: []])])

    assert {:error, :unsupported_metric, :use_distribution} =
             Definition.new([summary("web.time")])

    assert {:error, :duplicate_metric_name} =
             Definition.new([counter("web.count"), sum("web.count")])

    assert {:error, :unsupported_unit} = Definition.new([sum("web.time", unit: :native)])

    assert {:error, :unsupported_reporter_options} =
             Definition.new([sum("web.time", reporter_options: [other: true])])

    assert {:error, :recursive_metric_event} =
             Definition.new([counter("otlp_shipper.dropped.count")])

    assert {:error, :invalid_metrics} = Definition.new(:invalid)
    assert {:error, :invalid_metric} = Definition.new([%{}])
    assert {:error, :invalid_metric} = Definition.new([%{counter("web.count") | keep: :invalid}])

    for {unit, label} <- [
          unit: "1",
          second: "s",
          millisecond: "ms",
          microsecond: "us",
          nanosecond: "ns",
          byte: "By",
          kilobyte: "kBy",
          megabyte: "MBy",
          percent: "%"
        ] do
      assert Definition.unit(unit) == {:ok, label}
    end
  end

  test "converts measurement once and applies keep before transformations" do
    {:ok, [defn]} =
      Definition.new([
        sum("web.time",
          unit: {:native, :millisecond},
          tags: [:route],
          tag_values: &%{route: String.upcase(&1.route)}
        )
      ])

    native = System.convert_time_unit(2, :millisecond, :native)

    assert {:ok, [%{key: "route", value: %{value: {:string_value, "HOME"}}}], value} =
             Definition.sample(defn, %{time: native}, %{route: "home"})

    assert value == 2

    {:ok, [defn]} =
      Definition.new([
        sum("web.time", keep: fn _, _ -> false end, measurement: fn _ -> raise "not called" end)
      ])

    assert :skip = Definition.sample(defn, %{}, %{})

    {:ok, [defn]} =
      Definition.new([
        sum("web.time",
          measurement: fn m, meta -> m.x + meta.y end,
          tags: fn meta -> %{y: meta.y} end
        )
      ])

    assert {:ok, [%{key: "y"}], 5} = Definition.sample(defn, %{x: 2}, %{y: 3})
  end

  test "missing measurements, counter values and callback failures are isolated" do
    {:ok, [defn]} = Definition.new([counter("web.count")])
    assert :skip = Definition.sample(defn, %{}, %{})
    assert {:ok, [], 1} = Definition.sample(defn, %{count: :anything}, %{})
    {:ok, [defn]} = Definition.new([sum("web.value")])

    for bad <- ["oops", Integer.pow(2, 64)] do
      assert {:error, :invalid_measurement} = Definition.sample(defn, %{value: bad}, %{})
    end

    for fun <- [fn _ -> raise "secret" end, fn _ -> throw(:secret) end, fn _ -> exit(:secret) end] do
      {:ok, [defn]} = Definition.new([sum("web.value", measurement: fun)])
      assert {:error, :callback_failed} = Definition.sample(defn, %{}, %{})
    end

    {:ok, [defn]} = Definition.new([sum("web.value", keep: fn _ -> :bad end)])
    assert {:error, :invalid_keep_result} = Definition.sample(defn, %{}, %{})
  end

  test "tag shape and size are bounded without merging truncated series" do
    for tags <- [
          %{x: %{nested: true}},
          %{x: <<255>>},
          %{1 => "bad"},
          Map.new(1..33, &{to_string(&1), &1}),
          %{x: String.duplicate("x", 5000)},
          :bad
        ] do
      {:ok, [defn]} = Definition.new([sum("web.value", tags: fn _ -> tags end)])
      assert {:error, :invalid_tags} = Definition.sample(defn, %{value: 1}, %{})
    end

    {:ok, [defn]} = Definition.new([sum("web.value", tags: [:missing])])
    assert {:ok, [], 1} = Definition.sample(defn, %{value: 1}, %{})
  end

  test "histogram bounds must remain distinct after protobuf double conversion" do
    assert {:error, :invalid_histogram_buckets} =
             Definition.new([
               distribution("test.precision",
                 reporter_options: [buckets: [9_007_199_254_740_992, 9_007_199_254_740_993]]
               )
             ])
  end

  test "small tag slices do not retain huge source binaries" do
    source = :binary.copy("x", 100_000)
    slice = binary_part(source, 10, 100)
    assert :binary.referenced_byte_size(slice) > byte_size(slice)
    {:ok, [definition]} = Definition.new([sum("test.value", tags: fn _ -> %{slice => slice} end)])

    assert {:ok, [%{key: key, value: %{value: {:string_value, value}}}], 1} =
             Definition.sample(definition, %{value: 1}, %{})

    assert :binary.referenced_byte_size(key) == byte_size(key)
    assert :binary.referenced_byte_size(value) == byte_size(value)
  end
end
