defmodule OtlpShipper.Acceptance.TraceCompatibilitySteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions

  alias OtlpShipper.TraceCompatibilityProbe

  given_("the trace compatibility probe {string}", fn world, name ->
    Map.put(world, :probe, probe_name(name))
  end)

  when_("I run the real SDK compatibility probe", fn world ->
    assert {:ok, evidence} = TraceCompatibilityProbe.run(world.probe)
    Map.put(world, :evidence, evidence)
  end)

  then_("the export worker owns the single-span table until completion", fn world ->
    evidence = world.evidence
    assert evidence.flush_result == :ok
    assert is_pid(evidence.callback_worker)
    assert evidence.table_owner == evidence.callback_worker
    assert evidence.span_count == 1
    assert evidence.table_after == :undefined
    world
  end)

  then_("the timed-out worker and linked child are killed and the table is deleted", fn world ->
    assert world.evidence.worker_down_reason == :killed
    assert world.evidence.linked_child_down_reason == :killed
    assert world.evidence.table_after == :undefined
    world
  end)

  then_("the original batch is exported once without replay after another flush", fn world ->
    assert world.evidence.first_export_count == 1
    assert world.evidence.replay_count == 0
    assert world.evidence.table_after == :undefined
    world
  end)

  then_(
    "flush returns while export is blocked and termination does not invoke exporter shutdown",
    fn world ->
      assert world.evidence.flush_result == :ok
      assert world.evidence.worker_blocked_after_flush
      assert world.evidence.final_export_count == 1
      assert world.evidence.shutdown_callback_count == 0
      world
    end
  )

  then_("the burst exceeds the configured queue setting before admission closes", fn world ->
    assert world.evidence.configured_limit == 1
    assert world.evidence.accepted_before_check > world.evidence.configured_limit
    assert world.evidence.admission_after_check == false
    world
  end)

  then_(
    "independent pools stop with their owners and conversion work respects the deadline",
    fn world ->
      evidence = world.evidence
      assert evidence.initial_pools_ready
      assert evidence.first_pool_down_reason == :shutdown
      assert evidence.second_pool_alive
      assert evidence.second_pool_down_reason == :shutdown
      assert evidence.conversion_down_reason == :killed
      assert evidence.retry_child_down_reason == :killed
      assert evidence.timeout_ms > 0
      assert evidence.elapsed_ms >= evidence.timeout_ms
      assert evidence.elapsed_ms <= 1000
      world
    end
  )

  # Accept only the finite probe cases; never create atoms from feature input.
  defp probe_name("batch_lifetime"), do: :batch_lifetime
  defp probe_name("cancellation"), do: :cancellation
  defp probe_name("retry_result"), do: :retry_result
  defp probe_name("flush_shutdown"), do: :flush_shutdown
  defp probe_name("queue_bound"), do: :queue_bound
  defp probe_name("owned_lifecycle"), do: :owned_lifecycle
end
