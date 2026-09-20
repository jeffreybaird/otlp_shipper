defmodule OtlpShipper.TraceSDKSamplerTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias OtlpShipper.{TraceSampler, TraceSuppression}

  test "TSDK-06 only the exact exporter marker overrides configured sampling" do
    for delegate <- [:always_on, :always_off] do
      state = TraceSampler.setup(delegate)
      ordinary = :otel_sampler.new(delegate)

      for marker <- [false, :original, nil] do
        context = :otel_ctx.set_value(:otel_ctx.new(), :otlp_shipper_export, marker)

        assert TraceSampler.should_sample(context, 1, [], "ordinary", :client, %{}, state) ==
                 :otel_sampler.should_sample(ordinary, context, 1, [], "ordinary", :client, %{})
      end

      context = :otel_ctx.set_value(:otel_ctx.new(), :otlp_shipper_export, true)

      assert {:drop, [], _} =
               TraceSampler.should_sample(context, 1, [], "exporter", :client, %{}, state)

      assert is_binary(TraceSampler.description(state))
    end
  end

  test "TSDK-06 marked sampling preserves remote parent trace state" do
    remote = :otel_tracer.from_remote_span(1, 2, 1)
    context = :otel_tracer.set_current_span(:otel_ctx.new(), remote)
    context = :otel_ctx.set_value(context, :otlp_shipper_export, true)
    state = TraceSampler.setup(:always_on)

    assert {:drop, [], state_after} =
             TraceSampler.should_sample(context, 1, [], "export", :client, %{}, state)

    assert state_after == :otel_span.tracestate(remote)
  end

  test "TSDK-06 suppression restores the complete calling context after success and failures" do
    original = :otel_ctx.set_value(:otel_ctx.new(), :otlp_shipper_export, :original)
    original = :otel_ctx.set_value(original, :unrelated_probe, 42)
    token = :otel_ctx.attach(original)

    try do
      assert TraceSuppression.with_suppression(fn ->
               assert :otel_ctx.get_value(:otlp_shipper_export) == true
               :value
             end) == :value

      assert :otel_ctx.get_current() == original

      assert_raise RuntimeError, "probe failure", fn ->
        TraceSuppression.with_suppression(fn -> raise "probe failure" end)
      end

      assert :otel_ctx.get_current() == original

      assert catch_throw(TraceSuppression.with_suppression(fn -> throw(:probe_throw) end)) ==
               :probe_throw

      assert :otel_ctx.get_current() == original
    after
      :otel_ctx.detach(token)
    end
  end
end
