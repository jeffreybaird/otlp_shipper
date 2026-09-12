defmodule OtlpShipper.ProtobufTest do
  use OtlpShipper.CollectorCase, async: true

  test "vendored logs schema reaches a real HTTP endpoint", %{endpoint: endpoint, finch: finch} do
    type = :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest"

    message = %{
      resource_logs: [
        %{
          resource: %{
            attributes: [%{key: "service.name", value: %{value: {:string_value, "fixture"}}}]
          },
          scope_logs: []
        }
      ]
    }

    body = :otlp_shipper_logs_service.encode_msg(message, type)

    task =
      Task.async(fn ->
        Finch.build(
          :post,
          endpoint <> "/v1/logs",
          [{"content-type", "application/x-protobuf"}],
          body
        )
        |> Finch.request(finch)
      end)

    assert_receive {:export, collector, "logs", headers, decoded, ^body}
    assert {"content-type", "application/x-protobuf"} in headers

    assert [
             %{
               resource: %{
                 attributes: [%{key: "service.name", value: %{value: {:string_value, "fixture"}}}]
               }
             }
           ] = decoded.resource_logs

    send(collector, {:respond, 200, [], ""})
    assert {:ok, %{status: 200}} = Task.await(task)
  end

  test "vendored metrics schema preserves an integer sum", %{endpoint: endpoint, finch: finch} do
    type = :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest"

    message = %{
      resource_metrics: [
        %{
          scope_metrics: [
            %{
              metrics: [
                %{
                  name: "requests",
                  data:
                    {:sum,
                     %{
                       is_monotonic: true,
                       aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA,
                       data_points: [
                         %{value: {:as_int, 7}, start_time_unix_nano: 1, time_unix_nano: 2}
                       ]
                     }}
                }
              ]
            }
          ]
        }
      ]
    }

    body = :otlp_shipper_metrics_service.encode_msg(message, type)

    task =
      Task.async(fn ->
        Finch.build(:post, endpoint <> "/v1/metrics", [], body) |> Finch.request(finch)
      end)

    assert_receive {:export, collector, "metrics", _, decoded, ^body}

    assert [
             %{
               scope_metrics: [
                 %{metrics: [%{data: {:sum, %{data_points: [%{value: {:as_int, 7}}]}}}]}
               ]
             }
           ] = decoded.resource_metrics

    send(collector, {:respond, 200, [], ""})
    assert {:ok, %{status: 200}} = Task.await(task)
  end
end
