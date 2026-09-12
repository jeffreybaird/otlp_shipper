defmodule OtlpShipper.LogHandler do
  @moduledoc """
  Supervised Erlang Logger handler exporting bounded OTLP/HTTP log batches.

  Add `{OtlpShipper.LogHandler, service_name: "checkout"}` to your supervision
  tree. This starts a dedicated Finch pool, buffer, and handler registration in
  that order. A `:rest_for_one` supervisor refreshes registration after buffer or
  pool failure. Shutdown removes the handler before draining the buffer.

  Accepts all `OtlpShipper.Config` options plus `:max_body_bytes` (16,384 encoded
  AnyValue bytes), `:max_attribute_bytes` (1024 encoded value bytes and key bytes),
  `:max_attributes` (64), `:level` (`:info`), and `:diagnostic_interval_ms` (60,000).
  Collection conversion is limited to 64 entries per container and depth eight.

  For independent instances provide distinct `:handler_id` (default
  `:otlp_shipper`), `:finch_name` (default `OtlpShipper.LogHandler.Finch`), and
  `:buffer_name` (default `OtlpShipper.LogHandler.Buffer`), all atoms. These names
  must be application-owned constants. `:name` optionally names the supervisor.
  Configuration changes require a restart, except Logger's handler level/filters.
  The application's primary Logger level still applies; it is never changed here.

  Logging performs bounded conversion and direct ETS insertion in the caller,
  never an HTTP request or a message per event. Overflow drops oldest queued
  records. Crashes can lose queued/in-flight records and logs during restart.
  Export is best effort; retries can duplicate remotely accepted records.

  Trace IDs come from complete valid `otel_*` event metadata, then the current
  span if the optional tracing API is available. With that API installed, IDs
  inherited from process metadata without an active span are ignored: the API can
  leave stale IDs after detaching. Use a distinct explicit event pair for forwarded
  logs. Exporter diagnostics and HTTP
  client internal logs (Finch, Mint, NimblePool) are excluded to prevent recursion.
  Failure diagnostics are rate limited, contain no payloads/headers/URLs, and use
  domain `[:otlp_shipper]`. Telemetry still reports every export outcome.
  """
  use Supervisor
  @behaviour :logger_handler
  # These two calls are guarded at runtime and covered both with and without the
  # optional API. Consumers without tracing must also compile without warnings.
  @compile {:no_warn_undefined,
            [{:otel_tracer, :current_span_ctx, 0}, {:otel_span, :hex_span_ctx, 1}]}
  alias OtlpShipper.{Buffer, Config, Encoder, LogRecord, Transport}
  alias OtlpShipper.LogHandler.Registration

  @record_options [:max_body_bytes, :max_attribute_bytes, :max_attributes]
  @handler_options [
    :handler_id,
    :finch_name,
    :buffer_name,
    :name,
    :level,
    :diagnostic_interval_ms
  ]
  @defaults [
    handler_id: :otlp_shipper,
    finch_name: __MODULE__.Finch,
    buffer_name: __MODULE__.Buffer,
    level: :info,
    diagnostic_interval_ms: 60_000
  ]

  @doc "Starts the supervised log pipeline. Invalid options return tagged errors."
  @spec start_link(keyword()) ::
          Supervisor.on_start() | {:error, atom()} | {:error, atom(), atom()}
  def start_link(opts) do
    with true <- Keyword.keyword?(opts),
         settings = Keyword.merge(@defaults, Keyword.take(opts, @handler_options)),
         :ok <- validate_settings(settings),
         {:ok, limits} <- LogRecord.limits(Keyword.take(opts, @record_options)),
         {:ok, config} <-
           Config.load(:logs, Keyword.drop(opts, @handler_options ++ @record_options)) do
      Supervisor.start_link(
        __MODULE__,
        {settings, limits, config},
        Keyword.take(settings, [:name])
      )
    else
      false -> {:error, :invalid_log_options}
      error -> error
    end
  end

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :handler_id, :otlp_shipper),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @impl Supervisor
  def init({settings, limits, config}) do
    finch = settings[:finch_name]
    buffer = settings[:buffer_name]
    interval = settings[:diagnostic_interval_ms]
    last_diagnostic = :atomics.new(1, signed: true)
    :atomics.put(last_diagnostic, 1, System.monotonic_time(:millisecond) - interval)
    export = fn records -> export(records, config, finch, last_diagnostic, interval) end

    children = [
      %{
        id: finch,
        start: {__MODULE__.Pool, :start_link, [finch, :atomics.new(1, [])]},
        type: :supervisor
      },
      {Buffer, name: buffer, config: config, export: export},
      {Registration,
       handler_id: settings[:handler_id],
       buffer: buffer,
       limits: limits,
       level: settings[:level],
       token: make_ref()}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @impl :logger_handler
  def adding_handler(
        %{config: %{handle: %Buffer.Handle{}, limits: limits, token: token}} = config
      )
      when is_map(limits) and is_reference(token), do: {:ok, config}

  def adding_handler(_), do: {:error, :start_supervised_log_handler}

  @impl :logger_handler
  def removing_handler(_), do: :ok

  @impl :logger_handler
  def changing_config(_, old, new) do
    if Map.get(new, :config, old.config) == old.config,
      do: {:ok, Map.put(new, :config, old.config)},
      else: {:error, :restart_required}
  end

  @impl :logger_handler
  def filter_config(config), do: %{config | config: Map.take(config.config, [:token])}

  @impl :logger_handler
  def log(event, %{config: %{handle: handle, limits: limits}}) do
    unless Process.get({__MODULE__, :logging}, false) or excluded?(event) do
      Process.put({__MODULE__, :logging}, true)

      try do
        {event, context} = resolve_context(event)

        case LogRecord.new(event, limits, context, System.os_time(:nanosecond)) do
          {:ok, record} ->
            if Buffer.enqueue(handle, record) == {:error, :closed}, do: dropped(:unavailable)

          {:error, :invalid_log_event} ->
            dropped(:invalid_log_event)
        end
      after
        Process.delete({__MODULE__, :logging})
      end
    end

    :ok
  end

  defp validate_settings(settings) do
    valid =
      Enum.all?(
        [:handler_id, :finch_name, :buffer_name],
        &(is_atom(settings[&1]) and not is_nil(settings[&1]))
      )

    level =
      settings[:level] in [
        :all,
        :none,
        :debug,
        :info,
        :notice,
        :warning,
        :error,
        :critical,
        :alert,
        :emergency
      ]

    interval = settings[:diagnostic_interval_ms]

    if valid and valid_name?(settings[:name]) and level and is_integer(interval) and interval > 0,
      do: :ok,
      else: {:error, :invalid_log_options}
  end

  defp valid_name?(name) when is_atom(name), do: true
  defp valid_name?({:global, _}), do: true
  defp valid_name?({:via, module, _}) when is_atom(module), do: true
  defp valid_name?(_), do: false

  defp resolve_context(event) do
    if Code.ensure_loaded?(:otel_tracer) and Code.ensure_loaded?(:otel_span) do
      context = :otel_tracer.current_span_ctx() |> :otel_span.hex_span_ctx()
      {reject_stale_process_ids(event, context), context}
    else
      {event, %{}}
    end
  rescue
    _ -> {event, %{}}
  end

  # API 1.5 leaves Logger process metadata unchanged when detaching to an empty
  # context. Do not mistake those inherited IDs for explicit event correlation.
  # A distinct pair supplied on the event remains valid without a current span.
  defp reject_stale_process_ids(%{meta: meta} = event, context) when map_size(context) == 0 do
    process_meta =
      case :logger.get_process_metadata() do
        :undefined -> %{}
        metadata -> metadata
      end

    keys = [:otel_trace_id, :otel_span_id]

    if Map.take(meta, keys) == Map.take(process_meta, keys),
      do: %{event | meta: Map.drop(meta, keys ++ [:otel_trace_flags])},
      else: event
  end

  defp reject_stale_process_ids(event, _), do: event

  defp excluded?(%{meta: meta}) when is_map(meta) do
    domain = Map.get(meta, :domain, [])
    internal_domain?(domain) or internal_module?(Map.get(meta, :mfa))
  end

  defp excluded?(_), do: false

  defp internal_domain?([:otlp_shipper | _]), do: true
  defp internal_domain?([_ | tail]), do: internal_domain?(tail)
  defp internal_domain?(_), do: false

  defp internal_module?({module, _, _}) when is_atom(module) do
    name = Atom.to_string(module)

    Enum.any?(
      ["Elixir.Finch.", "Elixir.Mint."],
      &String.starts_with?(name, &1)
    ) or
      module in [Finch, Mint, NimblePool, __MODULE__, Registration, Buffer, Transport]
  end

  defp internal_module?(_), do: false

  defp export(records, config, finch, last_diagnostic, interval) do
    Logger.metadata(domain: [:otlp_shipper])

    result =
      with {:ok, body} <- Encoder.encode(:logs, records, config.resource) do
        Transport.export(config, finch, body, length(records))
      end

    diagnose(result, last_diagnostic, interval)
    result
  end

  defp diagnose(:ok, _, _), do: :ok

  defp diagnose(result, last_diagnostic, interval) do
    now = System.monotonic_time(:millisecond)
    previous = :atomics.get(last_diagnostic, 1)

    if now - previous >= interval and
         :atomics.compare_exchange(last_diagnostic, 1, previous, now) == :ok do
      :logger.warning("OTLP log export failed or was partially rejected", %{
        domain: [:otlp_shipper],
        signal: :logs,
        reason: elem(result, 1)
      })
    end

    :ok
  end

  defp dropped(reason),
    do:
      :telemetry.execute([:otlp_shipper, :dropped], %{count: 1}, %{signal: :logs, reason: reason})
end
