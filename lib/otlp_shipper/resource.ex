defmodule OtlpShipper.Resource do
  @moduledoc "Builds a shared OTLP Resource with an explicit service identity."
  alias OtlpShipper.{Pairs, Value}

  @doc """
  Resolves resource attributes from explicit options over an environment map.

  `:resource` is a map of string/atom keys. `:service_name`, `:service_version`,
  and `:service_instance_id` override its identity attributes. `OTEL_SERVICE_NAME`
  overrides `service.name` in `OTEL_RESOURCE_ATTRIBUTES`. No environment is read
  implicitly. A missing or blank service name is an initialization error.

      iex> {:ok, resource} = OtlpShipper.Resource.new([service_name: "checkout"], %{})
      iex> resource.attributes
      [%{key: "service.name", value: %{value: {:string_value, "checkout"}}}]
  """
  @spec new(keyword(), map()) :: {:ok, map()} | {:error, atom()}
  def new(opts, env \\ %{}) do
    with true <- Keyword.keyword?(opts) and is_map(env),
         {:ok, attrs} <- Pairs.parse(Map.get(env, "OTEL_RESOURCE_ATTRIBUTES", "")),
         explicit when is_map(explicit) <- Keyword.get(opts, :resource, %{}),
         true <- Enum.all?(Map.keys(explicit), &(is_atom(&1) or is_binary(&1))) do
      attrs =
        attrs
        |> put_if_present("service.name", nonempty(Map.get(env, "OTEL_SERVICE_NAME")))
        |> Map.merge(Map.new(explicit, fn {key, value} -> {to_string(key), value} end))
        |> put_if_present("service.name", Keyword.get(opts, :service_name))
        |> put_if_present("service.version", Keyword.get(opts, :service_version))
        |> put_if_present("service.instance.id", Keyword.get(opts, :service_instance_id))

      if valid_service_name?(attrs["service.name"]) do
        {:ok, %{attributes: Value.attributes(attrs)}}
      else
        {:error, :service_name_required}
      end
    else
      _ -> {:error, :invalid_resource}
    end
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
  defp nonempty(""), do: nil
  defp nonempty(value), do: value

  defp valid_service_name?(name) when is_binary(name),
    do: String.valid?(name) and String.trim(name) != ""

  defp valid_service_name?(_), do: false
end
