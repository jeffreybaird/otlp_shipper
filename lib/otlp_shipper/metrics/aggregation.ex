defmodule OtlpShipper.Metrics.Aggregation do
  @moduledoc """
  Pure per-series aggregation and OTLP data-point construction.

  Histogram buckets include their upper bound and an implicit positive-infinity
  bucket. Negative observations omit histogram sum for OpenMetrics compatibility.
  Gauges emit the last observed value and its observation time, with no temporality
  or start time. Sums/histograms use explicit interval start and end timestamps.
  """

  @doc """
  Adds one observation, rejecting arithmetic overflow without changing state.

      iex> OtlpShipper.Metrics.Aggregation.add(:sum, nil, 3, [], 100)
      {:ok, %{value: 3, negative: false}}
  """
  @spec add(atom(), map() | nil, number(), [number()], non_neg_integer()) ::
          {:ok, map()} | {:error, :numeric_overflow}
  def add(kind, state, value, bounds, observed) do
    result = update(kind, state, value, bounds, observed)
    if representable?(result), do: {:ok, result}, else: {:error, :numeric_overflow}
  rescue
    ArithmeticError -> {:error, :numeric_overflow}
  end

  @doc """
  Chooses the first upper bound greater than or equal to a value.

      iex> OtlpShipper.Metrics.Aggregation.bucket(10, [5, 10])
      1
      iex> OtlpShipper.Metrics.Aggregation.bucket(11, [5, 10])
      2
  """
  @spec bucket(number(), [number()]) :: non_neg_integer()
  def bucket(value, bounds), do: Enum.find_index(bounds, &(value <= &1)) || length(bounds)

  @doc """
  Builds one OTLP metric containing one data point. `monotonic` belongs to the
  definition across intervals, not just this series' current observation.

      iex> definition = %{kind: :counter, name: "web.count", unit: "1", description: "", bounds: []}
      iex> metric = OtlpShipper.Metrics.Aggregation.metric(definition, %{value: 2, negative: false}, [], 10, 20, true)
      iex> elem(metric.data, 1).data_points |> hd() |> Map.fetch!(:value)
      {:as_int, 2}
  """
  @spec metric(map(), map(), [map()], non_neg_integer(), non_neg_integer(), boolean()) :: map()
  def metric(definition, state, attributes, started, ended, monotonic) do
    point = %{attributes: attributes, start_time_unix_nano: started, time_unix_nano: ended}

    {type, data} =
      case definition.kind do
        :gauge ->
          point =
            point
            |> Map.delete(:start_time_unix_nano)
            |> Map.put(:time_unix_nano, state.observed)
            |> Map.put(:value, number_value(state.value))

          {:gauge, %{data_points: [point]}}

        :histogram ->
          point =
            Map.merge(point, %{
              count: state.count,
              bucket_counts: Tuple.to_list(state.buckets),
              explicit_bounds: definition.bounds,
              min: state.min / 1,
              max: state.max / 1
            })

          point = if state.negative, do: point, else: Map.put(point, :sum, state.sum / 1)

          {:histogram,
           %{aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA, data_points: [point]}}

        _ ->
          {:sum,
           %{
             aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA,
             is_monotonic: monotonic,
             data_points: [Map.put(point, :value, number_value(state.value))]
           }}
      end

    %{
      name: definition.name,
      description: definition.description,
      unit: definition.unit,
      data: {type, data}
    }
  end

  defp update(:gauge, _, value, _, observed), do: %{value: value, observed: observed}

  defp update(:histogram, nil, value, bounds, observed) do
    state = %{
      count: 0,
      sum: 0,
      min: value,
      max: value,
      negative: false,
      buckets: List.duplicate(0, length(bounds) + 1) |> List.to_tuple()
    }

    update(:histogram, state, value, bounds, observed)
  end

  defp update(:histogram, state, value, bounds, _) do
    index = bucket(value, bounds)

    %{
      state
      | count: state.count + 1,
        sum: state.sum + value,
        min: min(state.min, value),
        max: max(state.max, value),
        negative: state.negative or value < 0,
        buckets: put_elem(state.buckets, index, elem(state.buckets, index) + 1)
    }
  end

  defp update(kind, nil, value, bounds, observed),
    do: update(kind, %{value: 0, negative: false}, value, bounds, observed)

  defp update(_, state, value, _, _),
    do: %{value: state.value + value, negative: state.negative or value < 0}

  defp number_value(value) when is_integer(value), do: {:as_int, value}
  defp number_value(value), do: {:as_double, value}
  defp representable?(%{value: value}), do: valid_number?(value)

  defp representable?(%{count: count, sum: sum}),
    do: count <= 18_446_744_073_709_551_615 and valid_number?(sum)

  defp valid_number?(value) when is_integer(value),
    do: value >= -9_223_372_036_854_775_808 and value <= 9_223_372_036_854_775_807

  defp valid_number?(value) when is_float(value),
    do: value == value and abs(value) <= 1.7976931348623157e308
end
