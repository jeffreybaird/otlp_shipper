defmodule OtlpShipper.TraceSDKCorrelationTest do
  @moduledoc false
  use OtlpShipper.CollectorCase, async: false
  require Logger

  alias OtlpShipper.{LogHandler, TraceExporter, TraceFixtures, TraceSDKHarness}

  test "TSDK-05 logs correlate with delivered SDK spans and clear detached context", context do
    assert {:ok, _} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    instance = TraceSDKHarness.start(context.endpoint)
    on_exit(fn -> TraceSDKHarness.stop(instance) end)
    ref = instance.ref
    assert_receive {^ref, :initialized, {:ok, _}}, 1000

    start_supervised!(
      {LogHandler,
       service_name: "sdk-logs",
       base_endpoint: context.endpoint,
       max_batch: 1,
       flush_ms: 60_000,
       timeout: 1000,
       shutdown_ms: 100}
    )

    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)

    span =
      :otel_tracer.start_span(
        :otel_ctx.new(),
        TraceSDKHarness.tracer(instance),
        "correlated",
        %{}
      )

    token = :otel_ctx.attach(:otel_tracer.set_current_span(:otel_ctx.new(), span))

    try do
      Logger.info("sdk-inside")
    after
      :otel_ctx.detach(token)
      :otel_span.end_span(span)
    end

    Logger.info("sdk-outside")
    TraceSDKHarness.flush(instance)

    received =
      for _ <- 1..3 do
        assert_receive {:export, server, signal, _, request, _}, 1500
        send(server, {:respond, 200, [], ""})
        {signal, request}
      end

    [{"traces", request}] = Enum.filter(received, fn {signal, _} -> signal == "traces" end)
    assert [exported_span] = TraceFixtures.spans(request)

    logs =
      for {"logs", request} <- received,
          resource <- request.resource_logs,
          scope <- resource.scope_logs,
          record <- scope.log_records,
          into: %{},
          do: {elem(record.body.value, 1), record}

    assert logs["sdk-inside"].trace_id == exported_span.trace_id
    assert logs["sdk-inside"].span_id == exported_span.span_id
    assert logs["sdk-outside"].trace_id == ""
    assert logs["sdk-outside"].span_id == ""
  end
end
