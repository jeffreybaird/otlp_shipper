defmodule OtlpShipper.Acceptance.TraceContractSteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions

  alias OtlpShipper.TraceCompatibilityProbe

  when_("I probe an owned transport pool crash with two real SDK instances", fn world ->
    assert {:ok, evidence} = TraceCompatibilityProbe.run(:pool_restart)
    Map.put(world, :restart_evidence, evidence)
  end)

  then_("the dependent SDK processes restart and both instances export afterward", fn world ->
    evidence = world.restart_evidence
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
    world
  end)

  when_("I capture a real SDK span with remote context and overflowing metadata", fn world ->
    assert {:ok, evidence} = TraceCompatibilityProbe.run(:record_fidelity)
    Map.put(world, :record_evidence, evidence)
  end)

  then_("the SDK record preserves its configured identity resource and scope", fn world ->
    evidence = world.record_evidence
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
    world
  end)

  then_("its timestamps retain ordering after conversion to Unix nanoseconds", fn world ->
    evidence = world.record_evidence
    assert evidence.start_unix_nano > 0
    assert evidence.end_unix_nano >= evidence.start_unix_nano
    assert evidence.event_unix_nano >= evidence.start_unix_nano
    assert evidence.event_unix_nano <= evidence.end_unix_nano
    world
  end)

  then_("SDK accessors report the configured retained counts and each overflow loss", fn world ->
    evidence = world.record_evidence
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
    world
  end)
end
