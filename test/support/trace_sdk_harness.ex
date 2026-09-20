defmodule OtlpShipper.TraceSDKObserver do
  @moduledoc false
  @behaviour :otel_exporter_traces

  alias OtlpShipper.TraceExporter

  @impl true
  def init(options) do
    result = TraceExporter.init(options.exporter_options)
    send(options.owner, {options.ref, :initialized, result})

    case result do
      {:ok, state} -> {:ok, Map.put(options, :exporter_state, state)}
      :ignore -> :ignore
    end
  end

  @impl true
  def export(table, resource, state) do
    table_id = if is_atom(table), do: :ets.whereis(table), else: table
    send(state.owner, {state.ref, :entered, self(), table_id, :ets.tab2list(table)})
    result = TraceExporter.export(table, resource, state.exporter_state)
    send(state.owner, {state.ref, :returned, self(), result})
    result
  end

  @impl true
  def shutdown(state) do
    result = TraceExporter.shutdown(state.exporter_state)
    send(state.owner, {state.ref, :shutdown, result})
    result
  end
end

defmodule OtlpShipper.TraceSDKHarness do
  @moduledoc false

  alias OtlpShipper.{TraceExporter, TraceSampler, TraceSDKFixtures, TraceSDKObserver}

  @doc false
  def start(endpoint, options \\ []) do
    name = Module.concat(__MODULE__, "Provider#{System.unique_integer([:positive])}")
    pool = Module.concat(name, Pool)
    ref = make_ref()
    resource = Keyword.get(options, :resource, TraceSDKFixtures.resource())

    exporter_options =
      Keyword.merge(
        [pool: pool, base_endpoint: endpoint, timeout: 500, retry_base_ms: 1, retry_max_ms: 2],
        Keyword.get(options, :exporter, [])
      )

    batch = %{
      name: name,
      resource: resource,
      exporter:
        {TraceSDKObserver, %{owner: self(), ref: ref, exporter_options: exporter_options}},
      scheduled_delay_ms: 60_000,
      exporting_timeout_ms: Keyword.get(options, :sdk_timeout, 2500)
    }

    sdk = %{
      id_generator: :otel_id_generator,
      sampler: {TraceSampler, Keyword.get(options, :sampler, :always_on)},
      processors: [{:otel_batch_processor, batch}],
      deny_list: []
    }

    children = [
      TraceExporter.pool_child_spec(pool),
      %{
        id: name,
        start: {:otel_tracer_server_sup, :start_link, [name, resource, sdk]},
        type: :supervisor
      }
    ]

    {:ok, supervisor} = Supervisor.start_link(children, strategy: :rest_for_one)

    %{
      supervisor: supervisor,
      name: name,
      pool: pool,
      ref: ref,
      processor: :"otel_batch_processor_#{name}",
      provider: :"otel_tracer_provider_#{name}"
    }
  end

  @doc false
  def tracer(
        instance,
        name \\ :sdk_integration,
        version \\ "1",
        schema \\ "https://sdk/integration"
      ),
      do: :otel_tracer_provider.get_tracer(instance.name, name, version, schema)

  @doc false
  def emit(instance, name),
    do: instance |> tracer() |> :otel_tracer.start_span(name, %{}) |> :otel_span.end_span()

  @doc false
  def flush(instance), do: :otel_tracer_provider.force_flush(instance.name)

  @doc false
  def stop(instance) do
    if Process.alive?(instance.supervisor), do: Supervisor.stop(instance.supervisor)
  end

  @doc false
  def pool_pid(instance) do
    Enum.find_value(Supervisor.which_children(instance.supervisor), fn
      {id, pid, _, _} when id != instance.name -> pid
      _ -> nil
    end)
  end
end
