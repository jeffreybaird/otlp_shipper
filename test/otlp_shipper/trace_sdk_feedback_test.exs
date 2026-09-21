defmodule OtlpShipper.TraceSDKFeedbackTest do
  @moduledoc false
  use OtlpShipper.CollectorCase, async: false

  alias OtlpShipper.{TraceExporter, TraceFixtures, TraceSDKHarness}

  test "TSDK-06 actual instrumented export HTTP is suppressed while ordinary requests remain sampled",
       context do
    assert {:ok, _} = TraceExporter.init(pool: context.finch, base_endpoint: context.endpoint)
    instance = TraceSDKHarness.start(context.endpoint)
    on_exit(fn -> TraceSDKHarness.stop(instance) end)
    ref = instance.ref
    assert_receive {^ref, :initialized, {:ok, _}}, 1000

    ordinary =
      start_supervised!(
        {Bandit,
         plug: fn conn, _ -> Plug.Conn.send_resp(conn, 200, "ok") end,
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(ordinary)
    key = instrumentation_key()
    previous = :persistent_term.get(key, :sdk_absent)
    :persistent_term.put(key, TraceSDKHarness.tracer(instance, :finch_sdk_test))
    :ok = OpentelemetryFinch.setup()
    marker_handler = make_ref()

    :ok =
      :telemetry.attach(
        marker_handler,
        [:finch, :request, :start],
        &__MODULE__.capture_marker/4,
        self()
      )

    try do
      for path <- ["/ordinary-before", "/ordinary-after"] do
        assert {:ok, %{status: 200}} =
                 Finch.request(
                   Finch.build(:get, "http://127.0.0.1:#{port}" <> path),
                   instance.pool
                 )

        assert TraceSDKHarness.flush(instance) == :ok
        assert_receive {:export, server, "traces", _, request, _}, 1000
        assert [span] = TraceFixtures.spans(request)
        attributes = Map.new(span.attributes, &{&1.key, &1.value.value})
        assert attributes["http.target"] == {:string_value, path}
        assert_receive {:sdk_transport_marker, true}, 1000
        send(server, {:respond, 200, [], ""})
        assert_receive {^ref, :returned, _, :ok}, 1000
      end

      TraceSDKHarness.flush(instance)
      :sys.get_state(instance.processor)
      refute_receive {:export, _, "traces", _, _, _}, 50
    after
      :telemetry.detach(marker_handler)
      :telemetry.detach({OpentelemetryFinch, :request_stop})
      restore_tracer(key, previous)
    end
  end

  @doc false
  def capture_marker(_event, _measurements, _metadata, owner),
    do: send(owner, {:sdk_transport_marker, :otel_ctx.get_value(:otlp_shipper_export, false)})

  # The instrumentation library resolves its tracer through this SDK cache entry.
  defp instrumentation_key do
    apps = :persistent_term.get({:opentelemetry, :otel_module_to_application_key}, %{})
    scope = Map.get(apps, OpentelemetryFinch, :"$__default_tracer")
    {:opentelemetry, :global, :tracer, scope}
  end

  # Restore cache absence as well as a previously configured instrumentation tracer.
  defp restore_tracer(key, :sdk_absent), do: :persistent_term.erase(key)
  defp restore_tracer(key, previous), do: :persistent_term.put(key, previous)
end
