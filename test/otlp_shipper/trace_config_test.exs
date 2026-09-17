defmodule OtlpShipper.TraceConfigTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias OtlpShipper.Config

  test "TPC-01 transport defaults do not invent a trace resource" do
    assert {:ok, config} = Config.transport(:traces, [], %{})
    assert config.signal == :traces
    assert config.resource == nil
    assert config.endpoint == "http://localhost:4318/v1/traces"
    assert config.timeout == 10_000
    assert config.max_batch == 512
    assert config.max_item_bytes == 65_536
    assert config.max_batch_bytes == 1_048_576
    assert config.max_response_bytes == 65_536
    assert config.max_retries == 3
    assert Config.new(:traces, [], %{}) == {:error, :invalid_signal}
    assert Config.new(:logs, [], %{}) == {:error, :service_name_required}
    assert Config.new(:metrics, [], %{}) == {:error, :service_name_required}
  end

  test "TPC-01 explicit settings override trace and generic environment values" do
    environment = %{
      "OTEL_EXPORTER_OTLP_ENDPOINT" => "https://generic.example/prefix",
      "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => "https://trace.example/exact",
      "OTEL_EXPORTER_OTLP_HEADERS" => "source=generic",
      "OTEL_EXPORTER_OTLP_TRACES_HEADERS" => "source=trace",
      "OTEL_EXPORTER_OTLP_COMPRESSION" => "none",
      "OTEL_EXPORTER_OTLP_TRACES_COMPRESSION" => "gzip",
      "OTEL_EXPORTER_OTLP_TIMEOUT" => "700",
      "OTEL_EXPORTER_OTLP_TRACES_TIMEOUT" => "800",
      "OTEL_EXPORTER_OTLP_PROTOCOL" => "grpc",
      "OTEL_EXPORTER_OTLP_TRACES_PROTOCOL" => "http/protobuf"
    }

    assert {:ok, trace} = Config.transport(:traces, [], environment)
    assert trace.endpoint == "https://trace.example/exact"
    assert trace.headers == [{"source", "trace"}]
    assert trace.compression == :gzip
    assert trace.timeout == 800

    assert {:ok, explicit} =
             Config.transport(
               :traces,
               [
                 endpoint: "https://explicit.example/custom",
                 headers: [{"source", "explicit"}],
                 compression: :none,
                 timeout: 900,
                 protocol: "http/protobuf"
               ],
               Map.put(environment, "OTEL_EXPORTER_OTLP_TRACES_PROTOCOL", "grpc")
             )

    assert explicit.endpoint == "https://explicit.example/custom"
    assert explicit.headers == [{"source", "explicit"}]
    assert explicit.compression == :none
    assert explicit.timeout == 900
  end

  test "TPC-01 base endpoints append the trace path and unrelated signal settings are ignored" do
    assert {:ok, config} =
             Config.transport(:traces, [], %{
               "OTEL_EXPORTER_OTLP_ENDPOINT" => "https://collector.example/prefix/",
               "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT" => "https://logs.example/exact",
               "OTEL_SERVICE_NAME" => "ignored"
             })

    assert config.endpoint == "https://collector.example/prefix/v1/traces"
    assert config.resource == nil
  end

  test "TPC-01 resource and SDK ownership options are rejected instead of ignored" do
    for key <- [
          :resource,
          :service_name,
          :service_version,
          :service_instance_id,
          :max_queue,
          :flush_ms,
          :shutdown_ms
        ] do
      assert Config.transport(:traces, [{key, "unsupported"}], %{}) ==
               {:error, :unknown_option, key}
    end

    assert {:ok, config} = Config.transport(:traces, [max_batch: 4096], %{})
    assert config.max_batch == 4096
    assert Config.transport(:logs, [], %{}) == {:error, :invalid_signal}
    assert Config.transport(:traces, [protocol: "grpc"], %{}) == {:error, :unsupported_protocol}

    assert Config.transport(:traces, [endpoint: "ftp://example.com"], %{}) ==
             {:error, :invalid_endpoint}
  end
end
