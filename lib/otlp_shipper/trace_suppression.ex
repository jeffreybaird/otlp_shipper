defmodule OtlpShipper.TraceSuppression do
  @moduledoc false

  # Internal boundary for exporter HTTP work; the callback result is preserved.
  @doc false
  @spec with_suppression((-> result)) :: result when result: term()
  if Code.ensure_loaded?(:otel_ctx) do
    def with_suppression(fun) when is_function(fun, 0), do: with_context(fun)

    # Restore the complete previous context even when the request raises or throws.
    defp with_context(fun) do
      context = :otel_ctx.set_value(:otel_ctx.get_current(), :otlp_shipper_export, true)
      token = :otel_ctx.attach(context)

      try do
        fun.()
      after
        :otel_ctx.detach(token)
      end
    end
  else
    # Optional tracing additions require recompilation, as with the SDK adapter.
    def with_suppression(fun) when is_function(fun, 0), do: fun.()
  end
end
