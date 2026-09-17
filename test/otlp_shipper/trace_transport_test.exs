defmodule OtlpShipper.TraceTransportTest do
  @moduledoc false
  use OtlpShipper.CollectorCase, async: false

  alias OtlpShipper.{Config, Encoder, TraceFixtures, TraceRecord, Transport}

  test "TPC-05 trace HTTP uses gzip headers and retries transient failures", %{
    endpoint: endpoint,
    finch: finch
  } do
    assert {:ok, config} =
             Config.transport(
               :traces,
               [
                 base_endpoint: endpoint,
                 compression: :gzip,
                 headers: [{"x-probe", "trace"}],
                 retry_base_ms: 1,
                 retry_max_ms: 2
               ],
               %{}
             )

    assert {:ok, record} = TraceRecord.convert(TraceFixtures.span(), TraceFixtures.offset())
    assert {:ok, body} = Encoder.encode(:traces, [record], TraceFixtures.resource())
    deadline = System.monotonic_time(:millisecond) + 1000
    task = Task.async(fn -> Transport.export_until(config, finch, body, 1, deadline) end)

    for status <- [503, 200] do
      assert_receive {:export, server, "traces", headers, decoded, ^body}, 1000
      assert {"content-encoding", "gzip"} in headers
      assert {"content-type", "application/x-protobuf"} in headers
      assert {"x-probe", "trace"} in headers
      assert [%{span_id: <<2::64>>}] = TraceFixtures.spans(decoded)
      send(server, {:respond, status, [], ""})
    end

    assert Task.await(task) == :ok
  end

  test "TPC-05 partial responses and invalid counts are not retried", %{
    endpoint: endpoint,
    finch: finch
  } do
    assert {:ok, config} = Config.transport(:traces, [base_endpoint: endpoint], %{})
    assert {:ok, record} = TraceRecord.convert(TraceFixtures.span(), TraceFixtures.offset())
    assert {:ok, body} = Encoder.encode(:traces, [record], TraceFixtures.resource())

    for {response, expected} <- [
          {TraceFixtures.response(0), :ok},
          {TraceFixtures.response(0, "warning"), {:ok, :partial, 0}},
          {TraceFixtures.response(1, "rejected"), {:ok, :partial, 1}},
          {TraceFixtures.response(2), {:error, :invalid_response}},
          {<<255>>, {:error, :invalid_response}}
        ] do
      task =
        Task.async(fn ->
          Transport.export_until(
            config,
            finch,
            body,
            1,
            System.monotonic_time(:millisecond) + 1000
          )
        end)

      assert_receive {:export, server, "traces", _, _, _}, 1000
      send(server, {:respond, 200, [], response})
      assert Task.await(task) == expected
      refute_receive {:export, _, "traces", _, _, _}, 20
    end
  end

  test "TPC-06 expired absolute deadlines never begin a request", %{
    endpoint: endpoint,
    finch: finch
  } do
    assert {:ok, config} = Config.transport(:traces, [base_endpoint: endpoint], %{})
    assert {:ok, record} = TraceRecord.convert(TraceFixtures.span(), TraceFixtures.offset())
    assert {:ok, body} = Encoder.encode(:traces, [record], TraceFixtures.resource())

    assert Transport.export_until(config, finch, body, 1, System.monotonic_time(:millisecond) - 1) ==
             {:error, :timeout}

    refute_receive {:export, _, "traces", _, _, _}, 20
  end

  test "TPC-05 response byte limits and permanent HTTP failures remain terminal", %{
    endpoint: endpoint,
    finch: finch
  } do
    assert {:ok, config} =
             Config.transport(:traces, [base_endpoint: endpoint, max_response_bytes: 8], %{})

    assert {:ok, record} = TraceRecord.convert(TraceFixtures.span(), TraceFixtures.offset())
    assert {:ok, body} = Encoder.encode(:traces, [record], TraceFixtures.resource())

    for {status, response, expected} <- [
          {401, "", {:error, :http_status, 401}},
          {200, String.duplicate("x", 9), {:error, :response_too_large}}
        ] do
      task =
        Task.async(fn ->
          Transport.export_until(
            config,
            finch,
            body,
            1,
            System.monotonic_time(:millisecond) + 1000
          )
        end)

      assert_receive {:export, server, "traces", _, _, _}, 1000
      send(server, {:respond, status, [], response})
      assert Task.await(task) == expected
      refute_receive {:export, _, "traces", _, _, _}, 20
    end
  end
end
