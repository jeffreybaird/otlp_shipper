defmodule OtlpShipper.ConfigTest do
  use ExUnit.Case, async: true
  alias OtlpShipper.Config
  doctest Config

  test "endpoint precedence and path appending are signal aware" do
    env = %{
      "OTEL_EXPORTER_OTLP_ENDPOINT" => "https://collector/base/?token=opaque",
      "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT" => "https://logs/custom"
    }

    assert {:ok, %{endpoint: "https://logs/custom"}} =
             Config.new(:logs, [service_name: "test"], env)

    assert {:ok, %{endpoint: "https://collector/base/v1/metrics?token=opaque"}} =
             Config.new(:metrics, [service_name: "test"], env)

    assert {:ok, %{endpoint: "https://explicit/"}} =
             Config.new(:logs, [service_name: "test", endpoint: "https://explicit"], env)

    assert {:ok, %{endpoint: "https://explicit/v1/logs"}} =
             Config.new(:logs, [service_name: "test", base_endpoint: "https://explicit/"], env)

    assert {:ok, %{endpoint: "http://localhost:4318/v1/logs"}} =
             Config.new(:logs, [service_name: "test"], %{"OTEL_EXPORTER_OTLP_ENDPOINT" => ""})
  end

  test "rejects unsafe and malformed endpoints" do
    for url <- [
          nil,
          1,
          "file:///tmp/foo",
          "https:///",
          "https://user:secret@host",
          "http://host/#fragment",
          "http://host:0",
          "http://host:99999"
        ] do
      assert {:error, :invalid_endpoint} = Config.new(:logs, service_name: "test", endpoint: url)
    end
  end

  test "signal settings override generic settings and explicit options win" do
    env = %{
      "OTEL_EXPORTER_OTLP_HEADERS" => "authorization=Bearer%20secret",
      "OTEL_EXPORTER_OTLP_LOGS_HEADERS" => "x-key=a%2Cb%3Dc",
      "OTEL_EXPORTER_OTLP_TIMEOUT" => "4000",
      "OTEL_EXPORTER_OTLP_LOGS_TIMEOUT" => "1000",
      "OTEL_EXPORTER_OTLP_COMPRESSION" => "gzip"
    }

    assert {:ok, config} = Config.new(:logs, [service_name: "test"], env)
    assert config.headers == [{"x-key", "a,b=c"}]
    assert config.timeout == 1000
    assert config.compression == :gzip
    assert {:ok, config} = Config.new(:metrics, [service_name: "test"], env)
    assert config.headers == [{"authorization", "Bearer secret"}]
    assert config.timeout == 4000

    assert {:ok, config} =
             Config.new(
               :logs,
               [service_name: "test", headers: [], timeout: 12, compression: :none],
               env
             )

    assert config.headers == []
    assert config.timeout == 12
    assert config.compression == :none
  end

  test "normalizes explicit headers, redacts configuration inspection and rejects injection" do
    assert {:ok, config} =
             Config.new(:logs,
               service_name: "test",
               headers: %{"Authorization" => "Bearer hidden"}
             )

    assert config.headers == [{"authorization", "Bearer hidden"}]
    refute inspect(config) =~ "hidden"

    for headers <- [
          [{"X", "hello\r\nInjected: yes"}],
          [{"bad key", "x"}],
          [{:authorization, "x"}],
          ["x"],
          nil
        ] do
      assert {:error, :invalid_headers} =
               Config.new(:logs, service_name: "test", headers: headers)
    end

    assert {:error, :reserved_header} =
             Config.new(:logs, service_name: "test", headers: [{"Content-Type", "text/plain"}])

    for value <- ["missing_equals", "=empty", "x=%ZZ", "x=%FF"] do
      assert {:error, :invalid_headers} =
               Config.new(:logs, [service_name: "test"], %{"OTEL_EXPORTER_OTLP_HEADERS" => value})
    end
  end

  test "validates options and finite limits" do
    assert {:error, :unknown_option, :typo} = Config.new(:logs, typo: 1)
    assert {:error, :invalid_options} = Config.new(:logs, %{})

    assert {:error, :invalid_compression} =
             Config.new(:logs, service_name: "test", compression: :br)

    assert {:error, :unsupported_protocol} =
             Config.new(:logs, [service_name: "test"], %{"OTEL_EXPORTER_OTLP_PROTOCOL" => "grpc"})

    for key <- [
          :timeout,
          :retry_base_ms,
          :retry_max_ms,
          :max_response_bytes,
          :max_queue,
          :max_batch,
          :max_item_bytes,
          :max_batch_bytes,
          :flush_ms,
          :shutdown_ms
        ] do
      assert {:error, :invalid_option, ^key} =
               Config.new(:logs, [{:service_name, "test"}, {key, 0}])
    end

    for retries <- [-1, 101, "3"] do
      assert {:error, :invalid_option, :max_retries} =
               Config.new(:logs, service_name: "test", max_retries: retries)
    end

    assert {:ok, %{max_retries: 0}} = Config.new(:logs, service_name: "test", max_retries: 0)

    assert {:error, :invalid_option, :max_batch} =
             Config.new(:logs, service_name: "test", max_queue: 1)

    assert {:error, :invalid_option, :max_item_bytes} =
             Config.new(:logs, service_name: "test", max_batch_bytes: 1)

    assert {:error, :invalid_option, :retry_base_ms} =
             Config.new(:logs, service_name: "test", retry_max_ms: 1)

    for value <- ["2seconds", "-1", "never", 12] do
      assert {:error, :invalid_option, :timeout} =
               Config.new(:logs, [service_name: "test"], %{"OTEL_EXPORTER_OTLP_TIMEOUT" => value})
    end
  end

  test "runtime loading honors explicit options" do
    assert {:ok, %{endpoint: "http://localhost:4318/v1/logs"}} =
             Config.load(:logs,
               service_name: "test",
               endpoint: "http://localhost:4318/v1/logs",
               headers: [],
               compression: :none,
               timeout: 10
             )
  end
end
