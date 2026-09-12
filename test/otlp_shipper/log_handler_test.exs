defmodule OtlpShipper.LogHandlerTest do
  use OtlpShipper.CollectorCase, async: false
  @moduletag capture_log: true
  require Logger
  require OpenTelemetry.Tracer
  alias OtlpShipper.{Buffer, LogHandler}

  setup %{endpoint: endpoint} do
    original_level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: original_level) end)

    %{
      options: [
        service_name: "logs-test",
        base_endpoint: endpoint,
        flush_ms: 60_000,
        max_batch: 1,
        max_queue: 10,
        shutdown_ms: 50,
        timeout: 1000,
        retry_base_ms: 1,
        retry_max_ms: 2
      ]
    }
  end

  test "Logger inside a real span and outside delivers exact IDs and bodies", %{options: opts} do
    start_supervised!({LogHandler, opts})

    {trace_id, span_id} =
      OpenTelemetry.Tracer.with_span "checkout" do
        ctx = :otel_tracer.current_span_ctx()
        Logger.info(%{order: 42, paid: true}, customer: "test")
        {:otel_span.trace_id(ctx), :otel_span.span_id(ctx)}
      end

    assert trace_id > 0
    assert span_id > 0
    record = accept_record()
    assert record.trace_id == <<trace_id::128>>
    assert record.span_id == <<span_id::64>>
    assert record.severity_number == :SEVERITY_NUMBER_INFO
    assert record.severity_text == "info"
    assert record.time_unix_nano > 0
    assert record.observed_time_unix_nano >= record.time_unix_nano
    assert {:kvlist_value, %{values: body}} = record.body.value
    assert Enum.find(body, &(&1.key == "paid")).value == %{value: {:bool_value, true}}

    assert Enum.find(record.attributes, &(&1.key == "customer")).value == %{
             value: {:string_value, "test"}
           }

    refute Enum.any?(record.attributes, &(&1.key in ["pid", "mfa", "otel_trace_id", "domain"]))
    Logger.info("outside")
    record = accept_record()
    assert record.trace_id == ""
    assert record.span_id == ""
    assert record.body.value == {:string_value, "outside"}
  end

  test "gzip and 503 twice then 200 retain the same logical batch", %{options: opts} do
    attach_events()
    start_supervised!({LogHandler, Keyword.put(opts, :compression, :gzip)})
    Logger.info("retry me")

    bodies =
      for status <- [503, 503, 200] do
        assert_receive {:export, collector, "logs", headers, decoded, body}
        assert {"content-encoding", "gzip"} in headers
        assert {"content-type", "application/x-protobuf"} in headers
        assert hd(records(decoded)).body.value == {:string_value, "retry me"}
        send(collector, {:respond, status, [], ""})
        body
      end

    assert length(Enum.uniq(bodies)) == 1
    assert_receive {:telemetry, [:otlp_shipper, :export, :stop], %{count: 1}, %{status: :ok}}
    refute_receive {:export, _, _, _, _, _}, 30
    refute_receive {:telemetry, [:otlp_shipper, :dropped], _, _}, 0
  end

  test "401 reports every failure but logs only one filtered diagnostic", %{options: opts} do
    attach_events()
    capture_id = :otlp_test_diagnostics
    :ok = :logger.add_handler(capture_id, OtlpShipper.TestLogCapture, %{config: %{owner: self()}})
    on_exit(fn -> :logger.remove_handler(capture_id) end)
    start_supervised!({LogHandler, opts})

    for index <- 1..2 do
      Logger.info("reject", attempt: index)
      assert_receive {:export, collector, "logs", _, _, _}
      send(collector, {:respond, 401, [], "secret response"})

      assert_receive {:telemetry, [:otlp_shipper, :export, :exception], %{count: 1},
                      %{reason: :http_status}}

      assert_receive {:telemetry, [:otlp_shipper, :dropped], %{count: 1},
                      %{reason: :export_failed}}
    end

    assert_receive {:diagnostic, %{msg: {:string, message}, meta: meta}}
    assert message == "OTLP log export failed or was partially rejected"
    assert meta.reason == :http_status
    refute Map.has_key?(meta, :headers)
    refute_receive {:diagnostic, _}, 30
    refute_receive {:export, _, _, _, _, _}, 30
  end

  test "diagnostic domain, HTTP internals and reentrant telemetry logs cannot recurse", %{
    options: opts
  } do
    start_supervised!({LogHandler, opts})
    Logger.warning("internal", domain: [:otlp_shipper])
    :logger.log(:warning, "HTTP internal", %{mfa: {Finch.HTTP2.Pool, :example, 0}})
    refute_receive {:export, _, _, _, _, _}, 30
    id = make_ref()
    :telemetry.attach(id, [:otlp_shipper, :dropped], &__MODULE__.log_on_drop/4, nil)
    on_exit(fn -> :telemetry.detach(id) end)
    {:ok, config} = :logger.get_handler_config(:otlp_shipper)
    assert Map.keys(config.config) == [:token]
    handle = Buffer.handle(LogHandler.Buffer)
    :ok = LogHandler.log(%{}, %{config: %{handle: handle, limits: %{}}})
    refute_receive {:export, _, _, _, _, _}, 30
  end

  test "10,000 Logger events keep a fixed queue and exact drop count", %{options: opts} do
    start_supervised!({LogHandler, Keyword.put(opts, :max_batch, 10)})
    handle = Buffer.handle(LogHandler.Buffer)
    counter = :atomics.new(1, [])
    id = make_ref()
    :telemetry.attach(id, [:otlp_shipper, :dropped], &__MODULE__.count_drops/4, counter)
    on_exit(fn -> :telemetry.detach(id) end)
    :sys.suspend(handle.owner)

    try do
      for index <- 1..10_000, do: :logger.log(:info, "burst", %{index: index})
      assert Buffer.size(handle) == 10
      assert :atomics.get(counter, 1) == 9990
      assert {:message_queue_len, length} = Process.info(handle.owner, :message_queue_len)
      assert length <= 1
    after
      :sys.resume(handle.owner)
    end

    assert_receive {:export, collector, "logs", _, decoded, _}

    retained =
      for record <- records(decoded),
          do: Enum.find(record.attributes, &(&1.key == "index")).value.value

    assert retained == Enum.map(9991..10_000, &{:int_value, &1})
    send(collector, {:respond, 200, [], ""})
  end

  test "buffer and registration recover after being killed", %{options: opts} do
    supervisor = start_supervised!({LogHandler, opts})

    for child_id <- [LogHandler.Buffer, OtlpShipper.LogHandler.Registration] do
      {_, previous, _, _} =
        Enum.find(Supervisor.which_children(supervisor), &(elem(&1, 0) == child_id))

      Process.exit(previous, :kill)
      await_replacement(supervisor, child_id, previous)
      await_handler()
      Logger.info("after restart")
      assert accept_record().body.value == {:string_value, "after restart"}
    end
  end

  test "a timed-out export is dropped and the next batch still delivers", %{options: opts} do
    attach_events()
    start_supervised!({LogHandler, Keyword.put(opts, :timeout, 100)})
    Logger.info("slow")
    assert_receive {:export, collector, "logs", _, _, _}
    assert_receive {:telemetry, [:otlp_shipper, :dropped], %{count: 1}, %{reason: :export_failed}}
    send(collector, {:respond, 200, [], ""})
    Logger.info("recovered")
    assert accept_record().body.value == {:string_value, "recovered"}
  end

  test "shutdown removes registration and drains a partial batch", %{options: opts} do
    start_supervised!({LogHandler, Keyword.merge(opts, max_batch: 10, shutdown_ms: 1000)})
    Logger.info("last record")
    {:ok, test_supervisor} = ExUnit.fetch_test_supervisor()
    task = Task.async(fn -> Supervisor.terminate_child(test_supervisor, :otlp_shipper) end)
    assert accept_record().body.value == {:string_value, "last record"}
    assert Task.await(task) == :ok
    assert {:error, {:not_found, :otlp_shipper}} = :logger.get_handler_config(:otlp_shipper)
  end

  test "validates startup, protects ownership and allows level changes", %{options: opts} do
    for extra <- [
          [level: :invalid],
          [handler_id: "bad"],
          [diagnostic_interval_ms: 0],
          [max_body_bytes: 2]
        ] do
      assert {:error, _} = LogHandler.start_link(Keyword.merge(opts, extra))
    end

    assert {:error, :invalid_log_options} = LogHandler.start_link(:invalid)
    assert {:error, :service_name_required} = LogHandler.start_link([])
    assert {:error, :start_supervised_log_handler} = LogHandler.adding_handler(%{})
    start_supervised!({LogHandler, opts})
    assert :ok = :logger.update_handler_config(:otlp_shipper, :level, :error)
    Logger.info("below level")
    refute_receive {:export, _, _, _, _, _}, 20
    Logger.error("at level")
    assert accept_record().severity_number == :SEVERITY_NUMBER_ERROR

    assert {:error, :restart_required} =
             :logger.update_handler_config(:otlp_shipper, :config, %{bad: true})

    {:ok, handler} = :logger.get_handler_config(:otlp_shipper)

    assert {:error, _} =
             start_supervised(
               {LogHandler,
                Keyword.merge(opts, finch_name: OtherFinch, buffer_name: OtherBuffer)},
               id: :other
             )

    assert {:ok, ^handler} = :logger.get_handler_config(:otlp_shipper)
  end

  test "distinct explicit event IDs survive without a current span", %{options: opts} do
    start_supervised!({LogHandler, opts})
    Logger.info("forwarded", otel_trace_id: 11, otel_span_id: 22)
    record = accept_record()
    assert record.trace_id == <<11::128>>
    assert record.span_id == <<22::64>>
  end

  test "Finch restart and crashed batch worker do not disable logging", %{options: opts} do
    attach_events()
    supervisor = start_supervised!({LogHandler, opts})

    {LogHandler.Finch, pool, _, _} =
      Enum.find(Supervisor.which_children(supervisor), &(elem(&1, 0) == LogHandler.Finch))

    Process.exit(pool, :kill)
    await_replacement(supervisor, LogHandler.Finch, pool)
    Logger.info("before worker crash")
    assert_receive {:export, collector, "logs", _, _, _}
    %{worker: %{task: %{pid: worker}}} = :sys.get_state(LogHandler.Buffer)
    Process.exit(worker, :kill)
    assert_receive {:telemetry, [:otlp_shipper, :dropped], %{count: 1}, %{reason: :export_failed}}
    send(collector, {:respond, 200, [], ""})
    Logger.info("worker recovered")
    assert accept_record().body.value == {:string_value, "worker recovered"}
  end

  test "independent instances remove only their own handler", %{options: opts} do
    start_supervised!({LogHandler, opts})

    start_supervised!(
      {LogHandler,
       Keyword.merge(opts,
         handler_id: :other_logs,
         buffer_name: OtherBuffer,
         finch_name: OtherFinch
       )}
    )

    Logger.info("both")
    assert accept_record().body.value == {:string_value, "both"}
    assert accept_record().body.value == {:string_value, "both"}
    stop_supervised!(:otlp_shipper)
    assert {:ok, _} = :logger.get_handler_config(:other_logs)
    Logger.info("second only")
    assert accept_record().body.value == {:string_value, "second only"}
    refute_receive {:export, _, _, _, _, _}, 30
  end

  test "invalid supervisor names return a tagged startup error", %{options: opts} do
    assert {:error, :invalid_log_options} = LogHandler.start_link(Keyword.put(opts, :name, 123))
  end

  test "malformed domain metadata cannot uninstall the Logger handler", %{options: opts} do
    start_supervised!({LogHandler, opts})
    Logger.info("odd domain", domain: [:application | :invalid_tail])
    assert accept_record().body.value == {:string_value, "odd domain"}
    assert {:ok, _} = :logger.get_handler_config(:otlp_shipper)
  end

  def count_drops(_, %{count: count}, %{reason: :queue_full}, counter),
    do: :atomics.add(counter, 1, count)

  def count_drops(_, _, _, _), do: :ok
  def log_on_drop(_, _, _, _), do: Logger.warning("telemetry subscriber")

  def forward_event(event, measurements, metadata, owner),
    do: send(owner, {:telemetry, event, measurements, metadata})

  defp attach_events do
    id = make_ref()

    :telemetry.attach_many(
      id,
      [
        [:otlp_shipper, :export, :stop],
        [:otlp_shipper, :export, :exception],
        [:otlp_shipper, :dropped]
      ],
      &__MODULE__.forward_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp records(decoded), do: hd(hd(decoded.resource_logs).scope_logs).log_records

  defp accept_record do
    assert_receive {:export, collector, "logs", _, decoded, _}
    send(collector, {:respond, 200, [], ""})
    hd(records(decoded))
  end

  defp await_replacement(supervisor, id, previous, attempts \\ 100)
  defp await_replacement(_, _, _, 0), do: flunk("child did not restart")

  defp await_replacement(supervisor, id, previous, attempts) do
    case Enum.find(Supervisor.which_children(supervisor), &(elem(&1, 0) == id)) do
      {_, pid, _, _} when is_pid(pid) and pid != previous ->
        pid

      _ ->
        Process.sleep(10)
        await_replacement(supervisor, id, previous, attempts - 1)
    end
  end

  defp await_handler(attempts \\ 100)
  defp await_handler(0), do: flunk("handler did not reinstall")

  defp await_handler(attempts) do
    case :logger.get_handler_config(:otlp_shipper) do
      {:ok, _} ->
        :ok

      _ ->
        Process.sleep(10)
        await_handler(attempts - 1)
    end
  end
end
