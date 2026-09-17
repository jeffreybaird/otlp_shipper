defmodule OtlpShipper.TraceSuppressionTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias OtlpShipper.TraceSuppressionProbe

  test "TCP-07 marked Finch HTTP is suppressed and ordinary sampling resumes in the worker" do
    assert {:ok, evidence} = TraceSuppressionProbe.run(:always_on)
    assert evidence.http_statuses == [200, 200, 200]
    assert evidence.request_paths == ["/ordinary-before", "/exporter", "/ordinary-after"]
    assert evidence.exported_paths == ["/ordinary-before", "/ordinary-after"]
    assert evidence.marker_before == :original
    assert evidence.marker_after == :original
  end

  test "TCP-07 the configured always-off sampler still controls ordinary requests" do
    assert {:ok, evidence} = TraceSuppressionProbe.run(:always_off)
    assert evidence.http_statuses == [200, 200, 200]
    assert evidence.request_paths == ["/ordinary-before", "/exporter", "/ordinary-after"]
    assert evidence.exported_paths == []
    assert evidence.marker_before == :original
    assert evidence.marker_after == :original
  end
end
