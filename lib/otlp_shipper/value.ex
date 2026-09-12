defmodule OtlpShipper.Value do
  @moduledoc """
  Converts Elixir values into generated OTLP AnyValue message maps.

  Invalid UTF-8 binaries use `bytes_value`; integers outside signed 64-bit range
  use strings. Atom keys and values become strings. Booleans retain their type.
  Conversion preserves values; ingress/truncation limits are enforced by callers.
  """

  @doc """
  Builds an AnyValue, recursively converting collections.

      iex> OtlpShipper.Value.encode(%{healthy: true})
      %{value: {:kvlist_value, %{values: [%{key: "healthy", value: %{value: {:bool_value, true}}}]}}}

      iex> OtlpShipper.Value.encode([1, "two"])
      %{value: {:array_value, %{values: [%{value: {:int_value, 1}}, %{value: {:string_value, "two"}}]}}}
  """
  @spec encode(term()) :: map()
  def encode(value) when is_boolean(value), do: %{value: {:bool_value, value}}
  def encode(value) when is_atom(value), do: %{value: {:string_value, Atom.to_string(value)}}

  def encode(value)
      when is_integer(value) and value >= -9_223_372_036_854_775_808 and
             value <= 9_223_372_036_854_775_807,
      do: %{value: {:int_value, value}}

  def encode(value) when is_float(value), do: %{value: {:double_value, value}}

  def encode(value) when is_binary(value) do
    type = if String.valid?(value), do: :string_value, else: :bytes_value
    %{value: {type, value}}
  end

  def encode(value) when is_list(value),
    do: %{value: {:array_value, %{values: Enum.map(value, &encode/1)}}}

  def encode(value) when is_map(value),
    do: %{value: {:kvlist_value, %{values: attributes(value)}}}

  def encode(value),
    do: %{value: {:string_value, inspect(value, limit: 50, printable_limit: 4096)}}

  @doc """
  Builds deterministic KeyValue messages with unique string keys.

  Atom/string collisions resolve to the string-keyed entry. Other key types use
  bounded inspection. Prefer strings or atoms for interoperable attributes.

      iex> OtlpShipper.Value.attributes(%{count: 2})
      [%{key: "count", value: %{value: {:int_value, 2}}}]
  """
  @spec attributes(map()) :: [map()]
  def attributes(values) when is_map(values) do
    values
    |> Map.to_list()
    |> Enum.sort_by(fn {key, _} -> {is_binary(key), key} end)
    |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, value} -> %{key: key, value: encode(value)} end)
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)

  defp normalize_key(key) when is_binary(key) do
    if String.valid?(key), do: key, else: inspect(key, limit: 50, printable_limit: 4096)
  end

  defp normalize_key(key), do: inspect(key, limit: 50, printable_limit: 4096)
end
