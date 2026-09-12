defmodule OtlpShipper.TransportTest do
  use OtlpShipper.CollectorCase, async: true
  alias OtlpShipper.{Config, Transport}

  setup %{endpoint: endpoint} do
    {:ok, config} =
      Config.new(:logs,
        service_name: "transport",
        base_endpoint: endpoint,
        retry_base_ms: 1,
        retry_max_ms: 2
      )

    type = :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest"

    body =
      :otlp_shipper_logs_service.encode_msg(
        %{resource_logs: [%{resource: config.resource}]},
        type
      )

    %{config: config, body: body}
  end

  test "exports gzip protobuf with configured headers", %{
    config: config,
    finch: finch,
    body: body
  } do
    config = %{config | compression: :gzip, headers: [{"authorization", "Bearer synthetic"}]}
    task = Task.async(fn -> Transport.export(config, finch, body, 2) end)
    assert_receive {:export, collector, "logs", headers, _, ^body}
    assert {"content-encoding", "gzip"} in headers
    assert {"content-type", "application/x-protobuf"} in headers
    assert {"authorization", "Bearer synthetic"} in headers
    send(collector, {:respond, 200, [], ""})
    assert :ok = Task.await(task)
  end

  test "retries the same batch on retryable HTTP statuses", %{
    config: config,
    finch: finch,
    body: body
  } do
    for status <- [429, 502, 503, 504] do
      task = Task.async(fn -> Transport.export(config, finch, body, 1) end)

      for _ <- 1..2 do
        assert_receive {:export, collector, "logs", _, _, ^body}
        send(collector, {:respond, status, [{"retry-after", "0"}], ""})
      end

      assert_receive {:export, collector, "logs", _, _, ^body}
      send(collector, {:respond, 200, [], ""})
      assert :ok = Task.await(task)
    end
  end

  test "never follows redirects or retries permanent failures", %{
    config: config,
    finch: finch,
    body: body
  } do
    for status <- [301, 400, 401, 403, 500] do
      task = Task.async(fn -> Transport.export(config, finch, body, 1) end)
      assert_receive {:export, collector, "logs", _, _, _}
      send(collector, {:respond, status, [{"location", "http://invalid.invalid/"}], ""})
      assert {:error, :http_status, ^status} = Task.await(task)
    end
  end

  test "retry budget drops exactly once and exposes no response secrets", %{
    config: config,
    finch: finch,
    body: body
  } do
    config = %{config | max_retries: 1}
    owner = self()

    task =
      Task.async(fn ->
        id = make_ref()

        events = [
          [:otlp_shipper, :export, :stop],
          [:otlp_shipper, :export, :exception],
          [:otlp_shipper, :dropped]
        ]

        :ok = :telemetry.attach_many(id, events, &__MODULE__.capture/4, {owner, self()})

        try do
          Transport.export(config, finch, body, 4)
        after
          :telemetry.detach(id)
        end
      end)

    for _ <- 1..2 do
      assert_receive {:export, collector, "logs", _, _, _}
      send(collector, {:respond, 503, [], "secret response"})
    end

    assert {:error, :http_status, 503} = Task.await(task)

    assert_receive {:event, [:otlp_shipper, :export, :stop],
                    %{count: 4, duration: duration, byte_size: bytes},
                    %{signal: :logs, status: :error}}

    assert duration >= 0
    assert bytes == byte_size(body)

    assert_receive {:event, [:otlp_shipper, :export, :exception], %{count: 4},
                    %{reason: :http_status}}

    assert_receive {:event, [:otlp_shipper, :dropped], %{count: 4}, %{reason: :export_failed}}
    refute_receive {:event, [:otlp_shipper, :dropped], _, _}, 0
  end

  test "bounds total deadline and honors Retry-After without early retry", %{
    config: config,
    finch: finch,
    body: body
  } do
    task = Task.async(fn -> Transport.export(%{config | timeout: 200}, finch, body, 1) end)
    assert_receive {:export, collector, "logs", _, _, _}
    send(collector, {:respond, 503, [{"retry-after", "60"}], ""})
    assert {:error, :timeout} = Task.await(task)
    task = Task.async(fn -> Transport.export(%{config | timeout: 50}, finch, body, 1) end)
    assert_receive {:export, collector, "logs", _, _, _}
    assert {:error, :timeout} = Task.await(task, 1000)
    send(collector, {:respond, 200, [], ""})
  end

  test "partial acceptance is reported without retrying", %{
    config: config,
    finch: finch,
    body: body
  } do
    response =
      :otlp_shipper_logs_service.encode_msg(
        %{partial_success: %{rejected_log_records: 2, error_message: "synthetic warning"}},
        :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceResponse"
      )

    task = Task.async(fn -> Transport.export(config, finch, body, 4) end)
    assert_receive {:export, collector, "logs", _, _, _}
    send(collector, {:respond, 200, [], response})
    assert {:ok, :partial, 2} = Task.await(task)
  end

  test "metrics partial acceptance uses rejected data points", %{config: config, finch: finch} do
    config = %{
      config
      | signal: :metrics,
        endpoint: String.replace_suffix(config.endpoint, "logs", "metrics")
    }

    body =
      :otlp_shipper_metrics_service.encode_msg(
        %{resource_metrics: []},
        :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest"
      )

    response =
      :otlp_shipper_metrics_service.encode_msg(
        %{partial_success: %{rejected_data_points: 1}},
        :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceResponse"
      )

    task = Task.async(fn -> Transport.export(config, finch, body, 2) end)
    assert_receive {:export, collector, "metrics", _, _, _}
    send(collector, {:respond, 200, [], response})
    assert {:ok, :partial, 1} = Task.await(task)
  end

  test "rejects malformed or excessive collector responses", %{
    config: config,
    finch: finch,
    body: body
  } do
    for {response, error} <- [
          {<<255>>, :invalid_response},
          {String.duplicate("x", 100), :response_too_large}
        ] do
      task =
        Task.async(fn -> Transport.export(%{config | max_response_bytes: 10}, finch, body, 1) end)

      assert_receive {:export, collector, "logs", _, _, _}
      send(collector, {:respond, 200, [], response})
      assert {:error, ^error} = Task.await(task)
    end

    assert {:error, :batch_too_large} =
             Transport.export(%{config | max_batch_bytes: 1}, finch, body, 1)
  end

  test "pool failure becomes a tagged error", %{config: config, body: body} do
    assert {:error, :transport, :request_failed} =
             Transport.export(config, __MODULE__.MissingPool, body, 1)
  end

  @doc false
  def capture(event, measurements, metadata, {owner, source}) do
    if self() == source, do: send(owner, {:event, event, measurements, metadata})
  end
end
