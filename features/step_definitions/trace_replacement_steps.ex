defmodule OtlpShipper.Acceptance.TraceReplacementSteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions
  alias OtlpShipper.Conformance

  @fixture_root Path.expand("../../test/fixtures/conformance", __DIR__)

  given_("the trace Collector verification fixture", fn world ->
    Map.put(
      world,
      :collector_output,
      File.read!(Path.join(@fixture_root, "collector-traces-0.160.0.txt"))
    )
  end)

  when_("I verify its trace records and correlated log", fn world ->
    Map.put(world, :trace_verification, Conformance.verify_traces(world.collector_output))
  end)

  then_("the trace conformance verifier accepts the relationships", fn world ->
    assert world.trace_verification == :ok
    world
  end)

  when_("I alter its {string} evidence", fn world, field ->
    changed = alter_evidence(world.collector_output, field)
    refute changed == world.collector_output
    Map.put(world, :trace_verification, Conformance.verify_traces(changed))
  end)

  then_("the trace conformance verifier rejects the changed output", fn world ->
    assert world.trace_verification == {:error, :collector_trace_output_mismatch}
    world
  end)

  when_("I run conformance with only logs and metrics before command failure", fn world ->
    legacy = File.read!(Path.join(@fixture_root, "collector-0.160.0.txt"))
    reads = :atomics.new(1, [])
    owner = self()

    command = fn executable, args, _ ->
      case {executable, args} do
        {"docker", ["port" | _]} ->
          {"127.0.0.1:49152\n", 0}

        {"docker", ["logs" | _]} ->
          if :atomics.add_get(reads, 1, 1) <= 2, do: {legacy, 0}, else: {"fixture stop", 1}

        {"docker", ["rm", "--force", _]} ->
          send(owner, :replacement_cleaned)
          {"", 0}

        _ ->
          {"", 0}
      end
    end

    result = Conformance.run(command)
    assert_receive :replacement_cleaned
    Map.put(world, :run_evidence, %{result: result, reads: :atomics.get(reads, 1)})
  end)

  then_("conformance fails after checking for traces and cleans up its container", fn world ->
    assert world.run_evidence == %{result: {:error, :command_failed}, reads: 3}
    world
  end)

  given_("a synthetic replacement report matching the fresh consumer report format", fn world ->
    report =
      @fixture_root
      |> Path.join("replacement-report-synthetic.json")
      |> File.read!()
      |> :json.decode()

    Map.put(world, :replacement_report, report)
  end)

  when_("I validate the replacement evidence report", fn world ->
    Map.put(
      world,
      :report_result,
      Conformance.verify_replacement_report(world.replacement_report)
    )
  end)

  then_(
    "the report validator accepts its structure without claiming a real smoke run",
    fn world ->
      assert world.report_result == :ok
      world
    end
  )

  when_("the report says the canonical exporter is present", fn world ->
    report = Map.put(world.replacement_report, "canonical_exporter_present", true)
    Map.put(world, :report_result, Conformance.verify_replacement_report(report))
  end)

  then_("the replacement report validator rejects the evidence", fn world ->
    assert world.report_result == {:error, :replacement_report_mismatch}
    world
  end)

  # Mutate exact fixture fields rather than appending globally matching text.
  defp alter_evidence(output, "child status"),
    do: String.replace(output, "Status code    : Error", "Status code    : Unset")

  defp alter_evidence(output, "log span ID"),
    do: Regex.replace(~r/^Span ID: [0-9a-f]+$/m, output, "Span ID: 9999999999999999")

  defp alter_evidence(output, "instrumentation"),
    do:
      String.replace(
        output,
        "InstrumentationScope conformance.sdk 1.0",
        "InstrumentationScope other 1.0"
      )
end
