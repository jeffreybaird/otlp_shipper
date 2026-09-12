defmodule OtlpShipper.BufferTest do
  use ExUnit.Case, async: true
  alias OtlpShipper.{Buffer, Config}

  defp start_buffer(overrides \\ [], export \\ nil) do
    owner = self()

    {:ok, config} =
      Config.new(
        :logs,
        Keyword.merge(
          [
            service_name: "buffer",
            max_queue: 10,
            max_batch: 3,
            flush_ms: 10_000,
            timeout: 1000,
            shutdown_ms: 100
          ],
          overrides
        )
      )

    export =
      export ||
        fn items ->
          send(owner, {:batch, self(), items})
          :ok
        end

    pid = start_supervised!({Buffer, config: config, export: export})
    {pid, Buffer.handle(pid)}
  end

  test "flushes on batch size and explicit request" do
    {_pid, handle} = start_buffer()
    assert :ok = Buffer.enqueue(handle, :one)
    assert :ok = Buffer.enqueue(handle, :two)
    refute_receive {:batch, _, _}, 0
    assert :ok = Buffer.enqueue(handle, :three)
    assert_receive {:batch, _, [:one, :two, :three]}
    assert :ok = Buffer.enqueue(handle, :four)
    assert :ok = Buffer.flush(handle)
    assert_receive {:batch, _, [:four]}
  end

  test "flushes a partial batch on the interval" do
    {_pid, handle} = start_buffer(flush_ms: 10)
    :ok = Buffer.enqueue(handle, :one)
    assert_receive {:batch, _, [:one]}
  end

  test "10,000 events stay bounded with coalesced wakeups and exact drops" do
    owner = self()

    export = fn items ->
      send(owner, {:batch, self(), items})

      receive do
        :release -> :ok
      end
    end

    {pid, handle} = start_buffer([], export)
    for i <- 1..3, do: Buffer.enqueue(handle, i)
    assert_receive {:batch, worker, [1, 2, 3]}
    id = make_ref()
    counter = :atomics.new(1, [])

    :ok =
      :telemetry.attach(
        id,
        [:otlp_shipper, :dropped],
        &__MODULE__.count_drops/4,
        {self(), counter}
      )

    on_exit(fn -> :telemetry.detach(id) end)
    :sys.suspend(pid)

    try do
      for i <- 1..10_000, do: assert(:ok = Buffer.enqueue(handle, i))
      assert Buffer.size(handle) == 10
      assert :atomics.get(counter, 1) == 9990
      assert {:message_queue_len, length} = Process.info(pid, :message_queue_len)
      assert length <= 1
    after
      :sys.resume(pid)
    end

    send(worker, :release)
    assert_receive {:batch, worker, [9991, 9992, 9993]}
    send(worker, :release)
    assert_receive {:batch, worker, [9994, 9995, 9996]}
    send(worker, :release)
    assert_receive {:batch, worker, [9997, 9998, 9999]}
    send(worker, :release)
    Buffer.flush(handle)
    assert_receive {:batch, worker, [10_000]}
    send(worker, :release)
  end

  test "concurrent producers cannot grow ingress beyond its capacity" do
    {pid, handle} = start_buffer()
    :sys.suspend(pid)

    try do
      1..20
      |> Task.async_stream(
        fn producer -> for i <- 1..500, do: Buffer.enqueue(handle, {producer, i}) end,
        max_concurrency: 20
      )
      |> Enum.each(fn {:ok, results} -> assert Enum.all?(results, &(&1 == :ok)) end)

      assert Buffer.size(handle) == 10
      assert {:message_queue_len, length} = Process.info(pid, :message_queue_len)
      assert length <= 1
    after
      :sys.resume(pid)
    end
  end

  test "rejects oversized items and respects batch byte budgets" do
    {_pid, handle} = start_buffer(max_item_bytes: 20, max_batch_bytes: 25)
    assert {:error, :item_too_large} = Buffer.enqueue(handle, String.duplicate("x", 100))
    for _ <- 1..3, do: Buffer.enqueue(handle, "1234567890")
    assert_receive {:batch, _, ["1234567890"]}
    Buffer.flush(handle)
    assert_receive {:batch, _, ["1234567890"]}
  end

  test "callback exceptions do not kill the buffer" do
    owner = self()

    {pid, handle} =
      start_buffer([], fn items ->
        send(owner, {:attempt, items})
        raise "synthetic"
      end)

    for i <- 1..3, do: Buffer.enqueue(handle, i)
    assert_receive {:attempt, [1, 2, 3]}
    for i <- 4..6, do: Buffer.enqueue(handle, i)
    assert_receive {:attempt, [4, 5, 6]}
    assert Process.alive?(pid)
  end

  test "worker deadline kills stuck work and permits another batch" do
    owner = self()

    {_pid, handle} =
      start_buffer([timeout: 20], fn items ->
        send(owner, {:stuck, self(), items})

        receive do
          :never -> :ok
        end
      end)

    for i <- 1..3, do: Buffer.enqueue(handle, i)
    assert_receive {:stuck, worker, [1, 2, 3]}
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    for i <- 4..6, do: Buffer.enqueue(handle, i)
    assert_receive {:stuck, _, [4, 5, 6]}
  end

  test "shutdown flushes queued items and closes old handles" do
    {pid, handle} = start_buffer()
    Buffer.enqueue(handle, :pending)
    assert :ok = stop_supervised(Buffer)
    assert_receive {:batch, _, [:pending]}
    refute Process.alive?(pid)
    assert {:error, :closed} = Buffer.enqueue(handle, :late)
    assert Buffer.size(handle) == 0
  end

  test "shutdown is bounded even when the callback does not return" do
    owner = self()

    {_pid, handle} =
      start_buffer([shutdown_ms: 20], fn _ ->
        send(owner, {:stuck, self()})

        receive do
          :never -> :ok
        end
      end)

    Buffer.enqueue(handle, :pending)
    assert :ok = stop_supervised(Buffer)
    assert_receive {:stuck, worker}
    refute Process.alive?(worker)
  end

  test "invalid initialization is rejected" do
    assert {:error, {:error, :invalid_buffer_options}} = Buffer.start_link([])
  end

  @doc false
  def count_drops(_event, %{count: count}, %{reason: :queue_full}, {source, counter}) do
    if self() == source, do: :atomics.add(counter, 1, count)
  end

  def count_drops(_, _, _, _), do: :ok
end
