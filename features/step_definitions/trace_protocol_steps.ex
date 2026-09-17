defmodule OtlpShipper.Acceptance.TraceProtocolSteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions

  alias OtlpShipper.{
    Config,
    Encoder,
    TestCollector,
    TraceBatch,
    TraceFixtures,
    TraceRecord,
    Transport
  }

  when_("I resolve a trace base endpoint with no service identity", fn world ->
    assert {:ok, config} =
             Config.transport(:traces, [base_endpoint: "https://collector.example/prefix"], %{})

    Map.put(world, :trace_config, config)
  end)

  then_("the transport uses the trace path and has no generated resource", fn world ->
    assert world.trace_config.endpoint == "https://collector.example/prefix/v1/traces"
    assert world.trace_config.resource == nil
    world
  end)

  when_("I convert a normalized trace span with its explicit clock offset", fn world ->
    assert {:ok, converted} = TraceRecord.convert(TraceFixtures.span(), TraceFixtures.offset())
    Map.put(world, :trace_record, converted)
  end)

  then_("the converted span preserves its IDs and Unix nanosecond timestamps", fn world ->
    assert world.trace_record.span.trace_id == <<1::128>>
    assert world.trace_record.span.span_id == <<2::64>>
    assert world.trace_record.span.parent_span_id == ""
    assert world.trace_record.span.start_time_unix_nano == 1_700_000_000_000_000_000
    assert world.trace_record.span.end_time_unix_nano == 1_700_000_000_010_000_000
    world
  end)

  then_("an invalid trace ID returns a field-specific error", fn world ->
    assert TraceRecord.convert(TraceFixtures.span(%{trace_id: 0}), TraceFixtures.offset()) ==
             {:error, :invalid_span, :trace_id}

    world
  end)

  when_("I encode normalized spans from two original instrumentation scopes", fn world ->
    first = TraceFixtures.span()

    second =
      TraceFixtures.span(%{scope: %{name: "other", version: "2", schema_url: "https://other"}})

    converted =
      Enum.map([first, second], fn input ->
        assert {:ok, item} = TraceRecord.convert(input, TraceFixtures.offset())
        item
      end)

    assert {:ok, body} = Encoder.encode(:traces, converted, TraceFixtures.resource())
    Map.put(world, :trace_request, TraceFixtures.decode(body))
  end)

  then_(
    "the decoded request retains both scope schemas and the authoritative resource",
    fn world ->
      assert [envelope] = world.trace_request.resource_spans
      assert envelope.schema_url == "https://schema/resource"

      assert %{key: "service.name", value: %{value: {:string_value, "sdk-service"}}} in envelope.resource.attributes

      assert Enum.map(envelope.scope_spans, &{&1.scope.name, &1.schema_url}) |> Enum.sort() ==
               [{"example", "https://schema/scope"}, {"other", "https://other"}]

      world
    end
  )

  when_("I export two normalized spans with one span allowed per request", fn world ->
    Map.put(world, :http_evidence, run_batch(2, 1, [{200, ""}, {200, ""}]))
  end)

  then_("the collector receives two valid trace requests and both spans are accepted", fn world ->
    assert {:ok, %{accepted: 2, rejected: 0, invalid: 0, failed: 0, unsent: 0, requests: 2}} =
             world.http_evidence.result

    assert Enum.map(world.http_evidence.requests, &length(TraceFixtures.spans(&1))) == [1, 1]
    world
  end)

  when_("I export two spans to a collector rejecting one span", fn world ->
    Map.put(world, :http_evidence, run_batch(2, 2, [{200, TraceFixtures.response(1)}]))
  end)

  then_(
    "the trace outcome contains one accepted and one rejected span in one request",
    fn world ->
      assert {:ok, %{accepted: 1, rejected: 1, invalid: 0, failed: 0, unsent: 0, requests: 1}} =
               world.http_evidence.result

      assert length(world.http_evidence.requests) == 1
      world
    end
  )

  when_("I submit an encoded trace request after its absolute deadline", fn world ->
    result =
      with_collector(fn endpoint, finch ->
        assert {:ok, config} = Config.transport(:traces, [base_endpoint: endpoint], %{})

        assert {:ok, converted} =
                 TraceRecord.convert(TraceFixtures.span(), TraceFixtures.offset())

        assert {:ok, body} = Encoder.encode(:traces, [converted], TraceFixtures.resource())

        result =
          Transport.export_until(config, finch, body, 1, System.monotonic_time(:millisecond) - 1)

        refute_receive {:export, _, "traces", _, _, _}, 20
        result
      end)

    Map.put(world, :expired_result, result)
  end)

  then_("the transport reports a timeout without starting HTTP", fn world ->
    assert world.expired_result == {:error, :timeout}
    world
  end)

  when_("I export three spans and the second request fails permanently", fn world ->
    Map.put(world, :http_evidence, run_batch(3, 1, [{200, ""}, {401, ""}]))
  end)

  then_(
    "the outcome preserves one accepted span and counts one failed and one unsent span",
    fn world ->
      assert {:error, {:http_status, 401},
              %{accepted: 1, rejected: 0, invalid: 0, failed: 1, unsent: 1, requests: 2}} =
               world.http_evidence.result

      assert length(world.http_evidence.requests) == 2
      world
    end
  )

  # Drive actual loopback requests while the batch export runs in its caller task.
  defp run_batch(count, max_batch, replies) do
    with_collector(fn endpoint, finch ->
      assert {:ok, config} =
               Config.transport(
                 :traces,
                 [base_endpoint: endpoint, max_batch: max_batch, timeout: 1000],
                 %{}
               )

      input = Enum.map(1..count, &TraceFixtures.span(%{span_id: &1}))

      task =
        Task.async(fn ->
          TraceBatch.export(
            config,
            finch,
            input,
            TraceFixtures.resource(),
            TraceFixtures.offset(),
            count
          )
        end)

      try do
        requests =
          Enum.map(replies, fn {status, response} ->
            assert_receive {:export, server, "traces", headers, request, _}, 1000
            assert {"content-type", "application/x-protobuf"} in headers
            send(server, {:respond, status, [], response})
            request
          end)

        result = Task.await(task, 1500)
        refute_receive {:export, _, "traces", _, _, _}, 20
        %{result: result, requests: requests}
      after
        if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
      end
    end)
  end

  # Own both loopback server and Finch under one temporary supervisor per scenario.
  defp with_collector(fun) do
    owner = self()
    finch = Module.concat(__MODULE__, "Pool#{System.unique_integer([:positive])}")

    plug = fn conn, _ ->
      conn
      |> Plug.Conn.put_private(:owner, owner)
      |> TestCollector.call(TestCollector.init([]))
    end

    children = [
      {Finch, name: finch},
      Supervisor.child_spec(
        {Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0, startup_log: false},
        id: :trace_collector
      )
    ]

    {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)

    try do
      {_, server, _, _} =
        Enum.find(Supervisor.which_children(supervisor), fn {id, _, _, _} ->
          id == :trace_collector
        end)

      {:ok, {_, port}} = ThousandIsland.listener_info(server)
      fun.("http://127.0.0.1:#{port}", finch)
    after
      Supervisor.stop(supervisor)
    end
  end
end
