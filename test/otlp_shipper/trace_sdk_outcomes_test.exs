defmodule OtlpShipper.TraceSDKOutcomesTest do
  @moduledoc false
  use OtlpShipper.CollectorCase, async: false

  alias OtlpShipper.{TraceExporter, TraceFixtures, TraceSDKFixtures, TraceSDKHarness}

  test "TSDK-03 the adapter's own deadline before acceptance returns failed_retryable", context do
    assert {:ok, state} =
             TraceExporter.init(
               pool: context.finch,
               base_endpoint: context.endpoint,
               timeout: 150
             )

    table = TraceSDKFixtures.table([TraceSDKFixtures.record()])
    on_exit(fn -> if :ets.info(table) != :undefined, do: :ets.delete(table) end)
    task = Task.async(fn -> TraceExporter.export(table, TraceSDKFixtures.resource(), state) end)
    assert_receive {:export, server, "traces", _, _, _}, 1000
    assert Task.await(task, 1000) == :failed_retryable
    send(server, {:respond, 200, [], ""})
  end

  test "TSDK-01 a transient failure after accepted data is not reported as retryable", context do
    assert {:ok, state} =
             TraceExporter.init(
               pool: context.finch,
               base_endpoint: context.endpoint,
               max_batch: 1,
               max_retries: 0
             )

    table =
      TraceSDKFixtures.table([
        TraceSDKFixtures.record(span_id: 1),
        TraceSDKFixtures.record(span_id: 2)
      ])

    on_exit(fn -> if :ets.info(table) != :undefined, do: :ets.delete(table) end)
    task = Task.async(fn -> TraceExporter.export(table, TraceSDKFixtures.resource(), state) end)

    for status <- [200, 503] do
      assert_receive {:export, server, "traces", _, request, _}, 1000
      assert [_] = TraceFixtures.spans(request)
      send(server, {:respond, status, [], ""})
    end

    assert Task.await(task) == :failed_not_retryable
    refute_receive {:export, _, "traces", _, _, _}, 30
  end

  test "TSDK-05 an actual recorded exception event and status survive SDK export", context do
    assert {:ok, _} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    instance = TraceSDKHarness.start(context.endpoint)
    on_exit(fn -> TraceSDKHarness.stop(instance) end)
    ref = instance.ref
    assert_receive {^ref, :initialized, {:ok, _}}, 1000

    span =
      :otel_tracer.start_span(
        :otel_ctx.new(),
        TraceSDKHarness.tracer(instance),
        "exception-operation",
        %{}
      )

    handled =
      try do
        raise "application failure"
      rescue
        error ->
          assert :otel_span.record_exception(
                   span,
                   :error,
                   error,
                   Exception.message(error),
                   __STACKTRACE__,
                   %{}
                 )

          :otel_span.set_status(span, :error, "application failure")
          :application_handled
      end

    assert handled == :application_handled
    :otel_span.end_span(span)
    TraceSDKHarness.flush(instance)
    assert_receive {:export, server, "traces", _, request, _}, 1000
    assert [exported] = TraceFixtures.spans(request)
    assert exported.status == %{code: :STATUS_CODE_ERROR, message: "application failure"}
    assert [%{name: "exception", attributes: attributes}] = exported.events
    values = Map.new(attributes, &{&1.key, &1.value.value})
    assert values["exception.message"] == {:string_value, "application failure"}
    assert {:string_value, type} = values["exception.type"]
    assert String.contains?(type, "RuntimeError")
    assert {:string_value, stacktrace} = values["exception.stacktrace"]
    assert byte_size(stacktrace) > 0
    send(server, {:respond, 200, [], ""})
    assert_receive {^ref, :returned, _, :ok}, 1000
  end
end
