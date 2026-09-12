defmodule OtlpShipper.EncoderTest do
  use OtlpShipper.CollectorCase, async: true
  alias OtlpShipper.{Buffer, Config, Encoder, Transport, Value}
  doctest Encoder

  test "buffer, resource, encoder and Finch deliver a log batch", %{
    endpoint: endpoint,
    finch: finch
  } do
    {:ok, config} =
      Config.new(:logs, service_name: "checkout", base_endpoint: endpoint, max_batch: 2)

    owner = self()

    export = fn records ->
      {:ok, body} = Encoder.encode(:logs, records, config.resource)
      result = Transport.export(config, finch, body, length(records))
      send(owner, {:delivered, result})
      result
    end

    pid = start_supervised!({Buffer, config: config, export: export})
    handle = Buffer.handle(pid)
    for message <- ["one", "two"], do: Buffer.enqueue(handle, %{body: Value.encode(message)})
    assert_receive {:export, collector, "logs", _, decoded, _}

    assert [
             %{
               resource: %{
                 attributes: [
                   %{key: "service.name", value: %{value: {:string_value, "checkout"}}}
                 ]
               },
               scope_logs: [%{scope: %{name: "otlp_shipper"}, log_records: records}]
             }
           ] = decoded.resource_logs

    assert Enum.map(records, & &1.body.value) == [{:string_value, "one"}, {:string_value, "two"}]
    send(collector, {:respond, 200, [], ""})
    assert_receive {:delivered, :ok}
  end

  test "metrics envelope preserves generated message values" do
    metric = %{
      name: "active",
      data: {:gauge, %{data_points: [%{value: {:as_int, 7}, time_unix_nano: 123}]}}
    }

    assert {:ok, body} = Encoder.encode(:metrics, [metric], %{attributes: []})

    message =
      :otlp_shipper_metrics_service.decode_msg(
        body,
        :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest"
      )

    assert [
             %{
               scope_metrics: [
                 %{
                   metrics: [
                     %{name: "active", data: {:gauge, %{data_points: [%{value: {:as_int, 7}}]}}}
                   ]
                 }
               ]
             }
           ] = message.resource_metrics
  end

  test "rejects invalid values without exposing data" do
    assert {:error, :invalid_signal} = Encoder.encode(:traces, [], %{})
    assert {:error, :invalid_payload} = Encoder.encode(:logs, nil, %{})
    assert {:error, :invalid_payload} = Encoder.encode(:logs, [%{severity_number: "secret"}], %{})
  end
end
