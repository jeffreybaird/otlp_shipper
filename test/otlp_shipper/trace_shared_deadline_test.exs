defmodule OtlpShipper.TraceSharedDeadlineTest do
  @moduledoc false
  use OtlpShipper.CollectorCase, async: false

  alias OtlpShipper.{Config, Encoder, TraceBatch, TraceFixtures, TraceRecord, Transport}

  test "TPC-06 active HTTP is bounded by an earlier caller deadline", context do
    assert {:ok, config} =
             Config.transport(:traces, [base_endpoint: context.endpoint, timeout: 2000], %{})

    assert {:ok, record} = TraceRecord.convert(TraceFixtures.span(), TraceFixtures.offset())
    assert {:ok, body} = Encoder.encode(:traces, [record], TraceFixtures.resource())
    started = System.monotonic_time(:millisecond)

    task =
      Task.async(fn -> Transport.export_until(config, context.finch, body, 1, started + 150) end)

    assert_receive {:export, server, "traces", _, _, _}, 1000
    assert Task.await(task, 1000) == {:error, :timeout}
    assert System.monotonic_time(:millisecond) - started < 800
    send(server, {:respond, 200, [], ""})
  end

  test "TPC-06 later chunks share time already consumed by a successful request", context do
    assert {:ok, config} =
             Config.transport(
               :traces,
               [base_endpoint: context.endpoint, max_batch: 1, timeout: 500],
               %{}
             )

    started = System.monotonic_time(:millisecond)

    task =
      Task.async(fn ->
        TraceBatch.export(
          config,
          context.finch,
          [TraceFixtures.span(), TraceFixtures.span(%{span_id: 3})],
          TraceFixtures.resource(),
          TraceFixtures.offset(),
          2
        )
      end)

    assert_receive {:export, first, "traces", _, _, _}, 1000
    # Simulate real collector latency, deliberately spending part of the single budget.
    receive do
      :unexpected_test_message -> flunk("unexpected message while delaying collector response")
    after
      300 -> send(first, {:respond, 200, [], ""})
    end

    assert_receive {:export, second, "traces", _, _, _}, 1000
    assert {:error, :timeout, summary} = Task.await(task, 1000)
    assert System.monotonic_time(:millisecond) - started < 700
    assert summary == %{accepted: 1, rejected: 0, invalid: 0, failed: 1, unsent: 0, requests: 2}
    send(second, {:respond, 200, [], ""})
  end

  test "TPC-06 Retry-After beyond the remaining budget causes no second attempt", context do
    assert {:ok, config} =
             Config.transport(:traces, [base_endpoint: context.endpoint, timeout: 1000], %{})

    assert {:ok, record} = TraceRecord.convert(TraceFixtures.span(), TraceFixtures.offset())
    assert {:ok, body} = Encoder.encode(:traces, [record], TraceFixtures.resource())

    task =
      Task.async(fn ->
        Transport.export_until(
          config,
          context.finch,
          body,
          1,
          System.monotonic_time(:millisecond) + 150
        )
      end)

    assert_receive {:export, server, "traces", _, _, _}, 1000
    send(server, {:respond, 503, [{"retry-after", "1"}], ""})
    assert Task.await(task, 1000) == {:error, :timeout}
    refute_receive {:export, _, "traces", _, _, _}, 20
  end
end
