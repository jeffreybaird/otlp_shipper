defmodule OtlpShipper.TraceValue do
  @moduledoc false

  # Internal bounded traversal shared by trace records and envelopes. The budget
  # bounds materialization; generated protobuf bytes remain the exact size limit.
  @doc false
  def bounded?(value, budget) when is_integer(budget) and budget > 0 do
    measure(value, budget, 0) >= 0
  end

  def bounded?(_, _), do: false

  # Avoid copying maps or tuples before establishing a finite traversal bound.
  defp measure(_, remaining, depth) when remaining < 0 or depth > 16, do: -1
  defp measure(value, remaining, _) when is_binary(value), do: remaining - byte_size(value)

  defp measure(value, remaining, depth) when is_map(value) do
    if map_size(value) > remaining do
      -1
    else
      Enum.reduce_while(value, remaining, &measure_entry(&1, &2, depth))
    end
  end

  defp measure(value, remaining, depth) when is_tuple(value) do
    if tuple_size(value) > remaining, do: -1, else: measure_tuple(value, 0, remaining, depth)
  end

  defp measure([], remaining, _), do: remaining

  defp measure([head | tail], remaining, depth) do
    rest = measure(head, remaining - 1, depth + 1)
    if rest < 0, do: -1, else: measure(tail, rest, depth)
  end

  defp measure(_, remaining, _), do: remaining - 1

  # Stop map traversal immediately when its allocation budget is exhausted.
  defp measure_entry({key, item}, rest, depth) do
    rest = measure(item, measure(key, rest - 1, depth + 1), depth + 1)
    if rest < 0, do: {:halt, -1}, else: {:cont, rest}
  end

  # Traverse tuple elements directly so a giant tuple is never copied to a list.
  defp measure_tuple(tuple, index, remaining, _) when index == tuple_size(tuple), do: remaining

  defp measure_tuple(tuple, index, remaining, depth) do
    rest = measure(elem(tuple, index), remaining - 1, depth + 1)
    if rest < 0, do: -1, else: measure_tuple(tuple, index + 1, rest, depth)
  end

  @doc false
  def attributes(values) when is_map(values) do
    values
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      key = key(key)
      if Map.has_key?(acc, key), do: throw(:invalid_trace_value)
      Map.put(acc, key, %{key: key, value: value(value)})
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  def attributes(_), do: throw(:invalid_trace_value)

  # Only SDK-supported string or atom keys are accepted; collisions are errors.
  defp key(value) when is_atom(value) and value not in [nil, :undefined],
    do: Atom.to_string(value)

  defp key(value) when is_binary(value), do: string(value)
  defp key(_), do: throw(:invalid_trace_value)

  @doc false
  def string(value) when is_binary(value) do
    if String.valid?(value), do: value, else: throw(:invalid_trace_value)
  end

  def string(_), do: throw(:invalid_trace_value)

  # Arrays must be flat and homogeneous in the SDK representation.
  defp value(value) when is_tuple(value), do: value(Tuple.to_list(value))
  defp value([]), do: %{value: {:array_value, %{values: []}}}

  defp value([head | _] = values) do
    type = scalar_type(head)

    encoded =
      Enum.map(values, fn item ->
        if scalar_type(item) != type, do: throw(:invalid_trace_value)
        scalar(item)
      end)

    %{value: {:array_value, %{values: encoded}}}
  end

  defp value(value), do: scalar(value)

  # Preserve primitive types rather than stringifying unsupported data.
  defp scalar_type(value) when is_boolean(value), do: :boolean
  defp scalar_type(value) when is_binary(value), do: :binary
  defp scalar_type(value) when is_atom(value) and value not in [nil, :undefined], do: :atom
  defp scalar_type(value) when is_integer(value), do: :integer
  defp scalar_type(value) when is_float(value), do: :float
  defp scalar_type(_), do: throw(:invalid_trace_value)

  defp scalar(value) when is_boolean(value), do: %{value: {:bool_value, value}}
  defp scalar(value) when is_binary(value), do: %{value: {:string_value, string(value)}}

  defp scalar(value) when is_atom(value) and value not in [nil, :undefined],
    do: %{value: {:string_value, Atom.to_string(value)}}

  defp scalar(value)
       when is_integer(value) and value >= -9_223_372_036_854_775_808 and
              value <= 9_223_372_036_854_775_807,
       do: %{value: {:int_value, value}}

  defp scalar(value) when is_float(value), do: %{value: {:double_value, value}}
  defp scalar(_), do: throw(:invalid_trace_value)
end
