defmodule OtlpShipper.TraceBatchTest do
  @moduledoc false
  use OtlpShipper.CollectorCase, async: false

  alias OtlpShipper.{Config, Encoder, TraceBatch, TraceFixtures, TraceRecord}

  test "TPC-04 batches span counts and accounts local invalid data once", context do
    assert {:ok, config} = trace_config(context.endpoint, max_batch: 1)
    invalid = TraceFixtures.span(%{trace_id: 0})
    records = [TraceFixtures.span(), invalid, TraceFixtures.span(%{span_id: 3})]
    attach_outcomes()
    task = export(config, context.finch, records, 3)

    for id <- [2, 3] do
      assert_receive {:export, server, "traces", _, request, _}, 1000
      assert [%{span_id: <<^id::64>>}] = TraceFixtures.spans(request)
      send(server, {:respond, 200, [], ""})
    end

    assert {:ok, summary} = Task.await(task)
    assert summary == %{accepted: 2, rejected: 0, invalid: 1, failed: 0, unsent: 0, requests: 2}
    assert drop_count(drain_outcomes()) == 1
  end

  test "TPC-04 full request bytes include resource and scope envelopes", context do
    input = TraceFixtures.span()
    assert {:ok, converted} = TraceRecord.convert(input, TraceFixtures.offset())
    assert {:ok, single} = Encoder.encode(:traces, [converted], TraceFixtures.resource())
    span_bytes = :otlp_shipper_trace_service.encode_msg(converted.span, TraceFixtures.span_type())
    assert byte_size(single) > byte_size(span_bytes)

    assert {:ok, config} =
             trace_config(context.endpoint,
               max_item_bytes: byte_size(span_bytes),
               max_batch_bytes: byte_size(single),
               max_batch: 10
             )

    task = export(config, context.finch, [input, TraceFixtures.span(%{span_id: 3})], 2)

    for _ <- 1..2 do
      assert_receive {:export, server, "traces", _, request, body}, 1000
      assert length(TraceFixtures.spans(request)) == 1
      assert byte_size(body) <= config.max_batch_bytes
      send(server, {:respond, 200, [], ""})
    end

    assert {:ok, %{accepted: 2, requests: 2}} = Task.await(task)
  end

  test "TPC-04 individually oversized spans are dropped without splitting", context do
    assert {:ok, config} = trace_config(context.endpoint, max_item_bytes: 128)
    input = [TraceFixtures.span(%{name: String.duplicate("x", 1000)}), TraceFixtures.span()]
    task = export(config, context.finch, input, 2)
    assert_receive {:export, server, "traces", _, request, _}, 1000
    assert [%{name: "operation"}] = TraceFixtures.spans(request)
    send(server, {:respond, 200, [], ""})
    assert {:ok, %{accepted: 1, invalid: 1, requests: 1}} = Task.await(task)
    refute_receive {:export, _, "traces", _, _, _}, 20
  end

  test "TPC-07 an accepted chunk is not replayed after a permanent failure", context do
    assert {:ok, config} = trace_config(context.endpoint, max_batch: 1)
    attach_outcomes()
    records = Enum.map(1..3, &TraceFixtures.span(%{span_id: &1}))
    task = export(config, context.finch, records, 3)

    for {id, status} <- [{1, 200}, {2, 401}] do
      assert_receive {:export, server, "traces", _, request, _}, 1000
      assert [%{span_id: <<^id::64>>}] = TraceFixtures.spans(request)
      send(server, {:respond, status, [], ""})
    end

    assert {:error, {:http_status, 401}, summary} = Task.await(task)
    assert summary == %{accepted: 1, rejected: 0, invalid: 0, failed: 1, unsent: 1, requests: 2}
    assert drop_count(drain_outcomes()) == 2
    refute_receive {:export, _, "traces", _, _, _}, 20
  end

  test "TPC-05 partial rejection is counted once and is not retried", context do
    assert {:ok, config} = trace_config(context.endpoint)
    attach_outcomes()

    task =
      export(config, context.finch, [TraceFixtures.span(), TraceFixtures.span(%{span_id: 3})], 2)

    assert_receive {:export, server, "traces", _, _, _}, 1000
    send(server, {:respond, 200, [], TraceFixtures.response(1, "one rejected")})
    assert {:ok, summary} = Task.await(task)
    assert summary == %{accepted: 1, rejected: 1, invalid: 0, failed: 0, unsent: 0, requests: 1}
    assert drop_count(drain_outcomes()) == 1
    refute_receive {:export, _, "traces", _, _, _}, 20
  end

  test "TPC-06 blocked lazy conversion before the first request is bounded and reaped", context do
    assert {:ok, config} = trace_config(context.endpoint, timeout: 100)
    owner = self()

    input =
      Stream.map([TraceFixtures.span()], fn span ->
        send(owner, {:conversion_worker, self()})

        receive do
          :release_conversion -> span
        end
      end)

    task = export(config, context.finch, input, 1)
    assert_receive {:conversion_worker, worker}, 1000
    monitor = Process.monitor(worker)
    assert {:error, :timeout, summary} = Task.await(task, 1000)
    assert summary == %{accepted: 0, rejected: 0, invalid: 0, failed: 0, unsent: 1, requests: 0}
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
    refute_receive {:export, _, "traces", _, _, _}, 20
  end

  test "TPC-06 blocked lazy suffix retains the first accepted chunk", context do
    assert {:ok, config} = trace_config(context.endpoint, max_batch: 1, timeout: 250)
    owner = self()

    input =
      Stream.map([1, 2], fn
        1 ->
          TraceFixtures.span(%{span_id: 1})

        2 ->
          send(owner, {:conversion_worker, self()})

          receive do
            :release_conversion -> TraceFixtures.span(%{span_id: 2})
          end
      end)

    task = export(config, context.finch, input, 2)
    assert_receive {:export, server, "traces", _, _, _}, 1000
    send(server, {:respond, 200, [], ""})
    assert_receive {:conversion_worker, worker}, 1000
    monitor = Process.monitor(worker)
    assert {:error, :timeout, summary} = Task.await(task, 1000)
    assert summary == %{accepted: 1, rejected: 0, invalid: 0, failed: 0, unsent: 1, requests: 1}
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
    refute_receive {:export, _, "traces", _, _, _}, 20
  end

  test "TPC-06 blocked outcome telemetry cannot erase a committed accepted chunk", context do
    assert {:ok, config} = trace_config(context.endpoint, max_batch: 1, timeout: 250)
    id = make_ref()
    :telemetry.attach(id, [:otlp_shipper, :export, :stop], &__MODULE__.block_outcome/4, self())
    on_exit(fn -> :telemetry.detach(id) end)

    task =
      export(config, context.finch, [TraceFixtures.span(), TraceFixtures.span(%{span_id: 3})], 2)

    assert_receive {:export, server, "traces", _, _, _}, 1000
    send(server, {:respond, 200, [], ""})
    assert_receive {:blocked_outcome, worker, %{count: 1}, %{signal: :traces}}, 1000
    monitor = Process.monitor(worker)
    assert {:error, :timeout, summary} = Task.await(task, 1000)
    assert summary == %{accepted: 1, rejected: 0, invalid: 0, failed: 0, unsent: 1, requests: 1}
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
    refute_receive {:blocked_outcome, _, _, _}, 20
    refute_receive {:export, _, "traces", _, _, _}, 20
  end

  test "TPC-07 late cardinality mismatch preserves delivery already completed", context do
    assert {:ok, config} = trace_config(context.endpoint, max_batch: 1)
    task = export(config, context.finch, Stream.map([TraceFixtures.span()], & &1), 2)
    assert_receive {:export, server, "traces", _, _, _}, 1000
    send(server, {:respond, 200, [], ""})
    assert {:error, :invalid_batch, summary} = Task.await(task)
    assert summary.accepted == 1
    assert summary.requests == 1
    refute_receive {:export, _, "traces", _, _, _}, 20
  end

  @doc false
  def block_outcome(_event, measurements, %{signal: :traces} = metadata, owner) do
    send(owner, {:blocked_outcome, self(), measurements, metadata})

    receive do
      :release_outcome -> :ok
    end
  end

  def block_outcome(_event, _measurements, _metadata, _owner), do: :ok

  @doc false
  def forward_outcome(event, measurements, metadata, owner),
    do: send(owner, {:trace_outcome, event, measurements, metadata})

  # Keep loopback timeouts finite while avoiding host environment configuration.
  defp trace_config(endpoint, options \\ []),
    do:
      Config.transport(
        :traces,
        Keyword.merge(
          [base_endpoint: endpoint, timeout: 1000, retry_base_ms: 1, retry_max_ms: 2],
          options
        ),
        %{}
      )

  # The outer task lets the test drive the actual HTTP collector responses.
  defp export(config, finch, input, count),
    do:
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

  # Observe logical outcomes without changing their synchronous execution contract.
  defp attach_outcomes do
    id = make_ref()

    :telemetry.attach_many(
      id,
      [[:otlp_shipper, :dropped], [:otlp_shipper, :export, :stop]],
      &__MODULE__.forward_outcome/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  # Drain messages after the export task has completed, when emission is finished.
  defp drain_outcomes do
    receive do
      {:trace_outcome, event, measurements, metadata} ->
        [{event, measurements, metadata} | drain_outcomes()]
    after
      0 -> []
    end
  end

  # Invalid and unsent spans belong to batch accounting; submitted losses to transport.
  defp drop_count(events) do
    for {[:otlp_shipper, :dropped], %{count: count}, %{signal: :traces}} <- events,
        reduce: 0 do
      total -> total + count
    end
  end
end
