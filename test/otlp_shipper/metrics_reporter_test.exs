defmodule OtlpShipper.MetricsReporterTest do
  use OtlpShipper.CollectorCase, async: false
  import Telemetry.Metrics
  alias OtlpShipper.{Buffer, MetricsReporter}
  alias OtlpShipper.Metrics.{Definition, Registration, Worker}
  @event [:phase2, :sample]
  @moduletag capture_log: true

  setup %{endpoint: endpoint} do
    %{
      opts: [
        service_name: "metrics-test",
        base_endpoint: endpoint,
        flush_ms: 60_000,
        shutdown_ms: 100,
        retry_base_ms: 1,
        retry_max_ms: 2
      ]
    }
  end

  test "exact counters, sums, gauges and histograms use delta intervals and transformed tags", %{
    opts: opts
  } do
    metrics = [
      counter("test.count", event_name: @event),
      sum("test.bytes",
        event_name: @event,
        unit: :byte,
        tags: [:route],
        tag_values: &%{route: String.upcase(&1.route)}
      ),
      last_value("test.active", event_name: @event),
      distribution("test.duration",
        event_name: @event,
        unit: {:native, :millisecond},
        reporter_options: [buckets: [5, 10]]
      )
    ]

    reporter = start_supervised!({MetricsReporter, Keyword.put(opts, :metrics, metrics)})

    for {bytes, active, duration, route} <- [
          {2, 10, 5, "home"},
          {3, 8, 7, "home"},
          {4, 9, 12, "away"}
        ] do
      :telemetry.execute(
        @event,
        %{
          count: true,
          bytes: bytes,
          active: active,
          duration: System.convert_time_unit(duration, :millisecond, :native)
        },
        %{route: route}
      )
    end

    assert :ok = MetricsReporter.flush(reporter)
    {metrics, _} = accept_metrics()
    count = Map.fetch!(metrics, "test.count")

    assert {:sum,
            %{
              is_monotonic: true,
              aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA,
              data_points: [first]
            }} = count.data

    assert first.value == {:as_int, 3}
    assert first.start_time_unix_nano < first.time_unix_nano
    assert count.unit == "1"
    {:sum, %{data_points: points}} = metrics["test.bytes"].data
    assert metrics["test.bytes"].unit == "By"
    by_tag = Map.new(points, fn point -> {hd(point.attributes).value.value, point.value} end)

    assert by_tag == %{
             {:string_value, "HOME"} => {:as_int, 5},
             {:string_value, "AWAY"} => {:as_int, 4}
           }

    {:gauge, %{data_points: [gauge]}} = metrics["test.active"].data
    assert gauge.value == {:as_int, 9}
    assert gauge.start_time_unix_nano == 0
    assert gauge.time_unix_nano <= first.time_unix_nano

    {:histogram, %{aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA, data_points: [hist]}} =
      metrics["test.duration"].data

    assert {hist.count, hist.sum, hist.bucket_counts, hist.explicit_bounds} ==
             {3, 24.0, [1, 1, 1], [5.0, 10.0]}

    assert {hist.min, hist.max, metrics["test.duration"].unit} == {5.0, 12.0, "ms"}

    :telemetry.execute(
      @event,
      %{
        count: 1,
        bytes: -2,
        active: 4,
        duration: System.convert_time_unit(2, :millisecond, :native)
      },
      %{route: "home"}
    )

    :ok = MetricsReporter.flush(reporter)
    {second, _} = accept_metrics()
    {:sum, %{data_points: [point]}} = second["test.count"].data
    assert point.value == {:as_int, 1}
    assert point.start_time_unix_nano == first.time_unix_nano
    {:sum, %{is_monotonic: false, data_points: [point]}} = second["test.bytes"].data
    assert point.value == {:as_int, -2}
    {:histogram, %{data_points: [point]}} = second["test.duration"].data
    assert {point.count, point.sum, point.bucket_counts} == {1, 2.0, [1, 0, 0]}
    :ok = MetricsReporter.flush(reporter)
    refute_receive {:export, _, _, _, _, _}, 30
    :telemetry.execute(@event, %{bytes: 3}, %{route: "new"})
    :ok = MetricsReporter.flush(reporter)
    {third, _} = accept_metrics()
    assert Map.keys(third) == ["test.bytes"]
    assert {:sum, %{is_monotonic: false}} = third["test.bytes"].data
  end

  test "intervals export without explicit flush and skip empty intervals", %{opts: opts} do
    reporter = start_reporter(opts, [last_value("test.active", event_name: @event)], flush_ms: 20)
    :telemetry.execute(@event, %{active: 7})
    {metrics, _} = accept_metrics()
    assert {:gauge, %{data_points: [%{value: {:as_int, 7}}]}} = metrics["test.active"].data
    refute_receive {:export, _, _, _, _, _}, 60
    assert Process.alive?(reporter)
  end

  test "series cap counts losses and resets each interval", %{opts: opts} do
    attach_drops()

    reporter =
      start_reporter(opts, [sum("test.value", event_name: @event, tags: [:route])], max_series: 2)

    for route <- ["a", "b", "c", "a"],
        do: :telemetry.execute(@event, %{value: 1}, %{route: route})

    :ok = MetricsReporter.flush(reporter)
    assert_receive {:dropped, %{count: 1}, %{signal: :metrics, reason: :series_limit}}
    {metrics, _} = accept_metrics()
    {:sum, %{data_points: points}} = metrics["test.value"].data
    assert Enum.sort(Enum.map(points, & &1.value)) == [{:as_int, 1}, {:as_int, 2}]
    :telemetry.execute(@event, %{value: 4}, %{route: "c"})
    :ok = MetricsReporter.flush(reporter)
    {metrics, _} = accept_metrics()
    assert {:sum, %{data_points: [%{value: {:as_int, 4}}]}} = metrics["test.value"].data
  end

  test "10,000 events cannot grow the reporter mailbox past its ingress cap", %{opts: opts} do
    reporter = start_reporter(opts, [counter("test.count", event_name: @event)], max_pending: 10)
    worker = child(reporter, Worker)
    counter = :atomics.new(1, [])
    id = make_ref()
    :telemetry.attach(id, [:otlp_shipper, :dropped], &__MODULE__.count_drops/4, counter)
    on_exit(fn -> :telemetry.detach(id) end)
    :sys.suspend(worker)

    try do
      for _ <- 1..10_000, do: :telemetry.execute(@event, %{count: 1})
      assert Process.info(worker, :message_queue_len) == {:message_queue_len, 10}
      assert :atomics.get(counter, 1) == 9990
    after
      :sys.resume(worker)
    end

    :ok = MetricsReporter.flush(reporter)
    {metrics, _} = accept_metrics()
    assert {:sum, %{data_points: [%{value: {:as_int, 10}}]}} = metrics["test.count"].data
  end

  test "concurrent producers aggregate every accepted observation", %{opts: opts} do
    reporter =
      start_reporter(opts, [counter("test.count", event_name: @event)], max_pending: 20_000)

    1..20
    |> Task.async_stream(fn _ -> for _ <- 1..100, do: :telemetry.execute(@event, %{count: 1}) end)
    |> Stream.run()

    :ok = MetricsReporter.flush(reporter)
    {metrics, _} = accept_metrics()
    assert {:sum, %{data_points: [%{value: {:as_int, 2000}}]}} = metrics["test.count"].data
  end

  test "keep/drop, invalid callbacks and missing values do not detach handlers", %{opts: opts} do
    attach_drops()

    reporter =
      start_reporter(opts, [
        sum("test.valid",
          event_name: @event,
          measurement: fn m, _ -> m.value end,
          keep: & &1.keep
        ),
        sum("test.broken", event_name: @event, measurement: fn _ -> raise "secret" end)
      ])

    :telemetry.execute(@event, %{value: 7}, %{keep: false})
    :telemetry.execute(@event, %{value: 3}, %{keep: true})
    :ok = MetricsReporter.flush(reporter)
    {metrics, _} = accept_metrics()
    assert Map.keys(metrics) == ["test.valid"]
    assert {:sum, %{data_points: [%{value: {:as_int, 3}}]}} = metrics["test.valid"].data
    assert_receive {:dropped, %{count: 1}, %{reason: :callback_failed}}
    assert_receive {:dropped, %{count: 1}, %{reason: :callback_failed}}
    assert length(own_handlers()) == 1
  end

  test "503 retries retain one metric batch and failed intervals do not leak forward", %{
    opts: opts
  } do
    attach_drops()
    reporter = start_reporter(opts, [sum("test.value", event_name: @event)], compression: :gzip)
    :telemetry.execute(@event, %{value: 5})
    :ok = MetricsReporter.flush(reporter)

    bodies =
      for status <- [503, 503, 200] do
        assert_receive {:export, collector, "metrics", headers, _, bytes}
        assert {"content-encoding", "gzip"} in headers
        send(collector, {:respond, status, [], ""})
        bytes
      end

    assert length(Enum.uniq(bodies)) == 1
    :telemetry.execute(@event, %{value: 9})
    :ok = MetricsReporter.flush(reporter)
    assert_receive {:export, collector, "metrics", _, _, _}
    send(collector, {:respond, 401, [], ""})
    assert_receive {:dropped, %{count: 1}, %{reason: :export_failed}}
    :telemetry.execute(@event, %{value: 2})
    :ok = MetricsReporter.flush(reporter)
    {metrics, _} = accept_metrics()
    assert {:sum, %{data_points: [%{value: {:as_int, 2}}]}} = metrics["test.value"].data
  end

  test "worker, buffer and registration restart without stale or duplicated handlers", %{
    opts: opts
  } do
    reporter = start_reporter(opts, [counter("test.count", event_name: @event)])

    for id <- [Worker, Registration, Buffer] do
      previous = child(reporter, id)
      Process.exit(previous, :kill)
      await_replacement(reporter, id, previous)
      assert length(own_handlers()) == 1
      :telemetry.execute(@event, %{count: 1})
      :ok = MetricsReporter.flush(reporter)
      {metrics, _} = accept_metrics()
      assert {:sum, %{data_points: [%{value: {:as_int, 1}}]}} = metrics["test.count"].data
    end

    stop_supervised!(MetricsReporter)
    assert own_handlers() == []
  end

  test "shutdown detaches handlers and exports the final interval", %{opts: opts} do
    start_reporter(opts, [counter("test.count", event_name: @event)], shutdown_ms: 1000)
    :telemetry.execute(@event, %{count: 1})
    {:ok, test_supervisor} = ExUnit.fetch_test_supervisor()
    task = Task.async(fn -> Supervisor.terminate_child(test_supervisor, MetricsReporter) end)
    {metrics, _} = accept_metrics()
    assert {:sum, %{data_points: [%{value: {:as_int, 1}}]}} = metrics["test.count"].data
    assert Task.await(task) == :ok
    assert own_handlers() == []
  end

  test "startup rejects summaries, invalid options and self-reporting", %{opts: opts} do
    assert {:error, :unsupported_metric, :use_distribution} =
             MetricsReporter.start_link(Keyword.put(opts, :metrics, [summary("test.value")]))

    assert {:error, :invalid_metrics} = MetricsReporter.start_link(opts)
    assert {:error, :invalid_metrics_options} = MetricsReporter.start_link(:bad)

    for invalid <- [
          [max_series: 0],
          [max_pending: -1],
          [max_tag_bytes: 0],
          [finch_name: "bad"],
          [name: 123]
        ] do
      assert {:error, :invalid_metrics_options} =
               MetricsReporter.start_link(Keyword.merge(opts ++ [metrics: []], invalid))
    end

    assert {:error, :recursive_metric_event} =
             MetricsReporter.start_link(opts ++ [metrics: [counter("otlp_shipper.export.count")]])

    assert own_handlers() == []
    assert {:error, :unavailable} = MetricsReporter.flush(:absent_metrics_reporter)
  end

  test "empty and independent instances keep their own lifecycle", %{opts: opts} do
    empty = start_reporter(opts, [])
    assert :ok = MetricsReporter.flush(empty)
    refute_receive {:export, _, _, _, _, _}, 20

    second =
      start_supervised!(
        {MetricsReporter,
         opts ++
           [
             metrics: [counter("test.count", event_name: @event)],
             name: OtherMetrics,
             finch_name: OtherMetricsFinch
           ]}
      )

    stop_supervised!(MetricsReporter)
    :telemetry.execute(@event, %{count: 1})
    :ok = MetricsReporter.flush(second)
    {metrics, _} = accept_metrics()
    assert Map.has_key?(metrics, "test.count")
    stop_supervised!(OtherMetrics)
    assert own_handlers() == []
  end

  test "explicit flush invalidates already-delivered interval timer messages", %{opts: opts} do
    reporter = start_reporter(opts, [counter("test.count", event_name: @event)])
    worker = child(reporter, Worker)
    %{timer: {_, token}} = :sys.get_state(worker)
    :ok = MetricsReporter.flush(reporter)
    :telemetry.execute(@event, %{count: 1})
    send(worker, {:interval, token})
    assert map_size(:sys.get_state(worker).series) == 1
    refute_receive {:export, _, _, _, _, _}, 20
    :ok = MetricsReporter.flush(reporter)
    {metrics, _} = accept_metrics()
    assert {:sum, %{data_points: [%{value: {:as_int, 1}}]}} = metrics["test.count"].data
  end

  test "exporter HTTP and synchronous drop subscribers cannot create metric feedback", %{
    opts: opts
  } do
    metrics = [
      counter("test.count", event_name: @event),
      counter("http.requests", event_name: [:finch, :request, :start], measurement: fn _ -> 1 end)
    ]

    reporter = start_reporter(opts, metrics, max_series: 1)
    id = make_ref()
    :telemetry.attach(id, [:otlp_shipper, :dropped], &__MODULE__.emit_on_drop/4, nil)
    on_exit(fn -> :telemetry.detach(id) end)
    :telemetry.execute(@event, %{count: 1})
    :ok = MetricsReporter.flush(reporter)
    {values, _} = accept_metrics()
    assert Map.keys(values) == ["test.count"]
    :ok = MetricsReporter.flush(reporter)
    refute_receive {:export, _, _, _, _, _}, 30
    # A malformed measurement callback emits a drop while the recursion guard is set.
    bad = %{hd(metrics) | measurement: fn _ -> raise "bad" end}
    {:ok, [definition]} = Definition.new([bad])
    ingress = :sys.get_state(child(reporter, Worker)).ingress
    :ok = Registration.handle_event(@event, %{}, %{}, {[definition], ingress})
    :ok = MetricsReporter.flush(reporter)
    refute_receive {:export, _, _, _, _, _}, 30
  end

  def emit_on_drop(_, _, _, _), do: :telemetry.execute(@event, %{count: 1})

  def count_drops(_, %{count: count}, %{signal: :metrics, reason: :queue_full}, counter),
    do: :atomics.add(counter, 1, count)

  def count_drops(_, _, _, _), do: :ok

  def forward_drop(_, measurements, metadata, owner),
    do: send(owner, {:dropped, measurements, metadata})

  defp attach_drops do
    id = make_ref()
    :telemetry.attach(id, [:otlp_shipper, :dropped], &__MODULE__.forward_drop/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp start_reporter(opts, metrics, extra \\ []),
    do: start_supervised!({MetricsReporter, Keyword.merge(opts ++ [metrics: metrics], extra)})

  defp accept_metrics do
    assert_receive {:export, collector, "metrics", _, decoded, bytes}
    send(collector, {:respond, 200, [], ""})
    resource = hd(decoded.resource_metrics)
    assert Enum.any?(resource.resource.attributes, &(&1.key == "service.name"))
    metrics = hd(resource.scope_metrics).metrics
    {Map.new(metrics, &{&1.name, &1}), bytes}
  end

  defp child(reporter, id),
    do: reporter |> Supervisor.which_children() |> List.keyfind(id, 0) |> elem(1)

  defp own_handlers,
    do: Enum.filter(:telemetry.list_handlers(@event), &match?({Registration, _, _}, &1.id))

  defp await_replacement(reporter, id, previous, attempts \\ 100)
  defp await_replacement(_, _, _, 0), do: flunk("reporter child failed to restart")

  defp await_replacement(reporter, id, previous, attempts) do
    case child(reporter, id) do
      pid when is_pid(pid) and pid != previous ->
        pid

      _ ->
        Process.sleep(10)
        await_replacement(reporter, id, previous, attempts - 1)
    end
  end
end
