defmodule OtlpShipper.TraceSDKFixtures do
  @moduledoc false
  require Record

  @span_fields Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  @span_indexes @span_fields |> Keyword.keys() |> Enum.with_index(1) |> Map.new()
  Record.defrecordp(:span, @span_fields)

  Record.defrecordp(
    :event,
    Record.extract(:event, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  Record.defrecordp(:link, Record.extract(:link, from_lib: "opentelemetry/include/otel_span.hrl"))

  Record.defrecordp(
    :scope,
    :instrumentation_scope,
    Record.extract(:instrumentation_scope,
      from_lib: "opentelemetry_api/include/opentelemetry.hrl"
    )
  )

  @doc false
  def record(overrides \\ []) do
    now = :opentelemetry.timestamp()

    record =
      span(
        trace_id: 1,
        span_id: 2,
        parent_span_id: :undefined,
        parent_span_is_remote: false,
        tracestate: :otel_tracestate.new([]),
        name: "sdk-span",
        kind: :internal,
        start_time: now,
        end_time: now + System.convert_time_unit(1, :millisecond, :native),
        attributes: :otel_attributes.new(%{"probe" => true}, 128, :infinity),
        events: :otel_events.new(128, 128, :infinity),
        links: :otel_links.new([], 128, 128, :infinity),
        status: {:status, :unset, ""},
        trace_flags: 1,
        is_recording: true,
        instrumentation_scope:
          scope(name: "sdk_scope", version: "1", schema_url: "https://sdk/scope")
      )

    Enum.reduce(overrides, record, fn {field, value}, result ->
      put_elem(result, Map.fetch!(@span_indexes, field), value)
    end)
  end

  @doc false
  def table(records) do
    table = :ets.new(:trace_sdk_fixture, [:duplicate_bag, :public, {:keypos, 2}])
    :ets.insert(table, records)
    table
  end

  @doc false
  def resource,
    do: :otel_resource.create(%{"service.name" => "sdk-authoritative"}, "https://sdk/resource")

  @doc false
  def event_identities(record) do
    record
    |> span(:events)
    |> :otel_events.list()
    |> Enum.reverse()
    |> Enum.map(
      &{event(&1, :name), :opentelemetry.timestamp_to_nano(event(&1, :system_time_native))}
    )
  end

  @doc false
  def link_identities(record) do
    record
    |> span(:links)
    |> :otel_links.list()
    |> Enum.reverse()
    |> Enum.map(&{<<link(&1, :trace_id)::128>>, <<link(&1, :span_id)::64>>})
  end
end
