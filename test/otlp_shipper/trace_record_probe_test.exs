defmodule OtlpShipper.TraceRecordProbeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias OtlpShipper.TraceCompatibilityProbe

  test "TCP-09 real SDK records expose identity, timestamps, resources, scopes, and losses" do
    assert {:ok, evidence} = TraceCompatibilityProbe.run(:record_fidelity)
    assert evidence.trace_id == 1
    assert evidence.parent_span_id == 2
    assert evidence.parent_span_is_remote
    assert is_integer(evidence.span_id) and evidence.span_id > 0
    assert evidence.name == "fidelity"
    assert evidence.kind == :client
    assert evidence.trace_flags == 1
    assert evidence.tracestate == [{"vendor", "value"}]
    assert evidence.status == {:status, :error, "probe failure"}
    assert evidence.resource_attributes["service.name"] == "trace-probe"
    assert evidence.resource_schema_url == "https://probe/resource"
    assert evidence.scope_name == "trace_probe"
    assert evidence.scope_version == "1.0"
    assert evidence.scope_schema_url == "https://probe/scope"
    assert evidence.start_unix_nano > 0
    assert evidence.end_unix_nano >= evidence.start_unix_nano
    assert evidence.event_unix_nano >= evidence.start_unix_nano
    assert evidence.event_unix_nano <= evidence.end_unix_nano
    assert evidence.configured_attribute_limit > 0
    assert evidence.configured_event_limit > 0
    assert evidence.configured_link_limit > 0
    assert evidence.attribute_count == evidence.configured_attribute_limit
    assert evidence.event_count == evidence.configured_event_limit
    assert evidence.link_count == evidence.configured_link_limit
    assert evidence.dropped_attributes == 1
    assert evidence.dropped_events == 1
    assert evidence.dropped_links == 1
    assert evidence.dropped_event_attributes == 1
    assert evidence.dropped_link_attributes == 1
  end
end
