defmodule OtlpShipper.Pairs do
  @moduledoc false

  # Shared parsing for OTEL comma-separated, percent-encoded key/value settings.
  @doc false
  @spec parse(String.t()) :: {:ok, map()} | {:error, :invalid_pairs}
  def parse(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, %{}}, fn part, {:ok, acc} ->
      case String.split(part, "=", parts: 2) do
        [key, value] ->
          with {:ok, key} <- decode(String.trim(key)),
               {:ok, value} <- decode(String.trim(value)),
               false <- key == "" do
            {:cont, {:ok, Map.put(acc, key, value)}}
          else
            _ -> {:halt, {:error, :invalid_pairs}}
          end

        _ ->
          {:halt, {:error, :invalid_pairs}}
      end
    end)
  end

  def parse(_), do: {:error, :invalid_pairs}

  defp decode(value) do
    if Regex.match?(~r/%(?![0-9a-fA-F]{2})/, value) do
      {:error, :invalid_pairs}
    else
      decoded = URI.decode(value)
      if String.valid?(decoded), do: {:ok, decoded}, else: {:error, :invalid_pairs}
    end
  end
end
