defmodule OtlpShipper.Acceptance.TraceSuppressionSteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions

  alias OtlpShipper.TraceSuppressionProbe

  given_("a real Finch instrumentation probe delegating to {string}", fn world, sampler ->
    Map.put(world, :suppression_sampler, sampler_name(sampler))
  end)

  when_(
    "the worker sends ordinary, exporter-marked, and subsequent ordinary HTTP requests",
    fn world ->
      assert {:ok, evidence} = TraceSuppressionProbe.run(world.suppression_sampler)
      Map.put(world, :suppression_evidence, evidence)
    end
  )

  then_("the loopback server accepts all three requests", fn world ->
    assert world.suppression_evidence.http_statuses == [200, 200, 200]

    assert world.suppression_evidence.request_paths == [
             "/ordinary-before",
             "/exporter",
             "/ordinary-after"
           ]

    world
  end)

  then_("the worker restores its original export marker after the marked request", fn world ->
    assert world.suppression_evidence.marker_before == :original
    assert world.suppression_evidence.marker_after == :original
    world
  end)

  then_("the exported HTTP paths match the {string} sampling policy", fn world, sampler ->
    assert world.suppression_evidence.exported_paths == expected_paths(sampler)
    world
  end)

  # Only the explicitly supported sampler cases may enter the probe.
  defp sampler_name("always_on"), do: :always_on
  defp sampler_name("always_off"), do: :always_off

  # The configured delegate controls requests outside the marked export operation.
  defp expected_paths("always_on"), do: ["/ordinary-before", "/ordinary-after"]
  defp expected_paths("always_off"), do: []
end
