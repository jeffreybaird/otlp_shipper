defmodule OtlpShipper.LogRecord do
  @moduledoc """
  Converts Logger events to bounded OTLP records without performing I/O.

  Body and attribute value limits measure encoded AnyValue bytes. Collection
  traversal stops at the byte budget, 64 entries per container, or depth eight.
  Long strings are truncated at a UTF-8 boundary. Oversized attribute keys and
  attributes beyond `max_attributes` are omitted and counted; truncated values
  remain attributes and are not counted as dropped. Internal Logger metadata is
  intentionally excluded from the attribute set.
  """
  alias OtlpShipper.Value

  @internal [
    :pid,
    :gl,
    :time,
    :mfa,
    :file,
    :line,
    :domain,
    :report_cb,
    :otel_trace_id,
    :otel_span_id,
    :otel_trace_flags,
    :crash_reason,
    :erl_level
  ]
  @defaults [max_body_bytes: 16_384, max_attribute_bytes: 1024, max_attributes: 64]
  @levels %{
    debug: 5,
    info: 9,
    notice: 10,
    warning: 13,
    error: 17,
    critical: 18,
    alert: 19,
    emergency: 21
  }

  @doc """
  Validates record limits. Byte limits must be at least 32; count may be zero.

      iex> {:ok, limits} = OtlpShipper.LogRecord.limits(max_attributes: 2)
      iex> limits.max_attributes
      2
  """
  @spec limits(keyword()) :: {:ok, map()} | {:error, :invalid_log_limits}
  def limits(opts \\ []) do
    if Keyword.keyword?(opts) and Enum.all?(opts, &valid_limit?/1) do
      {:ok, Map.new(Keyword.merge(@defaults, opts))}
    else
      {:error, :invalid_log_limits}
    end
  end

  defp valid_limit?({key, value}) do
    key in Keyword.keys(@defaults) and is_integer(value) and
      value >= if(key == :max_attributes, do: 0, else: 32)
  end

  @doc """
  Maps Erlang Logger severity to OTLP severity; unknown levels are unspecified.

      iex> OtlpShipper.LogRecord.severity(:notice)
      10
  """
  @spec severity(atom()) :: non_neg_integer()
  def severity(level), do: Map.get(@levels, level, 0)

  @doc """
  Builds a record using explicit observation time (nanoseconds) and correlation.
  Correlation uses Logger's `otel_trace_id`, `otel_span_id`, and `otel_trace_flags`
  metadata keys. A complete valid metadata pair takes precedence over context.
  IDs accept fixed-width hex strings, raw bytes, or positive integers.
  Malformed events return a tagged error without exposing their contents.

      iex> event = %{level: :info, msg: {:string, "ready"}, meta: %{time: 1}}
      iex> {:ok, record} = OtlpShipper.LogRecord.new(event)
      iex> {record.severity_number, record.body, record.time_unix_nano}
      {9, %{value: {:string_value, "ready"}}, 1000}
  """
  @spec new(map(), map(), map(), non_neg_integer()) :: {:ok, map()} | {:error, :invalid_log_event}
  def new(event, limits \\ Map.new(@defaults), context \\ %{}, observed_time \\ 0)

  def new(%{level: level, msg: message, meta: meta}, limits, context, observed_time)
      when is_atom(level) and is_map(meta) do
    {attributes, dropped} = encode_attributes(Map.drop(meta, @internal), limits)
    {trace_id, span_id, flags} = correlation(meta, context)
    time = Map.get(meta, :time, 0)

    {:ok,
     %{
       time_unix_nano: if(is_integer(time) and time >= 0, do: time * 1000, else: 0),
       observed_time_unix_nano: observed_time,
       severity_number: severity(level),
       severity_text: Atom.to_string(level),
       body: encode_body(message, limits.max_body_bytes),
       attributes: attributes,
       dropped_attributes_count: dropped,
       trace_id: trace_id,
       span_id: span_id,
       flags: flags
     }}
  rescue
    _ -> {:error, :invalid_log_event}
  catch
    _, _ -> {:error, :invalid_log_event}
  end

  def new(_, _, _, _), do: {:error, :invalid_log_event}

  defp encode_attributes(meta, limits) do
    {values, dropped, _keys} =
      Enum.reduce(meta, {[], 0, MapSet.new()}, fn {key, value}, {attrs, dropped, keys} ->
        key = normalize_key(key)

        if length(attrs) >= limits.max_attributes or byte_size(key) > limits.max_attribute_bytes or
             MapSet.member?(keys, key) do
          {attrs, dropped + 1, keys}
        else
          attr = %{key: key, value: bounded_value(value, limits.max_attribute_bytes, 0)}
          {[attr | attrs], dropped, MapSet.put(keys, key)}
        end
      end)

    {Enum.sort_by(values, & &1.key), dropped}
  end

  defp encode_body({:report, report}, budget) when is_map(report),
    do: bounded_pairs(report, budget, 0)

  defp encode_body({:report, report}, budget) when is_list(report),
    do: bounded_pairs(report, budget, 0)

  defp encode_body({:string, text}, budget),
    do: text |> bounded_chardata(budget) |> bounded_value(budget, 0)

  defp encode_body({format, args}, budget) do
    format
    |> :io_lib.format(args, chars_limit: budget)
    |> bounded_chardata(budget)
    |> bounded_value(budget, 0)
  end

  defp bounded_value(_, budget, depth) when depth >= 8,
    do: bounded_string("[depth limit]", budget)

  defp bounded_value(value, budget, _) when is_binary(value), do: bounded_string(value, budget)

  defp bounded_value(value, budget, depth) when is_map(value),
    do: bounded_pairs(value, budget, depth)

  defp bounded_value(value, budget, depth) when is_list(value) do
    bounded_collection(value, :array_value, budget, fn item, remaining ->
      bounded_value(item, remaining, depth + 1)
    end)
  end

  defp bounded_value(value, budget, _) do
    value = Value.encode(value)
    if encoded_size(value) <= budget, do: value, else: bounded_string("[truncated]", budget)
  end

  defp bounded_pairs(pairs, budget, depth) when is_map(pairs),
    do: bounded_pairs(Map.to_list(pairs), budget, depth)

  defp bounded_pairs(pairs, budget, depth) do
    bounded_collection(pairs, :kvlist_value, budget, fn {key, value}, remaining ->
      key = key |> normalize_key() |> truncate_utf8(div(remaining, 4))
      %{key: key, value: bounded_value(value, remaining - byte_size(key) - 8, depth + 1)}
    end)
  end

  defp bounded_collection(items, type, budget, encode) do
    {values, _remaining} =
      items
      |> Stream.take(64)
      |> Enum.reduce_while({[], budget - 8}, fn item, acc ->
        collect_value(item, acc, type, budget, encode)
      end)

    %{value: {type, %{values: Enum.reverse(values)}}}
  end

  defp collect_value(_item, {values, remaining}, _type, _budget, _encode)
       when remaining < 32,
       do: {:halt, {values, remaining}}

  defp collect_value(item, {values, remaining}, type, budget, encode) do
    value = encode.(item, remaining - 8)
    candidate = %{value: {type, %{values: Enum.reverse([value | values])}}}
    size = encoded_size(candidate)

    cond do
      type == :kvlist_value and Enum.any?(values, &(&1.key == value.key)) ->
        {:cont, {values, remaining}}

      size <= budget ->
        {:cont, {[value | values], budget - size - 8}}

      true ->
        {:halt, {values, remaining}}
    end
  end

  defp bounded_string(value, budget) do
    # Copy prefixes so queued records cannot retain a huge source binary.
    prefix = binary_part(value, 0, min(byte_size(value), max(budget - 8, 0)))

    if String.valid?(value),
      do: %{value: {:string_value, prefix |> valid_prefix() |> :binary.copy()}},
      else: %{value: {:bytes_value, :binary.copy(prefix)}}
  end

  defp truncate_utf8(value, limit),
    do: value |> binary_part(0, min(byte_size(value), limit)) |> valid_prefix() |> :binary.copy()

  defp valid_prefix(<<>>), do: ""

  defp valid_prefix(value) do
    if String.valid?(value),
      do: value,
      else: valid_prefix(binary_part(value, 0, byte_size(value) - 1))
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)

  defp normalize_key(key) when is_binary(key) do
    if String.valid?(key), do: key, else: inspect(key, limit: 8, printable_limit: 128)
  end

  defp normalize_key(key), do: inspect(key, limit: 8, printable_limit: 128)

  defp bounded_chardata(text, budget) do
    case take_chardata([text], budget, budget * 2, []) do
      {:ok, chunks} -> chunks |> Enum.reverse() |> IO.iodata_to_binary()
      :error -> "[invalid chardata]"
    end
  end

  # Traverse only a bounded prefix, including empty/nested lists. Flattening a
  # complete charlist first would allocate an unbounded temporary binary.
  defp take_chardata(_, remaining, steps, chunks) when remaining <= 0 or steps <= 0,
    do: {:ok, chunks}

  defp take_chardata([], _, _, chunks), do: {:ok, chunks}

  defp take_chardata([[] | rest], remaining, steps, chunks),
    do: take_chardata(rest, remaining, steps - 1, chunks)

  defp take_chardata([[head | tail] | rest], remaining, steps, chunks),
    do: take_chardata([head, tail | rest], remaining, steps - 1, chunks)

  defp take_chardata([text | rest], remaining, steps, chunks) when is_binary(text) do
    size = min(byte_size(text), remaining)
    prefix = binary_part(text, 0, size)

    case :unicode.characters_to_binary(prefix) do
      binary when is_binary(binary) ->
        take_chardata(rest, remaining - size, steps - 1, [binary | chunks])

      {:incomplete, binary, _} when size < byte_size(text) ->
        {:ok, [binary | chunks]}

      _ ->
        :error
    end
  end

  defp take_chardata([char | rest], remaining, steps, chunks) when is_integer(char) do
    case :unicode.characters_to_binary([char]) do
      binary when is_binary(binary) and byte_size(binary) <= remaining ->
        take_chardata(rest, remaining - byte_size(binary), steps - 1, [binary | chunks])

      binary when is_binary(binary) ->
        {:ok, chunks}

      _ ->
        :error
    end
  end

  defp take_chardata(_, _, _, _), do: :error

  defp encoded_size(value) do
    value
    |> :otlp_shipper_logs_service.encode_msg(:"opentelemetry.proto.common.v1.AnyValue")
    |> byte_size()
  end

  defp correlation(meta, context) do
    case decode_ids(meta) do
      {"", "", _} -> decode_ids(context)
      ids -> ids
    end
  end

  defp decode_ids(meta) do
    trace = decode_id(Map.get(meta, :otel_trace_id), 16)
    span = decode_id(Map.get(meta, :otel_span_id), 8)

    if trace == "" or span == "",
      do: {"", "", 0},
      else: {trace, span, decode_flags(Map.get(meta, :otel_trace_flags))}
  end

  defp decode_id(id, size) when is_integer(id) and id > 0 do
    if id < Integer.pow(256, size), do: <<id::size(size)-unit(8)>>, else: ""
  end

  defp decode_id(id, size) when is_binary(id) and byte_size(id) == size do
    if id == :binary.copy(<<0>>, size), do: "", else: id
  end

  defp decode_id(id, size) when is_binary(id) and byte_size(id) == size * 2 do
    case Base.decode16(id, case: :mixed) do
      {:ok, raw} -> decode_id(raw, size)
      _ -> ""
    end
  end

  defp decode_id(_, _), do: ""
  defp decode_flags(value) when value in [1, "01"], do: 1
  defp decode_flags(_), do: 0
end
