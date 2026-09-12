defmodule OtlpShipper.MetricsReporter do
  @moduledoc """
  Supervised Telemetry.Metrics reporter exporting OTLP/HTTP metrics through Finch.

  Start `{OtlpShipper.MetricsReporter, metrics: metrics, service_name: "checkout"}`
  in your supervision tree. Counter and sum definitions become delta Sums;
  distributions become explicit-bound delta Histograms; last values become Gauges.
  Summaries are rejected with `{:error, :unsupported_metric, :use_distribution}`.
  Distributions require `reporter_options: [buckets: [...]]` in converted units.

  Accepts shared Config options plus `:metrics` (required), `:max_series` (1000),
  `:max_pending` (2048 pending observations), `:max_tag_bytes` (4096 external bytes),
  `:name` (optional supervisor name), and `:finch_name` (default
  `OtlpShipper.MetricsReporter.Finch`). Independent instances need distinct Finch
  names. `flush_ms` is the aggregation interval (default 1000 ms).

  A supervised GenServer serializes aggregation. Telemetry callbacks reserve a
  bounded ingress slot before sending a sample; no HTTP or GenServer call occurs
  in the event producer. If ingress is full the new observation is dropped. The
  first `max_series` series in an interval are admitted; new series beyond the cap
  are dropped until the next interval. Existing series continue updating.

  Intervals follow processing order, including observations waiting in ingress.
  Flush resets all active series; idle intervals emit nothing, including gauges.
  Sums remain nonmonotonic after any accepted negative observation until restart.
  Tags are not truncated, since that could merge distinct series. Invalid data,
  callback errors, overload, and transport drops emit the shared dropped event.
  Keep/tag/measurement callbacks must be fast and must not perform blocking work.

  Completed data points enter the shared bounded Buffer. Counts in transport/drop
  telemetry refer to points there, and observations at ingress/aggregation. There
  is one HTTP batch in flight. Shutdown detaches handlers, takes a final snapshot,
  and drains the Buffer within its shutdown budget. Crashes/restart gaps lose data;
  retrying an accepted request whose response was lost can duplicate points.
  """
  use Supervisor
  alias OtlpShipper.{Buffer, Config, Encoder, Pool, Transport}
  alias OtlpShipper.Metrics.{Definition, Registration, Worker}
  @options [:metrics, :max_series, :max_pending, :max_tag_bytes, :name, :finch_name]

  @doc "Starts the supervised reporter after validating all definitions and options."
  @spec start_link(keyword()) ::
          Supervisor.on_start() | {:error, atom()} | {:error, atom(), atom()}
  def start_link(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, definitions} <- Definition.new(Keyword.get(opts, :metrics)),
         settings =
           Keyword.merge(
             [
               max_series: 1000,
               max_pending: 2048,
               max_tag_bytes: 4096,
               finch_name: __MODULE__.Finch
             ],
             Keyword.take(opts, @options)
           ),
         :ok <- validate_settings(settings),
         {:ok, config} <- Config.load(:metrics, Keyword.drop(opts, @options)) do
      Supervisor.start_link(
        __MODULE__,
        {definitions, settings, config},
        Keyword.take(settings, [:name])
      )
    else
      false -> {:error, :invalid_metrics_options}
      error -> error
    end
  end

  @doc false
  def child_spec(opts),
    do: %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }

  @doc """
  Closes the current interval and requests asynchronous export. Returns after the
  snapshot is queued, not after delivery. Observations from this calling process
  emitted before flush are included. Concurrent producers may enter either interval.
  """
  @spec flush(Supervisor.supervisor()) :: :ok | {:error, :unavailable}
  def flush(supervisor) do
    case List.keyfind(Supervisor.which_children(supervisor), Worker, 0) do
      {Worker, pid, _, _} when is_pid(pid) -> GenServer.call(pid, :flush)
      _ -> {:error, :unavailable}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @impl true
  def init({definitions, settings, config}) do
    # Only startup handles live here; event producers never query this table.
    handles = :ets.new(__MODULE__, [:set, :public])
    finch = settings[:finch_name]

    export = fn items ->
      Logger.metadata(domain: [:otlp_shipper])

      with {:ok, body} <- Encoder.encode(:metrics, merge_points(items), config.resource) do
        Transport.export(config, finch, body, length(items))
      end
    end

    children = [
      %{id: finch, start: {Pool, :start_link, [finch, :atomics.new(1, [])]}, type: :supervisor},
      %{
        id: Buffer,
        start: {__MODULE__, :start_buffer, [handles, config, export]},
        shutdown: config.shutdown_ms + 1000
      },
      {Worker, handles: handles, definitions: definitions, settings: settings, config: config},
      {Registration,
       handles: handles, definitions: definitions, settings: settings, token: make_ref()}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc false
  def start_buffer(handles, config, export) do
    with {:ok, pid} <- Buffer.start_link(config: config, export: export) do
      :ets.insert(handles, {:buffer, Buffer.handle(pid)})
      {:ok, pid}
    end
  end

  defp merge_points(items) do
    items
    |> Enum.group_by(fn %{data: {type, data}} = metric ->
      {Map.delete(metric, :data), type, Map.delete(data, :data_points)}
    end)
    |> Enum.map(fn {{metric, type, data}, metrics} ->
      points = Enum.flat_map(metrics, fn %{data: {_, data}} -> data.data_points end)
      Map.put(metric, :data, {type, Map.put(data, :data_points, points)})
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp validate_settings(settings) do
    limits =
      Enum.all?(
        [:max_series, :max_pending, :max_tag_bytes],
        &(is_integer(settings[&1]) and settings[&1] > 0)
      )

    if limits and is_atom(settings[:finch_name]) and not is_nil(settings[:finch_name]) and
         valid_name?(settings[:name]), do: :ok, else: {:error, :invalid_metrics_options}
  end

  defp valid_name?(name) when is_atom(name), do: true
  defp valid_name?({:global, _}), do: true
  defp valid_name?({:via, module, _}) when is_atom(module), do: true
  defp valid_name?(_), do: false
end
