defmodule OtlpShipper.TracePoolRestartTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias OtlpShipper.TraceCompatibilityProbe

  test "TCP-08 pool failure restarts dependent SDK processes without disturbing another instance" do
    assert {:ok, evidence} = TraceCompatibilityProbe.run(:pool_restart)
    assert evidence.old_pool_down_reason == :killed
    assert is_pid(evidence.old_pool) and is_pid(evidence.new_pool)
    assert evidence.old_pool != evidence.new_pool
    assert is_pid(evidence.old_provider) and is_pid(evidence.new_provider)
    assert evidence.old_provider != evidence.new_provider
    assert is_pid(evidence.old_processor) and is_pid(evidence.new_processor)
    assert evidence.old_processor != evidence.new_processor
    assert is_pid(evidence.second_provider_before)
    assert evidence.second_provider_before == evidence.second_provider_after
    assert evidence.first_exported_names == ["after-restart"]
    assert evidence.second_exported_names == ["unaffected"]
  end
end
