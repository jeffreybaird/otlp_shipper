defmodule OtlpShipper.Metrics.AggregationTest do
  use ExUnit.Case, async: true
  alias OtlpShipper.Metrics.{Aggregation, Definition}
  import Telemetry.Metrics
  doctest Aggregation

  test "sum and gauge keep exact numeric kinds and last observation" do
    {:ok, state} = Aggregation.add(:sum, nil, 5, [], 0)
    assert {:ok, %{value: 3.5, negative: true}} = Aggregation.add(:sum, state, -1.5, [], 0)
    {:ok, state} = Aggregation.add(:gauge, nil, 1, [], 10)
    assert {:ok, %{value: 2, observed: 20}} = Aggregation.add(:gauge, state, 2, [], 20)
    {:ok, [definition]} = Definition.new([last_value("web.gauge")])
    metric = Aggregation.metric(definition, %{value: 2.5, observed: 20}, [], 1, 30, true)
    assert {:gauge, %{data_points: [point]}} = metric.data
    assert point.value == {:as_double, 2.5}
    assert point.time_unix_nano == 20
    refute Map.has_key?(point, :start_time_unix_nano)
  end

  test "histogram boundaries are inclusive and negative observations omit sum" do
    bounds = [0.0, 5.0, 10.0]

    state =
      Enum.reduce([-1, 0, 5, 7, 10, 11], nil, fn value, state ->
        {:ok, next} = Aggregation.add(:histogram, state, value, bounds, 0)
        next
      end)

    assert state.buckets == {2, 1, 2, 1}
    assert state.count == 6

    {:ok, [definition]} =
      Definition.new([distribution("web.hist", reporter_options: [buckets: bounds])])

    {:histogram, %{data_points: [point]}} =
      Aggregation.metric(definition, state, [], 10, 20, true).data

    assert point.min == -1.0
    assert point.max == 11.0
    refute Map.has_key?(point, :sum)
    {:ok, positive} = Aggregation.add(:histogram, nil, 2, bounds, 0)

    {:histogram, %{data_points: [point]}} =
      Aggregation.metric(definition, positive, [], 10, 20, true).data

    assert point.sum == 2.0
  end

  test "overflow rejects the observation" do
    assert {:error, :numeric_overflow} =
             Aggregation.add(:sum, %{value: 9_223_372_036_854_775_807, negative: false}, 1, [], 0)

    assert {:error, :numeric_overflow} =
             Aggregation.add(:sum, %{value: 1.0e308, negative: false}, 1.0e308, [], 0)
  end
end
