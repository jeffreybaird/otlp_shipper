defmodule OtlpShipper.TraceCompatibilityTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias OtlpShipper.TraceCompatibilityProbe

  test "TCP-01 SDK callback owns its table and releases it on completion" do
    assert {:ok, evidence} = TraceCompatibilityProbe.run(:batch_lifetime)
    assert evidence.flush_result == :ok
    assert is_pid(evidence.callback_worker)
    assert evidence.table_owner == evidence.callback_worker
    assert evidence.span_count == 1
    assert evidence.table_after == :undefined
  end

  test "TCP-02 SDK deadline kills the export worker and linked child" do
    assert {:ok, evidence} = TraceCompatibilityProbe.run(:cancellation)
    assert evidence.worker_down_reason == :killed
    assert evidence.linked_child_down_reason == :killed
    assert evidence.table_after == :undefined
  end

  test "TCP-03 failed_retryable does not replay the original span on another flush" do
    assert {:ok, evidence} = TraceCompatibilityProbe.run(:retry_result)
    assert evidence.first_export_count == 1
    assert evidence.replay_count == 0
    assert evidence.table_after == :undefined
  end

  test "TCP-04 force flush is asynchronous and termination omits exporter shutdown" do
    assert {:ok, evidence} = TraceCompatibilityProbe.run(:flush_shutdown)
    assert evidence.flush_result == :ok
    assert evidence.worker_blocked_after_flush
    assert evidence.final_export_count == 1
    assert evidence.shutdown_callback_count == 0
  end

  test "TCP-05 queue admission is periodic rather than a strict retention bound" do
    assert {:ok, evidence} = TraceCompatibilityProbe.run(:queue_bound)
    assert evidence.configured_limit == 1
    assert evidence.accepted_before_check > evidence.configured_limit
    assert evidence.admission_after_check == false
  end

  test "TCP-06 independent supervised pools and deadline workers are cleaned up" do
    assert {:ok, evidence} = TraceCompatibilityProbe.run(:owned_lifecycle)
    assert evidence.initial_pools_ready
    assert evidence.first_pool_down_reason == :shutdown
    assert evidence.second_pool_alive
    assert evidence.second_pool_down_reason == :shutdown
    assert evidence.conversion_down_reason == :killed
    assert evidence.retry_child_down_reason == :killed
    assert evidence.timeout_ms > 0
    assert evidence.elapsed_ms >= evidence.timeout_ms
    assert evidence.elapsed_ms <= 1000
  end
end
