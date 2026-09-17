defmodule OtlpShipper.TraceSDKCallbackTest do
  @moduledoc false
  use OtlpShipper.CollectorCase, async: false

  alias OtlpShipper.{TraceExporter, TraceFixtures, TraceSDKFixtures}

  test "TSDK-01 initialization validates consumer ownership without mutating SDK configuration",
       context do
    sdk_before = Application.get_all_env(:opentelemetry)
    assert {:ok, state} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    assert TraceExporter.shutdown(state) == :ok
    assert Process.alive?(Process.whereis(context.finch))
    assert Application.get_all_env(:opentelemetry) == sdk_before

    for options <- [
          [],
          [pool: :missing_trace_sdk_pool],
          [pool: context.finch, timeout: 0],
          [pool: context.finch, service_name: "must-not-replace-sdk"],
          :invalid
        ] do
      assert TraceExporter.init(options) == :ignore
    end
  end

  test "TSDK-01 real SDK record export preserves resource and scope while leaving borrowed table intact",
       context do
    assert {:ok, state} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    table = TraceSDKFixtures.table([TraceSDKFixtures.record()])
    on_exit(fn -> if :ets.info(table) != :undefined, do: :ets.delete(table) end)
    task = Task.async(fn -> TraceExporter.export(table, TraceSDKFixtures.resource(), state) end)
    assert_receive {:export, server, "traces", _, request, _}, 1000
    [resource] = request.resource_spans
    assert resource.schema_url == "https://sdk/resource"

    assert %{key: "service.name", value: %{value: {:string_value, "sdk-authoritative"}}} in resource.resource.attributes

    assert [scope] = resource.scope_spans
    assert scope.scope.name == "sdk_scope"
    assert scope.schema_url == "https://sdk/scope"
    assert [%{trace_id: <<1::128>>, span_id: <<2::64>>, name: "sdk-span"}] = scope.spans
    send(server, {:respond, 200, [], ""})
    assert Task.await(task) == :ok
    assert :ets.info(table, :size) == 1
  end

  test "TSDK-01 callback outcomes distinguish warning rejection permanent and retryable failure",
       context do
    assert {:ok, state} =
             TraceExporter.init(
               pool: context.finch,
               base_endpoint: context.endpoint,
               max_retries: 0
             )

    table = TraceSDKFixtures.table([TraceSDKFixtures.record()])
    on_exit(fn -> if :ets.info(table) != :undefined, do: :ets.delete(table) end)

    for {status, response, expected} <- [
          {200, TraceFixtures.response(0, "warning"), :ok},
          {200, TraceFixtures.response(1), :failed_not_retryable},
          {401, "", :failed_not_retryable},
          {503, "", :failed_retryable}
        ] do
      task = Task.async(fn -> TraceExporter.export(table, TraceSDKFixtures.resource(), state) end)
      assert_receive {:export, server, "traces", _, _, _}, 1000
      send(server, {:respond, status, [], response})
      assert Task.await(task) == expected
    end
  end

  test "TSDK-01 malformed resource and invalid spans do not fabricate successful exports",
       context do
    assert {:ok, state} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    table = TraceSDKFixtures.table([TraceSDKFixtures.record(trace_id: 0)])
    on_exit(fn -> if :ets.info(table) != :undefined, do: :ets.delete(table) end)

    assert TraceExporter.export(table, TraceSDKFixtures.resource(), state) ==
             :failed_not_retryable

    assert TraceExporter.export(table, :invalid_resource, state) == :failed_not_retryable
    refute_receive {:export, _, "traces", _, _, _}, 20
  end
end
