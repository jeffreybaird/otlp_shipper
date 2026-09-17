defmodule OtlpShipper.TraceRecord do
  @moduledoc """
  Converts SDK-independent normalized span maps to generated OTLP message inputs.

  IDs are nonzero integers; only a nil parent denotes a root. Times are native
  monotonic integers and `time_offset` is a native epoch offset captured by the
  caller. Scope identity is kept outside the individual span size limit. Attributes
  accept SDK scalar types and homogeneous flat lists/tuples without stringification.

  Required fields are `trace_id`, `span_id`, `name`, `kind`, `start_time`,
  `end_time`, and `trace_flags`. Optional `parent_span_id` defaults to nil;
  `parent_span_is_remote` accepts nil (unknown), false, or true. `tracestate`
  is an ordered list of string pairs. `attributes` is a native map. `events`
  contain `name`, native `time`, attributes and `dropped_attributes_count`;
  `links` contain IDs, tracestate, attributes and their dropped count. Span
  `dropped_attributes_count`, `dropped_events_count`, and `dropped_links_count`
  default to zero. `status` uses `code` (`:unset`, `:ok`, `:error`) and `message`.
  `scope` uses `name`, `version`, and `schema_url`, defaulting to empty strings.
  """
  import Bitwise
  alias OtlpShipper.TraceValue

  @span_type :"opentelemetry.proto.trace.v1.Span"
  @kinds %{
    internal: :SPAN_KIND_INTERNAL,
    server: :SPAN_KIND_SERVER,
    client: :SPAN_KIND_CLIENT,
    producer: :SPAN_KIND_PRODUCER,
    consumer: :SPAN_KIND_CONSUMER
  }
  @statuses %{unset: :STATUS_CODE_UNSET, ok: :STATUS_CODE_OK, error: :STATUS_CODE_ERROR}
  @uint64 18_446_744_073_709_551_615

  @doc """
  Converts a normalized span, capped at 65,536 generated Span bytes by default.

  Errors identify a malformed field, or report `:span_too_large`. Scope strings
  have a separate one-MiB traversal bound and are never truncated.

      iex> span = %{trace_id: 1, span_id: 2, name: "work", kind: :internal,
      ...> start_time: 0, end_time: 0, trace_flags: 1, scope: %{}}
      iex> {:ok, record} = OtlpShipper.TraceRecord.convert(span, 0)
      iex> record.span.trace_id
      <<1::128>>
  """
  @spec convert(map(), integer()) ::
          {:ok, map()} | {:error, :span_too_large} | {:error, :invalid_span, atom()}
  @spec convert(map(), integer(), pos_integer()) ::
          {:ok, map()} | {:error, :span_too_large} | {:error, :invalid_span, atom()}
  def convert(span, time_offset, max_bytes \\ 65_536)

  def convert(span, time_offset, max_bytes)
      when is_map(span) and is_integer(time_offset) and is_integer(max_bytes) and max_bytes > 0 do
    with :ok <- check_size(span, max_bytes),
         {:ok, converted} <- convert_fields(span, time_offset) do
      bytes = :otlp_shipper_trace_service.encode_msg(converted.span, @span_type, [:verify])
      if byte_size(bytes) <= max_bytes, do: {:ok, converted}, else: {:error, :span_too_large}
    end
  rescue
    _ -> {:error, :invalid_span, :encoding}
  end

  def convert(_, _, _), do: {:error, :invalid_span, :input}

  # Fixed input keys avoid copying or traversing irrelevant untrusted map contents.
  defp check_size(span, max_bytes) do
    keys = [:name, :tracestate, :attributes, :events, :links, :status]
    values = Enum.map(keys, &Map.get(span, &1))
    if TraceValue.bounded?(values, max_bytes * 4), do: :ok, else: {:error, :span_too_large}
  end

  # Keep field errors stable while converting nested records without SDK includes.
  defp convert_fields(input, offset) do
    start = timestamp(input[:start_time], offset, :start_time)
    finish = timestamp(input[:end_time], offset, :end_time)
    if finish < start, do: invalid(:end_time)

    converted = %{
      trace_id: identity(input[:trace_id], 128, :trace_id),
      span_id: identity(input[:span_id], 64, :span_id),
      parent_span_id: parent(input[:parent_span_id]),
      trace_state: field(:tracestate, fn -> tracestate(Map.get(input, :tracestate, [])) end),
      name: field(:name, fn -> nonempty(input[:name]) end),
      kind: enum(@kinds, input[:kind], :kind),
      start_time_unix_nano: start,
      end_time_unix_nano: finish,
      flags: flags(input[:trace_flags], input[:parent_span_is_remote]),
      attributes:
        field(:attributes, fn -> TraceValue.attributes(Map.get(input, :attributes, %{})) end),
      dropped_attributes_count: count(input, :dropped_attributes_count),
      events: field(:events, fn -> Enum.map(Map.get(input, :events, []), &event(&1, offset)) end),
      dropped_events_count: count(input, :dropped_events_count),
      links: field(:links, fn -> Enum.map(Map.get(input, :links, []), &link/1) end),
      dropped_links_count: count(input, :dropped_links_count),
      status:
        field(:status, fn -> status(Map.get(input, :status, %{code: :unset, message: ""})) end)
    }

    {:ok, %{span: converted, scope: field(:scope, fn -> scope(Map.get(input, :scope, %{})) end)}}
  catch
    {:invalid_span, key} -> {:error, :invalid_span, key}
  end

  # Nested validation failures belong to the containing public field.
  defp field(key, fun) do
    fun.()
  rescue
    _ -> invalid(key)
  catch
    _ -> invalid(key)
  end

  defp invalid(key), do: throw({:invalid_span, key})

  # Fixed-width identities must fit exactly; zero is never a fabricated identity.
  defp identity(value, bits, key) do
    if is_integer(value) and value > 0 and value < 1 <<< bits,
      do: <<value::unsigned-big-size(bits)>>,
      else: invalid(key)
  end

  defp parent(nil), do: <<>>
  defp parent(value), do: identity(value, 64, :parent_span_id)

  # Epoch conversion applies the captured offset before changing units.
  defp timestamp(value, offset, key) when is_integer(value) do
    result = System.convert_time_unit(value + offset, :native, :nanosecond)
    if result >= 0 and result <= @uint64, do: result, else: invalid(key)
  end

  defp timestamp(_, _, key), do: invalid(key)

  # OTLP keeps low trace flags and represents known remote-parent state separately.
  defp flags(value, remote) when is_integer(value) and value >= 0 and value <= 255 do
    case remote do
      nil -> value
      false -> bor(value, 256)
      true -> bor(value, 768)
      _ -> invalid(:parent_span_is_remote)
    end
  end

  defp flags(_, _), do: invalid(:trace_flags)

  # Generated protobuf enums are selected from fixed atoms, never created from input.
  defp enum(values, value, key), do: Map.get(values, value) || invalid(key)

  defp nonempty(value) do
    value = TraceValue.string(value)
    if value == "", do: throw(:invalid_trace_value), else: value
  end

  # Preserve order and reject ambiguous separators in normalized tracestate members.
  defp tracestate(values) when is_list(values) do
    Enum.map_join(values, ",", fn {key, value} ->
      key = nonempty(key)
      value = nonempty(value)

      if String.contains?(key, [",", "="]) or String.contains?(value, [",", "="]),
        do: throw(:invalid_trace_value)

      key <> "=" <> value
    end)
  end

  defp tracestate(_), do: throw(:invalid_trace_value)

  # Drop counters retain their unsigned protobuf range.
  defp count(map, key) do
    value = Map.get(map, key, 0)
    if is_integer(value) and value >= 0 and value <= 4_294_967_295, do: value, else: invalid(key)
  end

  # Event timestamps follow the same native clock contract as span timestamps.
  defp event(map, offset) when is_map(map) do
    %{
      name: TraceValue.string(Map.fetch!(map, :name)),
      time_unix_nano: timestamp(Map.fetch!(map, :time), offset, :events),
      attributes: TraceValue.attributes(Map.get(map, :attributes, %{})),
      dropped_attributes_count: count(map, :dropped_attributes_count)
    }
  end

  # SDK links expose no flags or remote-parent bit; do not invent either.
  defp link(map) when is_map(map) do
    %{
      trace_id: identity(map[:trace_id], 128, :links),
      span_id: identity(map[:span_id], 64, :links),
      trace_state: tracestate(Map.get(map, :tracestate, [])),
      attributes: TraceValue.attributes(Map.get(map, :attributes, %{})),
      dropped_attributes_count: count(map, :dropped_attributes_count)
    }
  end

  # Preserve status messages even when their code is unset or OK.
  defp status(%{code: code} = map),
    do: %{
      code: enum(@statuses, code, :status),
      message: TraceValue.string(Map.get(map, :message, ""))
    }

  # Scope fields are independent of the encoded Span byte limit.
  defp scope(map) when is_map(map) do
    if not TraceValue.bounded?(map, 1_048_576), do: throw(:invalid_trace_value)
    Map.new([:name, :version, :schema_url], &{&1, TraceValue.string(Map.get(map, &1, ""))})
  end
end
