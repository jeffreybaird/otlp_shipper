defmodule OtlpShipper.TraceProbeSampler do
  @moduledoc false
  @behaviour :otel_sampler

  @impl true
  def setup(delegate), do: :otel_sampler.new(delegate)

  @impl true
  def description(delegate),
    do: "ProbeExportSuppression(" <> :otel_sampler.description(delegate) <> ")"

  @impl true
  def should_sample(ctx, trace_id, links, name, kind, attributes, delegate) do
    if :otel_ctx.get_value(ctx, :otlp_shipper_probe_export, false) == true do
      span = :otel_tracer.current_span_ctx(ctx)
      {:drop, [], :otel_span.tracestate(span)}
    else
      :otel_sampler.should_sample(delegate, ctx, trace_id, links, name, kind, attributes)
    end
  end
end

defmodule OtlpShipper.TraceSuppressionExporter do
  @moduledoc false
  @behaviour :otel_exporter_traces
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def export(table, _resource, {owner, ref}) do
    paths =
      Enum.map(
        Enum.sort_by(:ets.tab2list(table), &span(&1, :start_time)),
        &(&1 |> span(:attributes) |> :otel_attributes.map() |> Map.fetch!(:"http.target"))
      )

    send(owner, {ref, :exported, paths})
    :ok
  end

  @impl true
  def shutdown(_state), do: :ok
end

defmodule OtlpShipper.TraceSuppressionProbe do
  @moduledoc false
  alias OtlpShipper.TraceProbeSampler
  alias OtlpShipper.TraceSuppressionExporter

  @name TraceSuppressionProvider
  @finch TraceSuppressionFinch
  @marker :otlp_shipper_probe_export
  @paths ["/ordinary-before", "/exporter", "/ordinary-after"]

  @doc false
  @spec run(:always_on | :always_off) :: {:ok, map()}
  def run(delegate) do
    owner = self()
    ref = make_ref()

    {:ok, supervisor} =
      Supervisor.start_link(children(delegate, owner, ref), strategy: :one_for_one)

    try do
      observe(supervisor, ref)
    after
      if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
    end
  end

  # The isolated provider owns a real SDK batch processor and a recording exporter.
  defp children(delegate, owner, ref) do
    resource = :otel_resource.create(%{"service.name" => "suppression-probe"})

    batch = %{
      name: @name,
      resource: resource,
      exporter: {TraceSuppressionExporter, {owner, ref}},
      scheduled_delay_ms: 60_000
    }

    options = %{
      id_generator: :otel_id_generator,
      sampler: {TraceProbeSampler, delegate},
      processors: [{:otel_batch_processor, batch}],
      deny_list: []
    }

    plug = fn conn, _ ->
      send(owner, {ref, :request, conn.request_path})
      Plug.Conn.send_resp(conn, 200, "ok")
    end

    [
      {Finch, name: @finch},
      Supervisor.child_spec({Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0, startup_log: false},
        id: Bandit
      ),
      %{
        id: @name,
        start: {:otel_tracer_server_sup, :start_link, [@name, resource, options]},
        type: :supervisor
      }
    ]
  end

  # Serial callers temporarily replace only the instrumentation's cached tracer.
  defp observe(supervisor, ref) do
    key = instrumentation_key()
    original = :persistent_term.get(key, :probe_absent)
    tracer = :otel_tracer_provider.get_tracer(@name, :suppression_probe, "1.0", :undefined)
    :persistent_term.put(key, tracer)

    try do
      :ok = OpentelemetryFinch.setup()

      try do
        result = run_requests(supervisor)
        # SDK 1.7 termination exports the retained table synchronously.
        Supervisor.stop(supervisor)
        {:ok, Map.merge(result, collect_observations(ref))}
      after
        :telemetry.detach({OpentelemetryFinch, :request_stop})
      end
    after
      restore_tracer(key, original)
    end
  end

  # Resolve the exact SDK/API 1.5 cache key, including its application version.
  defp instrumentation_key do
    apps = :persistent_term.get({:opentelemetry, :otel_module_to_application_key}, %{})
    scope = Map.get(apps, OpentelemetryFinch, :"$__default_tracer")
    {:opentelemetry, :global, :tracer, scope}
  end

  # Preserve absence as well as existing cached tracer values.
  defp restore_tracer(key, :probe_absent), do: :persistent_term.erase(key)
  defp restore_tracer(key, original), do: :persistent_term.put(key, original)

  # All requests execute in the same worker, so the last proves context restoration.
  defp run_requests(supervisor) do
    {_, server, _, _} =
      Enum.find(Supervisor.which_children(supervisor), fn {id, _, _, _} -> id == Bandit end)

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    task = Task.async(fn -> request_sequence("http://127.0.0.1:#{port}") end)

    case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> raise "suppression HTTP worker did not complete"
    end
  end

  # A seeded non-boolean value proves the marker is restored rather than erased.
  defp request_sequence(endpoint) do
    :otel_ctx.set_value(@marker, :original)
    before = :otel_ctx.get_value(@marker)
    first = request(endpoint, Enum.at(@paths, 0))
    second = marked_request(endpoint)
    after_marker = :otel_ctx.get_value(@marker)
    third = request(endpoint, Enum.at(@paths, 2))
    %{http_statuses: [first, second, third], marker_before: before, marker_after: after_marker}
  end

  # Bound the marker to the real HTTP request and its synchronous telemetry callback.
  defp marked_request(endpoint) do
    token = :otel_ctx.attach(:otel_ctx.set_value(:otel_ctx.get_current(), @marker, true))

    try do
      request(endpoint, Enum.at(@paths, 1))
    after
      :otel_ctx.detach(token)
    end
  end

  # Use the actual Finch transport and installed instrumentation on loopback only.
  defp request(endpoint, path) do
    {:ok, response} = Finch.build(:get, endpoint <> path) |> perform_request()
    response.status
  end

  # Keep the request timeout bounded independently of the worker deadline.
  defp perform_request(request), do: Finch.request(request, @finch, receive_timeout: 1_000)

  # Shutdown is a completion barrier, so no sleeps are needed to collect exports.
  defp collect_observations(ref, requests \\ [], exported \\ []) do
    receive do
      {^ref, :request, path} -> collect_observations(ref, [path | requests], exported)
      {^ref, :exported, paths} -> collect_observations(ref, requests, paths ++ exported)
    after
      0 -> %{request_paths: Enum.reverse(requests), exported_paths: exported}
    end
  end
end
