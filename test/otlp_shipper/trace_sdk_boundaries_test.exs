defmodule OtlpShipper.TraceSDKBoundariesTest do
  @moduledoc false
  use OtlpShipper.CollectorCase, async: false

  alias OtlpShipper.{TraceExporter, TraceSDKFixtures}

  test "TSDK-07 R6-01 blocking invalid-initialization diagnostics cannot hang the SDK",
       _context do
    id = make_ref()

    :telemetry.attach(
      id,
      [:otlp_shipper, :export, :exception],
      &__MODULE__.block_diagnostic/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(id) end)
    task = Task.async(fn -> TraceExporter.init([]) end)

    try do
      assert_receive {:diagnostic_worker, worker}, 1000
      monitor = Process.monitor(worker)
      assert Task.yield(task, 700) == {:ok, :ignore}
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
    after
      if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
    end
  end

  test "TSDK-07 R6-03 valid scope envelopes use the request budget rather than span budget",
       context do
    assert {:ok, state} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    schema = "https://scope/" <> String.duplicate("x", 300_000)

    record =
      TraceSDKFixtures.record(
        instrumentation_scope: {:instrumentation_scope, "large-scope", "1", schema}
      )

    table = TraceSDKFixtures.table([record])
    on_exit(fn -> if :ets.info(table) != :undefined, do: :ets.delete(table) end)
    task = Task.async(fn -> TraceExporter.export(table, TraceSDKFixtures.resource(), state) end)

    try do
      assert_receive {:export, server, "traces", _, request, body}, 1500
      assert byte_size(body) < 1_048_576
      assert [resource] = request.resource_spans
      assert [%{schema_url: ^schema, spans: [%{name: "sdk-span"}]}] = resource.scope_spans
      send(server, {:respond, 200, [], ""})
      assert Task.await(task, 1500) == :ok
    after
      if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
    end
  end

  test "TSDK-07 R6-02 SDK charlist resource schemas preserve meaning and respect request bounds",
       context do
    assert {:ok, state} =
             TraceExporter.init(
               pool: context.finch,
               base_endpoint: context.endpoint,
               max_batch_bytes: 1024,
               max_item_bytes: 512
             )

    table = TraceSDKFixtures.table([TraceSDKFixtures.record()])
    on_exit(fn -> if :ets.info(table) != :undefined, do: :ets.delete(table) end)
    valid = :otel_resource.create(%{}, ~c"https://charlist/resource")
    task = Task.async(fn -> TraceExporter.export(table, valid, state) end)
    assert_receive {:export, server, "traces", _, %{resource_spans: [resource]}, _}, 1000
    assert resource.schema_url == "https://charlist/resource"
    send(server, {:respond, 200, [], ""})
    assert Task.await(task) == :ok
    oversized = :otel_resource.create(%{}, List.duplicate(?x, 100_000))
    assert TraceExporter.export(table, oversized, state) == :failed_not_retryable
    refute_receive {:export, _, "traces", _, _, _}, 20
  end

  @doc false
  def block_diagnostic(
        _event,
        _measurements,
        %{signal: :traces, reason: :invalid_configuration},
        owner
      ) do
    send(owner, {:diagnostic_worker, self()})

    receive do
      :release_diagnostic -> :ok
    end
  end

  def block_diagnostic(_event, _measurements, _metadata, _owner), do: :ok
end
