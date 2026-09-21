if Code.ensure_loaded?(:otel_exporter_traces) do
  defmodule OtlpShipper.TraceExporter do
    @moduledoc """
    OTLP/HTTP trace exporter for OpenTelemetry SDK 1.7.0 and API 1.5.0.

    Configure the SDK batch processor with `{OtlpShipper.TraceExporter, options}`.
    Options require a caller-owned named Finch `:pool`; remaining options follow
    `OtlpShipper.Config.load_transport/2`. Resources come exclusively from the SDK.
    Unsupported SDK/API versions or unavailable pools make initialization ignore
    this exporter. Initialization diagnostics get a separate 100 ms budget and are
    best effort. This module exists only when the SDK was available at compilation.

    Start `pool_child_spec/1` before the SDK provider under a consumer-owned
    `:rest_for_one` supervisor. Give the SDK export worker at least `timeout + 2000`
    milliseconds. The SDK owns batching and table lifetime. This callback waits for
    bounded export work without retaining the table or owning another queue/pool.

    One retained SDK record is retrieved at a time. ETS may copy a large source
    record; the SDK owns that retention bound. Additional normalization/encoding is
    bounded before traversing collections. Shutdown does not stop the caller's pool.
    Install `OtlpShipper.TraceSampler` around the consumer's sampler to suppress
    exporter HTTP instrumentation. The exporter never changes SDK configuration.
    """
    @behaviour :otel_exporter_traces
    alias OtlpShipper.{Config, TraceBatch, TraceSDKRecord}

    @doc """
    Builds a consumer-owned pool child specification with bounded restart recovery.

    Each instance needs a distinct atom name. Place this child before its SDK
    provider under `:rest_for_one`; provider shutdown then precedes pool shutdown.
    """
    @spec pool_child_spec(atom()) :: Supervisor.child_spec()
    def pool_child_spec(name) when is_atom(name) and name not in [nil, :undefined] do
      %{
        id: name,
        start: {OtlpShipper.Pool, :start_link, [name, :atomics.new(1, [])]},
        type: :supervisor
      }
    end

    @impl true
    def init(options) do
      with true <- supported_versions?(),
           true <- Keyword.keyword?(options),
           {pool, transport_options} <- Keyword.pop(options, :pool),
           true <- available_pool?(pool),
           {:ok, config} <- Config.load_transport(:traces, transport_options) do
        {:ok, %{config: config, pool: pool}}
      else
        _ -> initialization_failed()
      end
    end

    @impl true
    def export(table, resource, %{config: config, pool: pool}) do
      deadline = System.monotonic_time(:millisecond) + config.timeout
      offset = System.time_offset(:native)
      count = :ets.info(table, :size)

      spans =
        table |> records() |> Stream.map(&TraceSDKRecord.normalize(&1, config.max_item_bytes))

      resource = fn -> TraceSDKRecord.resource(resource, config.max_batch_bytes) end

      config
      |> TraceBatch.export_until(pool, spans, resource, offset, count, deadline)
      |> callback_result()
    rescue
      _ -> :failed_not_retryable
    end

    @impl true
    def shutdown(_state), do: :ok

    # Refuse unverified record layouts instead of guessing from dependency ranges.
    defp supported_versions? do
      Application.spec(:opentelemetry, :vsn) == ~c"1.7.0" and
        Application.spec(:opentelemetry_api, :vsn) == ~c"1.5.0"
    end

    # Registry metadata is read directly; do not call an arbitrary registered process.
    defp available_pool?(pool) when is_atom(pool) and pool not in [nil, :undefined] do
      case Registry.meta(pool, :config) do
        {:ok, %{registry_name: ^pool, supervisor_name: supervisor, default_pool_config: config}}
        when is_map(config) and is_atom(supervisor) ->
          is_pid(Process.whereis(supervisor))

        _ ->
          false
      end
    rescue
      _ -> false
    end

    defp available_pool?(_), do: false

    # Configuration diagnostics contain neither credentials nor arbitrary option values.
    defp initialization_failed do
      task = Task.async(&initialization_diagnostic/0)
      Task.yield(task, 100) || Task.shutdown(task, :brutal_kill)
      :ignore
    end

    # A subscriber cannot hold SDK initialization open beyond this bounded worker.
    defp initialization_diagnostic do
      :telemetry.execute([:otlp_shipper, :export, :exception], %{count: 0}, %{
        signal: :traces,
        reason: :invalid_configuration
      })
    end

    # Select one record at a time without retaining the borrowed ETS table afterward.
    defp records(table) do
      Stream.unfold({:first, table}, fn
        {:first, table} -> selected(:ets.select(table, [{:"$1", [], [:"$1"]}], 1))
        :"$end_of_table" -> nil
        continuation -> selected(:ets.select(continuation))
      end)
    end

    defp selected(:"$end_of_table"), do: nil
    defp selected({[record], continuation}), do: {record, continuation}

    # Partial or local loss makes successful transport a permanent SDK outcome.
    defp callback_result({:ok, %{invalid: 0, rejected: 0}}), do: :ok
    defp callback_result({:ok, _}), do: :failed_not_retryable

    defp callback_result({:error, reason, %{accepted: 0, rejected: 0, invalid: 0}}) do
      if retryable?(reason), do: :failed_retryable, else: :failed_not_retryable
    end

    defp callback_result({:error, _, _}), do: :failed_not_retryable

    # SDK 1.7 does not requeue this result; transport already exhausted its own budget.
    defp retryable?(:timeout), do: true
    defp retryable?({:transport, _}), do: true
    defp retryable?({:http_status, status}) when status in [429, 502, 503, 504], do: true
    defp retryable?(_), do: false
  end
end
