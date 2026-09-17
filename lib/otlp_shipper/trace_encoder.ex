defmodule OtlpShipper.TraceEncoder do
  @moduledoc "Encodes trace envelopes while preserving resource and instrumentation scope identity."
  alias OtlpShipper.TraceValue
  @request_type :"opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest"

  @doc """
  Encodes converted spans under an authoritative resource, capped at one MiB.

  Resource attributes are native values, with optional `schema_url` and
  `dropped_attributes_count`. Empty valid resources are retained. Bounds apply
  before materialization and to the exact generated request bytes before gzip.

      iex> {:ok, bytes} = OtlpShipper.TraceEncoder.encode([], %{attributes: %{}})
      iex> is_binary(bytes)
      true
  """
  @spec encode([map()], map()) :: {:ok, binary()} | {:error, atom()}
  @spec encode([map()], map(), pos_integer()) :: {:ok, binary()} | {:error, atom()}
  def encode(spans, resource, max_bytes \\ 1_048_576)

  def encode(spans, resource, max_bytes)
      when is_list(spans) and is_integer(max_bytes) and max_bytes > 0 do
    with {:ok, resource, schema} <- resource(resource, max_bytes),
         {:ok, scopes} <- scopes(spans, max_bytes) do
      request = %{
        resource_spans: [%{resource: resource, schema_url: schema, scope_spans: scopes}]
      }

      encoded = :otlp_shipper_trace_service.encode_msg(request, @request_type, [:verify])
      if byte_size(encoded) <= max_bytes, do: {:ok, encoded}, else: {:error, :batch_too_large}
    end
  rescue
    _ -> {:error, :invalid_payload}
  end

  def encode(_, _, _), do: {:error, :invalid_payload}

  # Validate resource identity without invoking logs/metrics resource defaults.
  defp resource(%{attributes: attrs} = input, max_bytes) do
    if TraceValue.bounded?(input, max_bytes * 4) do
      resource_fields(input, attrs)
    else
      {:error, :batch_too_large}
    end
  end

  defp resource(_, _), do: {:error, :invalid_resource}

  # Catch only within the resource boundary so callers distinguish invalid identity.
  defp resource_fields(input, attrs) do
    count = Map.get(input, :dropped_attributes_count, 0)

    if not is_integer(count) or count < 0 or count > 4_294_967_295,
      do: throw(:invalid_trace_value)

    {:ok, %{attributes: TraceValue.attributes(attrs), dropped_attributes_count: count},
     TraceValue.string(Map.get(input, :schema_url, ""))}
  rescue
    _ -> {:error, :invalid_resource}
  catch
    _ -> {:error, :invalid_resource}
  end

  # The input budget bounds both grouping state and generated-message verification.
  defp scopes(spans, max_bytes) do
    if TraceValue.bounded?(spans, max_bytes * 4) do
      grouped = Enum.group_by(spans, &scope_identity/1)
      ordered = spans |> Enum.map(&scope_identity/1) |> Enum.uniq()
      {:ok, Enum.map(ordered, &scope_envelope(&1, Map.fetch!(grouped, &1)))}
    else
      {:error, :batch_too_large}
    end
  rescue
    _ -> {:error, :invalid_payload}
  catch
    _ -> {:error, :invalid_payload}
  end

  # Schema URL participates in identity even when name and version match.
  defp scope_identity(%{scope: %{name: name, version: version, schema_url: schema}, span: span})
       when is_map(span) do
    {TraceValue.string(name), TraceValue.string(version), TraceValue.string(schema)}
  end

  defp scope_envelope({name, version, schema}, records) do
    %{
      scope: %{name: name, version: version},
      schema_url: schema,
      spans: Enum.map(records, & &1.span)
    }
  end
end
