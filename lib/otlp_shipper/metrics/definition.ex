defmodule OtlpShipper.Metrics.Definition do
  @moduledoc """
  Validates Telemetry.Metrics definitions and extracts samples before aggregation.

  Measurement functions already include Telemetry.Metrics unit conversion. Keep
  predicates run first; nil measurements are skipped (including counters).
  Counter measurements may be any non-nil value and contribute one event.
  Numeric metrics require finite signed-64-bit integers or doubles.
  """
  alias Telemetry.Metrics.{Counter, Sum, LastValue, Distribution, Summary}
  alias OtlpShipper.Value

  @types %{Counter => :counter, Sum => :sum, LastValue => :gauge, Distribution => :histogram}
  @units %{
    unit: "1",
    second: "s",
    millisecond: "ms",
    microsecond: "us",
    nanosecond: "ns",
    byte: "By",
    kilobyte: "kBy",
    megabyte: "MBy",
    percent: "%"
  }

  @doc """
  Validates definitions and rejects duplicate OTLP names. Histograms require
  explicit strictly increasing finite `reporter_options[:buckets]` (at most 256).
  Summaries return `{:error, :unsupported_metric, :use_distribution}`.

      iex> {:ok, [definition]} = OtlpShipper.Metrics.Definition.new([Telemetry.Metrics.counter("web.count")])
      iex> {definition.name, definition.kind, definition.unit}
      {"web.count", :counter, "1"}
  """
  @spec new(list()) :: {:ok, [map()]} | {:error, atom()} | {:error, atom(), atom()}
  def new(metrics) when is_list(metrics) do
    Enum.reduce_while(metrics, {:ok, []}, fn metric, {:ok, definitions} ->
      case compile_definition(metric) do
        {:ok, definition} ->
          if Enum.any?(definitions, &(&1.name == definition.name)),
            do: {:halt, {:error, :duplicate_metric_name}},
            else: {:cont, {:ok, [definition | definitions]}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, definitions} -> {:ok, Enum.reverse(definitions)}
      error -> error
    end
  rescue
    _ -> {:error, :invalid_metrics}
  end

  def new(_), do: {:error, :invalid_metrics}

  @doc """
  Maps supported units to UCUM; native time must be converted explicitly.

      iex> OtlpShipper.Metrics.Definition.unit(:millisecond)
      {:ok, "ms"}
  """
  @spec unit(atom()) :: {:ok, binary()} | {:error, :unsupported_unit}
  def unit(unit) do
    case Map.fetch(@units, unit) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :unsupported_unit}
    end
  end

  @doc """
  Extracts `{attributes, value}` or skips a filtered/missing measurement.
  Tag values are scalar and bounded by total external size and 32 keys. No tag
  truncation is performed because it could merge distinct series. Callback errors
  are sanitized; they never detach the telemetry handler.

      iex> {:ok, [definition]} = OtlpShipper.Metrics.Definition.new([Telemetry.Metrics.sum("web.bytes")])
      iex> OtlpShipper.Metrics.Definition.sample(definition, %{bytes: 42}, %{})
      {:ok, [], 42}
  """
  @spec sample(map(), map(), map(), pos_integer()) ::
          {:ok, [map()], number()} | :skip | {:error, atom()}
  def sample(definition, measurements, metadata, max_tag_bytes \\ 4096) do
    metric = definition.metric

    with true <- keep?(metric.keep, metadata, measurements),
         value when not is_nil(value) <- measurement(metric.measurement, measurements, metadata),
         {:ok, value} <- validate_measurement(definition.kind, value),
         tags = extract_tags(metric, metadata),
         :ok <- validate_tags(tags, max_tag_bytes) do
      {:ok, Value.attributes(tags), value}
    else
      false -> :skip
      nil -> :skip
      {:error, _} = error -> error
      _ -> {:error, :invalid_keep_result}
    end
  rescue
    _ -> {:error, :callback_failed}
  catch
    _, _ -> {:error, :callback_failed}
  end

  defp compile_definition(%Summary{}), do: {:error, :unsupported_metric, :use_distribution}

  defp compile_definition(%{__struct__: type} = metric) when is_map_key(@types, type) do
    with :ok <- validate_fields(metric),
         {:ok, unit} <- unit(metric.unit),
         {:ok, bounds} <- boundaries(type, metric.reporter_options) do
      {:ok,
       %{
         name: Enum.join(metric.name, "."),
         kind: Map.fetch!(@types, type),
         unit: if(type == Counter, do: "1", else: unit),
         description: metric.description || "",
         bounds: bounds,
         metric: metric
       }}
    end
  end

  defp compile_definition(_), do: {:error, :invalid_metric}

  defp validate_fields(metric) do
    valid_name = is_list(metric.name) and metric.name != [] and Enum.all?(metric.name, &is_atom/1)

    valid_event =
      is_list(metric.event_name) and metric.event_name != [] and
        Enum.all?(metric.event_name, &is_atom/1)

    own_event = match?([:otlp_shipper | _], metric.event_name)

    valid_tags =
      (is_list(metric.tags) and Enum.all?(metric.tags, &(is_atom(&1) or is_binary(&1)))) or
        is_function(metric.tags, 1)

    valid_keep = is_nil(metric.keep) or is_function(metric.keep, 1) or is_function(metric.keep, 2)

    valid_description =
      is_nil(metric.description) or
        (is_binary(metric.description) and String.valid?(metric.description))

    cond do
      own_event ->
        {:error, :recursive_metric_event}

      valid_name and valid_event and valid_tags and valid_keep and valid_description and
        is_function(metric.tag_values, 1) and Keyword.keyword?(metric.reporter_options) ->
        :ok

      true ->
        {:error, :invalid_metric}
    end
  end

  defp boundaries(Distribution, options) do
    bounds = Keyword.get(options, :buckets)

    if Keyword.keys(options) == [:buckets] and is_list(bounds) and length(bounds) <= 256 and
         Enum.all?(bounds, &numeric?/1) and increasing?(bounds),
       do: {:ok, Enum.map(bounds, &(&1 / 1))},
       else: {:error, :invalid_histogram_buckets}
  end

  defp boundaries(_, []), do: {:ok, []}
  defp boundaries(_, _), do: {:error, :unsupported_reporter_options}
  defp increasing?([]), do: true
  defp increasing?([_]), do: true
  defp increasing?([left, right | rest]), do: left < right and increasing?([right | rest])

  defp keep?(nil, _, _), do: true
  defp keep?(fun, meta, _) when is_function(fun, 1), do: fun.(meta)
  defp keep?(fun, meta, measurements), do: fun.(meta, measurements)
  defp measurement(fun, measurements, meta) when is_function(fun, 2), do: fun.(measurements, meta)
  defp measurement(fun, measurements, _) when is_function(fun, 1), do: fun.(measurements)
  defp measurement(key, measurements, _), do: Map.get(measurements, key)
  defp extract_tags(%{tags: fun}, metadata) when is_function(fun, 1), do: fun.(metadata)
  defp extract_tags(metric, metadata), do: metric.tag_values.(metadata) |> Map.take(metric.tags)
  defp validate_measurement(:counter, _), do: {:ok, 1}

  defp validate_measurement(_, value) do
    if numeric?(value), do: {:ok, value}, else: {:error, :invalid_measurement}
  end

  defp numeric?(value) when is_integer(value),
    do: value >= -9_223_372_036_854_775_808 and value <= 9_223_372_036_854_775_807

  defp numeric?(value) when is_float(value),
    do: value == value and abs(value) <= 1.7976931348623157e308

  defp numeric?(_), do: false

  defp validate_tags(tags, max_bytes) when is_map(tags) and not is_struct(tags) do
    if map_size(tags) <= 32 and :erlang.external_size(tags) <= max_bytes and
         Enum.all?(tags, fn {key, value} -> valid_key?(key) and scalar?(value) end),
       do: :ok,
       else: {:error, :invalid_tags}
  end

  defp validate_tags(_, _), do: {:error, :invalid_tags}
  defp valid_key?(key) when is_atom(key), do: true
  defp valid_key?(key) when is_binary(key), do: String.valid?(key)
  defp valid_key?(_), do: false
  defp scalar?(value) when is_atom(value), do: true
  defp scalar?(value) when is_binary(value), do: String.valid?(value)
  defp scalar?(value), do: numeric?(value)
end
