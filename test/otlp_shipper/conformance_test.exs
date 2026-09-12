defmodule OtlpShipper.ConformanceTest do
  use ExUnit.Case, async: true
  alias OtlpShipper.Conformance

  @fixture File.read!(Path.expand("../fixtures/conformance/collector-0.160.0.txt", __DIR__))

  test "recognizes the real Collector's decoded signals" do
    assert :ok = Conformance.verify(@fixture)

    for {before, after_value} <- [
          {"SeverityNumber: Info2(10)", "SeverityNumber: Error(17)"},
          {"Body: Str(otlp-shipper-conformance-log)", "Body: Str(other)"},
          {"conformance: Bool(true)", "conformance: Bool(false)"},
          {"region: Str(test)", "region: Str(other)"},
          {"Value: 3\n", "Value: 30\n"},
          {"Value: 21\n", "Value: 210\n"},
          {"Value: 12\n", "Value: 120\n"},
          {"DataType: Gauge", "DataType: Sum"},
          {"AggregationTemporality: Delta", "AggregationTemporality: Cumulative"},
          {"Buckets #2, Count: 1", "Buckets #2, Count: 0"},
          {"ExplicitBounds #1: 10.000000", "ExplicitBounds #1: 100.000000"},
          {"service.name: Str(otlp-shipper-conformance)", "service.name: Str(other)"}
        ] do
      assert {:error, :collector_output_mismatch} =
               Conformance.verify(String.replace(@fixture, before, after_value))
    end

    swapped =
      @fixture
      |> String.replace("Value: 21\n", "Value: swapped\n")
      |> String.replace("Value: 3\n", "Value: 21\n")
      |> String.replace("Value: swapped\n", "Value: 3\n")

    assert {:error, :collector_output_mismatch} = Conformance.verify(swapped)
    assert {:error, :collector_output_mismatch} = Conformance.verify("")
  end

  test "accepts only Docker's loopback port mapping" do
    assert {:ok, "http://127.0.0.1:49152"} = Conformance.endpoint("127.0.0.1:49152\n")

    for address <- ["0.0.0.0:49152", "127.0.0.1:abc", "127.0.0.1:1\n[::]:1"] do
      assert {:error, :invalid_docker_port} = Conformance.endpoint(address)
    end
  end

  test "removes all inherited OTEL settings only in the child process" do
    env = %{
      "OTEL_EXPORTER_OTLP_HEADERS" => "secret",
      "OTEL_RESOURCE_ATTRIBUTES" => "secret",
      "PATH" => "/bin",
      "MIX_ENV" => "dev"
    }

    assert Map.new(Conformance.clean_environment(env)) ==
             %{"OTEL_EXPORTER_OTLP_HEADERS" => nil, "OTEL_RESOURCE_ATTRIBUTES" => nil}

    assert [] = Conformance.clean_environment(%{})
  end

  test "orchestrates Docker and a separate fixture VM, then removes its container" do
    owner = self()

    command = fn executable, args, opts ->
      send(owner, {:command, executable, args, opts})

      case {executable, args} do
        {"docker", ["port" | _]} -> {"127.0.0.1:49152\n", 0}
        {"docker", ["logs" | _]} -> {@fixture, 0}
        _ -> {"", 0}
      end
    end

    assert :ok = Conformance.run(command)
    assert_receive {:command, "docker", ["run" | run_args], _}
    assert "127.0.0.1::4318" in run_args
    assert "--pull=never" in run_args

    assert_receive {:command, "mix", ["run", "--no-compile", script, "http://127.0.0.1:49152"],
                    opts}

    assert String.ends_with?(script, "/conformance/emit.exs")
    assert Keyword.has_key?(opts, :env)
    assert_receive {:command, "docker", ["rm", "--force", name], _}
    assert name in run_args
  end

  test "failed and missing executables still attempt cleanup" do
    owner = self()

    for failure <- [:exit_status, :missing] do
      command = fn executable, args, _ ->
        send(owner, {:attempt, executable, args})

        case args do
          ["rm" | _] -> {"", 0}
          _ when failure == :exit_status -> {"synthetic error", 1}
          _ -> :erlang.error(:enoent)
        end
      end

      assert {:error, reason} = Conformance.run(command)
      assert reason in [:command_failed, :command_unavailable]
      assert_receive {:attempt, "docker", ["rm", "--force", _]}
    end
  end

  test "fixture failure removes the container and does not claim conformance" do
    owner = self()

    command = fn executable, args, _ ->
      case {executable, args} do
        {"docker", ["port" | _]} ->
          {"127.0.0.1:49152", 0}

        {"docker", ["logs" | _]} ->
          {@fixture, 0}

        {"mix", _} ->
          {"synthetic fixture failure", 1}

        {"docker", ["rm" | _]} ->
          send(owner, :cleaned)
          {"", 0}

        _ ->
          {"", 0}
      end
    end

    assert {:error, :command_failed} = Conformance.run(command)
    assert_receive :cleaned
  end

  test "rejects task arguments before starting Docker" do
    assert_raise Mix.Error, "Usage: mix otlp_shipper.conformance", fn ->
      Mix.Tasks.OtlpShipper.Conformance.run(["unexpected"])
    end
  end
end
