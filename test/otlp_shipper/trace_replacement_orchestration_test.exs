defmodule OtlpShipper.TraceReplacementOrchestrationTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias OtlpShipper.Conformance

  @legacy File.read!(Path.expand("../fixtures/conformance/collector-0.160.0.txt", __DIR__))

  test "TRP-03 successful logs and metrics alone cannot complete three-signal conformance" do
    reads = :atomics.new(1, [])
    owner = self()

    command = fn executable, args, _options ->
      case {executable, args} do
        {"docker", ["port" | _]} ->
          {"127.0.0.1:49152\n", 0}

        {"docker", ["logs" | _]} ->
          if :atomics.add_get(reads, 1, 1) <= 2,
            do: {@legacy, 0},
            else: {"synthetic stop after observing missing traces", 1}

        {"docker", ["rm", "--force", _]} ->
          send(owner, :trace_conformance_cleaned)
          {"", 0}

        _ ->
          {"", 0}
      end
    end

    assert Conformance.run(command) == {:error, :command_failed}
    assert :atomics.get(reads, 1) == 3
    assert_receive :trace_conformance_cleaned
  end
end
