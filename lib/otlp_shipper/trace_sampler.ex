if Code.ensure_loaded?(:otel_sampler) do
  defmodule OtlpShipper.TraceSampler do
    @moduledoc """
    Consumer-configured sampler wrapper that prevents exporter HTTP feedback.

    Configure the SDK sampler as `{OtlpShipper.TraceSampler, delegate}`, where
    `delegate` is its existing sampler specification, for example `:always_on`
    or `{:parent_based, %{root: :always_on}}`. The shipper never installs this
    wrapper or changes application configuration itself.

    Only the exact exporter context marker overrides the delegate. Other spans
    retain the delegate's sampling decision, attributes, and trace state. This
    supports synchronous Finch instrumentation; instrumentation crossing process
    boundaries must propagate the context and be verified separately.

    This module is compiled only when the optional tracing SDK is available.
    Adding the SDK later requires recompiling this dependency.
    """
    @behaviour :otel_sampler

    @impl true
    @doc "Initializes the consumer's delegate using the SDK's sampler contract."
    @spec setup(:otel_sampler.sampler_spec()) :: :otel_sampler.t()
    def setup(delegate), do: :otel_sampler.new(delegate)

    @impl true
    @doc "Identifies the wrapper and its configured delegate."
    @spec description(:otel_sampler.t()) :: binary()
    def description(delegate),
      do: "OtlpShipperTraceSampler(" <> :otel_sampler.description(delegate) <> ")"

    @impl true
    @doc "Drops marked exporter spans and otherwise preserves the delegate's result."
    @spec should_sample(
            :otel_ctx.t(),
            :opentelemetry.trace_id(),
            :otel_links.t(),
            :opentelemetry.span_name(),
            :opentelemetry.span_kind(),
            :opentelemetry.attributes_map(),
            :otel_sampler.t()
          ) :: :otel_sampler.sampling_result()
    def should_sample(ctx, trace_id, links, name, kind, attributes, delegate) do
      if :otel_ctx.get_value(ctx, :otlp_shipper_export, false) == true do
        span = :otel_tracer.current_span_ctx(ctx)
        {:drop, [], :otel_span.tracestate(span)}
      else
        :otel_sampler.should_sample(delegate, ctx, trace_id, links, name, kind, attributes)
      end
    end
  end
end
