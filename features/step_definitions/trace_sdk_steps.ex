defmodule OtlpShipper.Acceptance.TraceSDKSteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions
  require Logger

  alias OtlpShipper.{
    LogHandler,
    TestCollector,
    TraceExporter,
    TraceFixtures,
    TraceSampler,
    TraceSDKFixtures,
    TraceSDKHarness
  }

  when_("I initialize and shut down the SDK exporter with a consumer-owned pool", fn world ->
    evidence =
      with_collector(fn endpoint, pool ->
        assert {:ok, state} = TraceExporter.init(pool: pool, base_endpoint: endpoint)
        %{shutdown: TraceExporter.shutdown(state), alive: Process.alive?(Process.whereis(pool))}
      end)

    Map.put(world, :sdk_lifecycle, evidence)
  end)

  then_("initialization succeeds and shutdown leaves that pool alive", fn world ->
    assert world.sdk_lifecycle == %{shutdown: :ok, alive: true}
    world
  end)

  when_("a named SDK provider exports a completed span through shipper", fn world ->
    request =
      with_collector(fn endpoint, pool ->
        assert {:ok, _} = TraceExporter.init(pool: pool, base_endpoint: endpoint)
        instance = TraceSDKHarness.start(endpoint)
        ref = instance.ref

        try do
          assert_receive {^ref, :initialized, {:ok, _}}, 1000
          TraceSDKHarness.emit(instance, "sdk-acceptance")
          assert TraceSDKHarness.flush(instance) == :ok
          assert_receive {:export, server, "traces", _, request, _}, 1000
          send(server, {:respond, 200, [], ""})
          assert_receive {^ref, :returned, _, :ok}, 1000
          request
        after
          TraceSDKHarness.stop(instance)
        end
      end)

    Map.put(world, :sdk_request, request)
  end)

  then_(
    "the collector receives the span under the SDK resource and instrumentation scope",
    fn world ->
      assert [resource] = world.sdk_request.resource_spans
      assert resource.schema_url == "https://sdk/resource"

      assert %{key: "service.name", value: %{value: {:string_value, "sdk-authoritative"}}} in resource.resource.attributes

      assert [scope] = resource.scope_spans
      assert scope.scope.name == "sdk_integration"
      assert scope.schema_url == "https://sdk/integration"
      assert [%{name: "sdk-acceptance"}] = scope.spans
      world
    end
  )

  when_("the collector rejects the span in a real SDK record batch", fn world ->
    result =
      with_collector(fn endpoint, pool ->
        assert {:ok, state} = TraceExporter.init(pool: pool, base_endpoint: endpoint)
        table = TraceSDKFixtures.table([TraceSDKFixtures.record()])

        task =
          Task.async(fn -> TraceExporter.export(table, TraceSDKFixtures.resource(), state) end)

        try do
          assert_receive {:export, server, "traces", _, _, _}, 1000
          send(server, {:respond, 200, [], TraceFixtures.response(1)})
          Task.await(task, 1000)
        after
          if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
          :ets.delete(table)
        end
      end)

    Map.put(world, :sdk_rejection, result)
  end)

  then_("the exporter reports the SDK permanent-failure callback result", fn world ->
    assert world.sdk_rejection == :failed_not_retryable
    world
  end)

  when_("I sample ordinary and exporter-marked work with the {string} delegate", fn world, name ->
    delegate = delegate_name(name)
    configured = TraceSampler.setup(delegate)
    ordinary = :otel_ctx.new()
    marked = :otel_ctx.set_value(ordinary, :otlp_shipper_export, true)

    sample = fn context ->
      TraceSampler.should_sample(context, 1, [], "work", :client, %{}, configured)
    end

    expected =
      :otel_sampler.should_sample(
        :otel_sampler.new(delegate),
        ordinary,
        1,
        [],
        "work",
        :client,
        %{}
      )

    Map.put(world, :sampler_evidence, %{
      ordinary: sample.(ordinary),
      marked: sample.(marked),
      expected: expected
    })
  end)

  then_(
    "ordinary work keeps the delegate decision and exporter-marked work is dropped",
    fn world ->
      assert world.sampler_evidence.ordinary == world.sampler_evidence.expected
      assert {:drop, [], _} = world.sampler_evidence.marked
      world
    end
  )

  when_("the SDK cancels a shipper export waiting for the collector", fn world ->
    result =
      with_collector(fn endpoint, _pool ->
        instance = TraceSDKHarness.start(endpoint, sdk_timeout: 100, exporter: [timeout: 2000])
        ref = instance.ref

        try do
          assert_receive {^ref, :initialized, {:ok, _}}, 1000
          TraceSDKHarness.emit(instance, "cancelled")
          TraceSDKHarness.flush(instance)
          assert_receive {^ref, :entered, worker, table, [_]}, 1000
          monitor = Process.monitor(worker)
          assert_receive {:export, server, "traces", _, _, _}, 1000
          assert_receive {:DOWN, ^monitor, :process, ^worker, reason}, 1000
          send(server, {:respond, 503, [], ""})
          refute_receive {:export, _, "traces", _, _, _}, 50
          %{reason: reason, table: :ets.info(table)}
        after
          TraceSDKHarness.stop(instance)
        end
      end)

    Map.put(world, :sdk_cancelled, result)
  end)

  then_("its export worker is killed and the borrowed table is deleted", fn world ->
    assert world.sdk_cancelled == %{reason: :killed, table: :undefined}
    world
  end)

  when_("I flush a real provider again before the first HTTP response completes", fn world ->
    result =
      with_collector(fn endpoint, _pool ->
        instance = TraceSDKHarness.start(endpoint)
        ref = instance.ref

        try do
          assert_receive {^ref, :initialized, {:ok, _}}, 1000
          TraceSDKHarness.emit(instance, "once")
          assert TraceSDKHarness.flush(instance) == :ok
          assert_receive {^ref, :entered, worker, _, [_]}, 1000
          assert_receive {:export, server, "traces", _, _, _}, 1000
          alive_before = Process.alive?(worker)
          repeated = TraceSDKHarness.flush(instance)
          monitor = Process.monitor(worker)
          send(server, {:respond, 200, [], ""})
          assert_receive {^ref, :returned, ^worker, :ok}, 1000
          assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1000
          :sys.get_state(instance.processor)
          refute_receive {:export, _, "traces", _, _, _}, 30
          %{alive_before: alive_before, repeated: repeated}
        after
          TraceSDKHarness.stop(instance)
        end
      end)

    Map.put(world, :sdk_flush, result)
  end)

  then_("flush returns before delivery and the accepted span is not replayed", fn world ->
    assert world.sdk_flush == %{alive_before: true, repeated: :ok}
    world
  end)

  when_("I log inside a shipped SDK span and after detaching its context", fn world ->
    Map.put(world, :sdk_correlation, with_collector(&correlated_logs/2))
  end)

  then_(
    "the first log matches the shipped span and the later log has no inherited IDs",
    fn world ->
      %{span: span, logs: logs} = world.sdk_correlation
      assert logs["acceptance-inside"].trace_id == span.trace_id
      assert logs["acceptance-inside"].span_id == span.span_id
      assert logs["acceptance-outside"].trace_id == ""
      assert logs["acceptance-outside"].span_id == ""
      world
    end
  )

  when_("an invalid exporter configuration invokes a blocking diagnostic subscriber", fn world ->
    handler = make_ref()

    :telemetry.attach(
      handler,
      [:otlp_shipper, :export, :exception],
      &__MODULE__.block_diagnostic/4,
      self()
    )

    task = Task.async(fn -> TraceExporter.init([]) end)

    try do
      assert_receive {:sdk_diagnostic, worker}, 1000
      monitor = Process.monitor(worker)
      result = Task.yield(task, 700)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
      Map.put(world, :sdk_initialization_result, result)
    after
      :telemetry.detach(handler)
      if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
    end
  end)

  then_(
    "initialization returns ignore and its diagnostic worker terminates within the bound",
    fn world ->
      assert world.sdk_initialization_result == {:ok, :ignore}
      world
    end
  )

  @doc false
  def block_diagnostic(_event, _measurements, %{signal: :traces}, owner) do
    send(owner, {:sdk_diagnostic, self()})

    receive do
      :release_diagnostic -> :ok
    end
  end

  def block_diagnostic(_event, _measurements, _metadata, _owner), do: :ok

  # Only the named fixture samplers become atoms.
  defp delegate_name("always_on"), do: :always_on
  defp delegate_name("always_off"), do: :always_off

  # Exercise Logger and SDK public operations against the same local collector.
  defp correlated_logs(endpoint, _pool) do
    instance = TraceSDKHarness.start(endpoint)
    ref = instance.ref
    assert_receive {^ref, :initialized, {:ok, _}}, 1000

    {:ok, handler} =
      LogHandler.start_link(
        service_name: "acceptance-logs",
        base_endpoint: endpoint,
        max_batch: 1,
        flush_ms: 60_000,
        timeout: 1000,
        shutdown_ms: 100
      )

    level = Logger.level()
    Logger.configure(level: :info)

    try do
      span =
        :otel_tracer.start_span(
          :otel_ctx.new(),
          TraceSDKHarness.tracer(instance),
          "correlated",
          %{}
        )

      token = :otel_ctx.attach(:otel_tracer.set_current_span(:otel_ctx.new(), span))

      try do
        Logger.info("acceptance-inside")
      after
        :otel_ctx.detach(token)
        :otel_span.end_span(span)
      end

      Logger.info("acceptance-outside")
      TraceSDKHarness.flush(instance)

      requests =
        for _ <- 1..3 do
          assert_receive {:export, server, signal, _, request, _}, 1500
          send(server, {:respond, 200, [], ""})
          {signal, request}
        end

      [{"traces", trace}] = Enum.filter(requests, fn {signal, _} -> signal == "traces" end)
      [span] = TraceFixtures.spans(trace)

      logs =
        for {"logs", request} <- requests,
            resource <- request.resource_logs,
            scope <- resource.scope_logs,
            record <- scope.log_records,
            into: %{},
            do: {elem(record.body.value, 1), record}

      %{span: span, logs: logs}
    after
      Logger.configure(level: level)
      Supervisor.stop(handler)
      TraceSDKHarness.stop(instance)
    end
  end

  # Bound all fixture server and pool resources to this acceptance scenario.
  defp with_collector(fun) do
    owner = self()
    pool = Module.concat(__MODULE__, "Pool#{System.unique_integer([:positive])}")

    plug = fn conn, _ ->
      conn |> Plug.Conn.put_private(:owner, owner) |> TestCollector.call(TestCollector.init([]))
    end

    collector =
      Supervisor.child_spec({Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0, startup_log: false},
        id: :sdk_collector
      )

    {:ok, supervisor} =
      Supervisor.start_link([{Finch, name: pool}, collector], strategy: :one_for_one)

    try do
      {_, server, _, _} =
        Enum.find(Supervisor.which_children(supervisor), fn {id, _, _, _} ->
          id == :sdk_collector
        end)

      {:ok, {_, port}} = ThousandIsland.listener_info(server)
      fun.("http://127.0.0.1:#{port}", pool)
    after
      Supervisor.stop(supervisor)
    end
  end
end
