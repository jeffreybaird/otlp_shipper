defmodule OtlpShipper.Config do
  @moduledoc """
  Validated OTLP/HTTP configuration. All time values are milliseconds.

  Explicit options override signal-specific OTEL variables, then generic OTEL
  variables. `endpoint` is an exact signal URL; `base_endpoint` appends `v1/logs`
  or `v1/metrics`. Use `load/2` to read the environment once at startup.

  `timeout` bounds an entire export, including retries. Queue/batch limits apply
  per component; the queue and one in-flight batch can coexist. Configuration
  changes require restarting the component. Headers/resources are hidden by Inspect.
  """
  alias OtlpShipper.{Pairs, Resource}

  @derive {Inspect, except: [:headers, :resource]}
  defstruct signal: :logs,
            endpoint: nil,
            headers: [],
            resource: %{},
            compression: :none,
            timeout: 10_000,
            max_retries: 3,
            retry_base_ms: 200,
            retry_max_ms: 5_000,
            max_response_bytes: 65_536,
            max_queue: 2048,
            max_batch: 512,
            max_item_bytes: 65_536,
            max_batch_bytes: 1_048_576,
            flush_ms: 1000,
            shutdown_ms: 5000

  @type t :: %__MODULE__{}
  @limits [
    :timeout,
    :retry_base_ms,
    :retry_max_ms,
    :max_response_bytes,
    :max_queue,
    :max_batch,
    :max_item_bytes,
    :max_batch_bytes,
    :flush_ms,
    :shutdown_ms
  ]
  @options @limits ++
             [
               :max_retries,
               :endpoint,
               :base_endpoint,
               :headers,
               :compression,
               :resource,
               :service_name,
               :service_version,
               :service_instance_id
             ]

  @doc """
  Resolves and validates configuration without accessing global state.

      iex> {:ok, config} = OtlpShipper.Config.new(:logs, service_name: "checkout")
      iex> config.endpoint
      "http://localhost:4318/v1/logs"

      iex> OtlpShipper.Config.new(:traces, service_name: "checkout")
      {:error, :invalid_signal}
  """
  @spec new(atom(), keyword(), map()) :: {:ok, t()} | {:error, atom()} | {:error, atom(), atom()}
  def new(signal, opts \\ [], env \\ %{})

  def new(signal, opts, env) when signal in [:logs, :metrics] do
    with :ok <- validate_options(opts, env),
         :ok <- validate_protocol(signal, env),
         {:ok, endpoint} <- resolve_endpoint(signal, opts, env),
         {:ok, headers} <- resolve_headers(signal, opts, env),
         {:ok, resource} <- Resource.new(opts, env),
         {:ok, compression} <- resolve_compression(signal, opts, env),
         {:ok, limits} <- resolve_limits(signal, opts, env) do
      config = struct!(__MODULE__, limits)

      {:ok,
       %{
         config
         | signal: signal,
           endpoint: endpoint,
           headers: headers,
           resource: resource,
           compression: compression
       }}
    end
  end

  def new(_, _, _), do: {:error, :invalid_signal}

  @doc "Resolves configuration using the current environment at startup."
  @spec load(atom(), keyword()) :: {:ok, t()} | {:error, atom()} | {:error, atom(), atom()}
  def load(signal, opts \\ []), do: new(signal, opts, System.get_env())

  defp validate_options(opts, env) do
    if Keyword.keyword?(opts) and is_map(env) do
      case Keyword.keys(opts) -- @options do
        [] -> :ok
        [key | _] -> {:error, :unknown_option, key}
      end
    else
      {:error, :invalid_options}
    end
  end

  defp validate_protocol(signal, env) do
    if setting(env, signal, "PROTOCOL", "http/protobuf") == "http/protobuf",
      do: :ok,
      else: {:error, :unsupported_protocol}
  end

  defp resolve_endpoint(signal, opts, env) do
    signal_endpoint =
      nonempty(env["OTEL_EXPORTER_OTLP_#{String.upcase(to_string(signal))}_ENDPOINT"])

    {url, append?} =
      cond do
        Keyword.has_key?(opts, :endpoint) -> {opts[:endpoint], false}
        Keyword.has_key?(opts, :base_endpoint) -> {opts[:base_endpoint], true}
        signal_endpoint != nil -> {signal_endpoint, false}
        true -> {nonempty(env["OTEL_EXPORTER_OTLP_ENDPOINT"]) || "http://localhost:4318", true}
      end

    with true <- is_binary(url),
         {:ok, uri} <- URI.new(url),
         true <- uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "",
         true <- is_integer(uri.port) and uri.port in 1..65535,
         true <- is_nil(uri.userinfo) and is_nil(uri.fragment) do
      path =
        if append?,
          do: String.trim_trailing(uri.path || "", "/") <> "/v1/#{signal}",
          else: uri.path || "/"

      {:ok, URI.to_string(%{uri | path: path})}
    else
      _ -> {:error, :invalid_endpoint}
    end
  end

  defp resolve_headers(signal, opts, env) do
    result =
      case Keyword.fetch(opts, :headers) do
        {:ok, value} when is_map(value) -> {:ok, Map.to_list(value)}
        {:ok, value} when is_list(value) -> {:ok, value}
        {:ok, _} -> {:error, :invalid_headers}
        :error -> Pairs.parse(setting(env, signal, "HEADERS", ""))
      end

    with {:ok, headers} <- result,
         true <- Enum.all?(headers, &valid_header?/1) do
      headers = Enum.map(headers, fn {key, value} -> {String.downcase(key), value} end)

      if Enum.any?(headers, fn {key, _} ->
           key in [
             "host",
             "content-length",
             "content-type",
             "content-encoding",
             "transfer-encoding"
           ]
         end), do: {:error, :reserved_header}, else: {:ok, headers}
    else
      _ -> {:error, :invalid_headers}
    end
  end

  defp valid_header?({key, value}) when is_binary(key) and is_binary(value),
    do:
      Regex.match?(~r/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/, key) and
        not Regex.match?(~r/[\x00-\x1F\x7F]/, value)

  defp valid_header?(_), do: false

  defp resolve_compression(signal, opts, env) do
    case Keyword.get(opts, :compression, setting(env, signal, "COMPRESSION", "none")) do
      value when value in [:gzip, "gzip"] -> {:ok, :gzip}
      value when value in [:none, "none"] -> {:ok, :none}
      _ -> {:error, :invalid_compression}
    end
  end

  defp resolve_limits(signal, opts, env) do
    defaults = Map.from_struct(%__MODULE__{})
    timeout = Keyword.get(opts, :timeout, parse_integer(setting(env, signal, "TIMEOUT", "10000")))
    limits = Keyword.put(Keyword.take(opts, @limits ++ [:max_retries]), :timeout, timeout)
    values = Map.merge(Map.take(defaults, @limits ++ [:max_retries]), Map.new(limits))
    invalid = Enum.find(@limits, fn key -> not (is_integer(values[key]) and values[key] > 0) end)

    cond do
      invalid != nil ->
        {:error, :invalid_option, invalid}

      not (is_integer(values.max_retries) and values.max_retries >= 0 and
               values.max_retries <= 100) ->
        {:error, :invalid_option, :max_retries}

      values.max_batch > values.max_queue ->
        {:error, :invalid_option, :max_batch}

      values.max_item_bytes > values.max_batch_bytes ->
        {:error, :invalid_option, :max_item_bytes}

      values.retry_base_ms > values.retry_max_ms ->
        {:error, :invalid_option, :retry_base_ms}

      true ->
        {:ok, values}
    end
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp setting(env, signal, suffix, default) do
    nonempty(env["OTEL_EXPORTER_OTLP_#{String.upcase(to_string(signal))}_#{suffix}"]) ||
      nonempty(env["OTEL_EXPORTER_OTLP_#{suffix}"]) || default
  end

  defp nonempty(""), do: nil
  defp nonempty(value), do: value
end
