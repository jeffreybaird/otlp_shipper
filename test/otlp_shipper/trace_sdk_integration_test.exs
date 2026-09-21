defmodule OtlpShipper.TraceSDKIntegrationTest do
  @moduledoc false
  use OtlpShipper.CollectorCase, async: false

  alias OtlpShipper.{
    TraceExporter,
    TraceFixtures,
    TraceRecordEvidence,
    TraceSDKFixtures,
    TraceSDKHarness
  }

  test "TSDK-02 real SDK metadata and losses survive generated trace export", context do
    assert {:ok, _} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)

    instance =
      TraceSDKHarness.start(context.endpoint,
        exporter: [max_item_bytes: 1_048_576, max_batch_bytes: 2_097_152]
      )

    on_exit(fn -> TraceSDKHarness.stop(instance) end)
    ref = instance.ref
    assert_receive {^ref, :initialized, {:ok, _}}, 1000
    limits = TraceRecordEvidence.emit(TraceSDKHarness.tracer(instance))
    assert TraceSDKHarness.flush(instance) == :ok
    assert_receive {^ref, :entered, worker, table, [record]}, 1000
    monitor = Process.monitor(worker)
    assert :ets.info(table, :owner) == worker
    assert_receive {:export, server, "traces", _, request, _}, 1000
    [span] = TraceFixtures.spans(request)
    assert span.trace_id == <<1::128>>
    assert span.parent_span_id == <<2::64>>
    assert span.name == "fidelity"
    assert span.kind == :SPAN_KIND_CLIENT
    assert span.status == %{code: :STATUS_CODE_ERROR, message: "probe failure"}
    assert span.trace_state == "vendor=value"
    assert span.flags == 769
    assert length(span.attributes) == limits.configured_attribute_limit
    assert span.dropped_attributes_count == 1
    assert length(span.events) == limits.configured_event_limit
    assert span.dropped_events_count == 1
    assert length(span.links) == limits.configured_link_limit
    assert span.dropped_links_count == 1
    assert hd(span.events).dropped_attributes_count == 1
    assert hd(span.links).dropped_attributes_count == 1
    observed = TraceRecordEvidence.describe(record, :otel_resource.create(%{}), limits)
    assert span.start_time_unix_nano == observed.start_unix_nano
    assert span.end_time_unix_nano == observed.end_unix_nano

    assert Enum.map(span.events, &{&1.name, &1.time_unix_nano}) ==
             TraceSDKFixtures.event_identities(record)

    assert Enum.map(span.links, &{&1.trace_id, &1.span_id}) ==
             TraceSDKFixtures.link_identities(record)

    send(server, {:respond, 200, [], ""})
    assert_receive {^ref, :returned, ^worker, :ok}, 1000
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1000
    assert :ets.info(table) == :undefined
  end

  test "TSDK-03 SDK cancellation destroys the borrowed table and stops retry work", context do
    assert {:ok, _} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)

    instance =
      TraceSDKHarness.start(context.endpoint, sdk_timeout: 100, exporter: [timeout: 2000])

    on_exit(fn -> TraceSDKHarness.stop(instance) end)
    ref = instance.ref
    assert_receive {^ref, :initialized, {:ok, _}}, 1000
    TraceSDKHarness.emit(instance, "cancelled")
    TraceSDKHarness.flush(instance)
    assert_receive {^ref, :entered, worker, table, [_]}, 1000
    monitor = Process.monitor(worker)
    assert_receive {:export, server, "traces", _, _, _}, 1000
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 1000
    assert :ets.info(table) == :undefined
    send(server, {:respond, 503, [], ""})
    refute_receive {:export, _, "traces", _, _, _}, 100
  end

  test "TSDK-04 flush return precedes HTTP completion and repeated flush does not replay",
       context do
    assert {:ok, _} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    instance = TraceSDKHarness.start(context.endpoint)
    on_exit(fn -> TraceSDKHarness.stop(instance) end)
    ref = instance.ref
    assert_receive {^ref, :initialized, {:ok, _}}, 1000
    TraceSDKHarness.emit(instance, "once")
    assert TraceSDKHarness.flush(instance) == :ok
    assert_receive {^ref, :entered, worker, _, [_]}, 1000
    assert_receive {:export, server, "traces", _, _, _}, 1000
    assert Process.alive?(worker)
    assert TraceSDKHarness.flush(instance) == :ok
    monitor = Process.monitor(worker)
    send(server, {:respond, 200, [], ""})
    assert_receive {^ref, :returned, ^worker, :ok}, 1000
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1000
    :sys.get_state(instance.processor)
    refute_receive {:export, _, "traces", _, _, _}, 30
  end

  test "TSDK-05 real nested spans and concurrent producers retain relationships and scope",
       context do
    assert {:ok, _} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    instance = TraceSDKHarness.start(context.endpoint)
    on_exit(fn -> TraceSDKHarness.stop(instance) end)
    ref = instance.ref
    assert_receive {^ref, :initialized, {:ok, _}}, 1000
    tracer = TraceSDKHarness.tracer(instance)
    root = :otel_tracer.start_span(:otel_ctx.new(), tracer, "root", %{})
    parent_context = :otel_tracer.set_current_span(:otel_ctx.new(), root)
    child = :otel_tracer.start_span(parent_context, tracer, "child", %{})
    :otel_span.end_span(child)
    :otel_span.end_span(root)

    tasks =
      for index <- 1..10,
          do: Task.async(fn -> TraceSDKHarness.emit(instance, "parallel-#{index}") end)

    Enum.each(tasks, &Task.await/1)
    other = TraceSDKHarness.tracer(instance, :other_scope, "2", "https://other/scope")
    other |> :otel_tracer.start_span("other", %{}) |> :otel_span.end_span()
    TraceSDKHarness.flush(instance)
    assert_receive {:export, server, "traces", _, request, _}, 1000
    spans = Map.new(TraceFixtures.spans(request), &{&1.name, &1})
    assert map_size(spans) == 13
    assert spans["root"].parent_span_id == ""
    assert spans["child"].parent_span_id == spans["root"].span_id
    assert spans["child"].trace_id == spans["root"].trace_id
    [resource] = request.resource_spans

    assert Enum.map(resource.scope_spans, & &1.schema_url) |> Enum.sort() == [
             "https://other/scope",
             "https://sdk/integration"
           ]

    send(server, {:respond, 200, [], ""})
    assert_receive {^ref, :returned, _, :ok}, 1000
  end

  test "TSDK-05 an always-off delegate does not export unsampled application work", context do
    assert {:ok, _} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    instance = TraceSDKHarness.start(context.endpoint, sampler: :always_off)
    on_exit(fn -> TraceSDKHarness.stop(instance) end)
    ref = instance.ref
    assert_receive {^ref, :initialized, {:ok, _}}, 1000
    TraceSDKHarness.emit(instance, "unsampled")
    TraceSDKHarness.flush(instance)
    :sys.get_state(instance.processor)
    refute_receive {:export, _, "traces", _, _, _}, 30
  end
end
