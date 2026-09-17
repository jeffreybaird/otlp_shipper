defmodule OtlpShipper.TraceRuntimeConfigTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias OtlpShipper.Config

  test "TPC-01 runtime transport resolution reads current settings without mutating earlier config" do
    inherited = Map.filter(System.get_env(), fn {key, _} -> String.starts_with?(key, "OTEL_") end)
    Enum.each(inherited, fn {key, _} -> System.delete_env(key) end)

    on_exit(fn ->
      System.get_env()
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "OTEL_"))
      |> Enum.each(&System.delete_env/1)

      System.put_env(inherited)
    end)

    System.put_env("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "https://before.example/exact")
    assert {:ok, before} = Config.load_transport(:traces, [])
    System.put_env("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "https://after.example/exact")
    assert {:ok, after_config} = Config.load_transport(:traces, [])
    assert before.endpoint == "https://before.example/exact"
    assert after_config.endpoint == "https://after.example/exact"
    assert before.resource == nil
    assert after_config.resource == nil
  end
end
