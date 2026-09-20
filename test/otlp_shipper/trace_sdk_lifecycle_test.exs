defmodule OtlpShipper.TraceSDKLifecycleTest do
  @moduledoc false
  use OtlpShipper.CollectorCase, async: false

  alias OtlpShipper.{TraceExporter, TraceFixtures, TraceSDKHarness}

  test "TSDK-04 pool failure replaces dependent SDK processes and leaves another instance usable",
       context do
    assert {:ok, _} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    first = TraceSDKHarness.start(context.endpoint)
    second = TraceSDKHarness.start(context.endpoint)

    on_exit(fn ->
      TraceSDKHarness.stop(first)
      TraceSDKHarness.stop(second)
    end)

    first_ref = first.ref
    second_ref = second.ref
    assert_receive {^first_ref, :initialized, {:ok, _}}, 1000
    assert_receive {^second_ref, :initialized, {:ok, _}}, 1000
    old_provider = Process.whereis(first.provider)
    old_processor = Process.whereis(first.processor)
    survivor = Process.whereis(second.provider)
    pool = TraceSDKHarness.pool_pid(first)
    Process.exit(pool, :kill)
    assert_receive {^first_ref, :initialized, {:ok, _}}, 2000
    assert Process.whereis(first.provider) != old_provider
    assert Process.whereis(first.processor) != old_processor
    assert Process.whereis(second.provider) == survivor

    for {instance, name} <- [{first, "recovered"}, {second, "unaffected"}] do
      TraceSDKHarness.emit(instance, name)
      TraceSDKHarness.flush(instance)
      assert_receive {:export, server, "traces", _, request, _}, 1000
      assert [%{name: ^name}] = TraceFixtures.spans(request)
      send(server, {:respond, 200, [], ""})
      ref = instance.ref
      assert_receive {^ref, :returned, _, :ok}, 1000
    end
  end

  test "TSDK-04 reverse shutdown drains pending SDK spans before releasing the owned pool",
       context do
    assert {:ok, _} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    instance = TraceSDKHarness.start(context.endpoint)
    on_exit(fn -> TraceSDKHarness.stop(instance) end)
    ref = instance.ref
    assert_receive {^ref, :initialized, {:ok, _}}, 1000
    pool = TraceSDKHarness.pool_pid(instance)
    monitor = Process.monitor(pool)
    TraceSDKHarness.emit(instance, "shutdown-span")
    stopper = Task.async(fn -> TraceSDKHarness.stop(instance) end)
    assert_receive {:export, server, "traces", _, request, _}, 1000
    assert Process.alive?(pool)
    assert [%{name: "shutdown-span"}] = TraceFixtures.spans(request)
    send(server, {:respond, 200, [], ""})
    assert Task.await(stopper, 2000) == :ok
    assert_receive {:DOWN, ^monitor, :process, ^pool, :shutdown}, 1000
    refute_receive {^ref, :shutdown, _}, 20
  end
end
