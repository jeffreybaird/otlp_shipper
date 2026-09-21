if Code.ensure_loaded?(:otel_exporter_traces) do
  defmodule OtlpShipper.TraceSDKRecord do
    @moduledoc false
    alias OtlpShipper.TraceValue
    require Record

    Record.defrecordp(
      :sdk_span,
      :span,
      Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
    )

    Record.defrecordp(
      :sdk_event,
      :event,
      Record.extract(:event, from_lib: "opentelemetry/include/otel_span.hrl")
    )

    Record.defrecordp(
      :sdk_link,
      :link,
      Record.extract(:link, from_lib: "opentelemetry/include/otel_span.hrl")
    )

    Record.defrecordp(
      :sdk_scope,
      :instrumentation_scope,
      Record.extract(:instrumentation_scope,
        from_lib: "opentelemetry_api/include/opentelemetry.hrl"
      )
    )

    Record.defrecordp(
      :sdk_status,
      :status,
      Record.extract(:status, from_lib: "opentelemetry_api/include/opentelemetry.hrl")
    )

    @doc false
    @spec normalize(tuple(), pos_integer()) :: map()
    # Reject oversized retained values before mapping SDK event/link collections.
    def normalize(record, max_bytes) do
      if bounded_record?(record, max_bytes), do: span(record), else: %{}
    rescue
      _ -> %{}
    catch
      _, _ -> %{}
    end

    @doc false
    @spec resource(term(), pos_integer()) :: map() | nil
    # Check the raw resource before converting a possible character-list schema URL.
    def resource(record, max_bytes) do
      if TraceValue.bounded?(record, max_bytes * 4), do: resource_fields(record), else: nil
    end

    # Accessors return undefined for invalid resources; never substitute defaults.
    defp resource_fields(record) do
      attributes = :otel_resource.attributes(record)

      %{
        attributes: :otel_attributes.map(attributes),
        dropped_attributes_count: :otel_attributes.dropped(attributes),
        schema_url: text(:otel_resource.schema_url(record))
      }
    rescue
      _ -> nil
    end

    # Scope belongs to the request envelope, not the individual Span byte budget.
    defp bounded_record?(sdk_span() = record, max_bytes) do
      scope = sdk_span(record, :instrumentation_scope)
      payload = sdk_span(record, instrumentation_scope: :undefined)
      TraceValue.bounded?(payload, max_bytes * 4) and TraceValue.bounded?(scope, 4_194_304)
    end

    # Copy only normalized scalar metadata and bounded event/link collections.
    defp span(sdk_span() = record) do
      attributes = sdk_span(record, :attributes)
      events = sdk_span(record, :events)
      links = sdk_span(record, :links)

      %{
        trace_id: sdk_span(record, :trace_id),
        span_id: sdk_span(record, :span_id),
        parent_span_id: optional(sdk_span(record, :parent_span_id)),
        parent_span_is_remote: optional(sdk_span(record, :parent_span_is_remote)),
        trace_flags: sdk_span(record, :trace_flags),
        tracestate: tracestate(sdk_span(record, :tracestate)),
        name: text(sdk_span(record, :name)),
        kind: sdk_span(record, :kind),
        start_time: sdk_span(record, :start_time),
        end_time: sdk_span(record, :end_time),
        attributes: :otel_attributes.map(attributes),
        dropped_attributes_count: :otel_attributes.dropped(attributes),
        events: events |> :otel_events.list() |> Enum.reverse() |> Enum.map(&event/1),
        dropped_events_count: :otel_events.dropped(events),
        links: links |> :otel_links.list() |> Enum.reverse() |> Enum.map(&link/1),
        dropped_links_count: :otel_links.dropped(links),
        status: status(sdk_span(record, :status)),
        scope: scope(sdk_span(record, :instrumentation_scope))
      }
    end

    # SDK 1.7 stores events newest-first; the caller reverses before mapping.
    defp event(sdk_event(name: name, system_time_native: time, attributes: attributes)) do
      %{
        name: text(name),
        time: time,
        attributes: :otel_attributes.map(attributes),
        dropped_attributes_count: :otel_attributes.dropped(attributes)
      }
    end

    # Links expose no remote-context or flags metadata in this SDK version.
    defp link(
           sdk_link(
             trace_id: trace_id,
             span_id: span_id,
             tracestate: state,
             attributes: attributes
           )
         ) do
      %{
        trace_id: trace_id,
        span_id: span_id,
        tracestate: tracestate(state),
        attributes: :otel_attributes.map(attributes),
        dropped_attributes_count: :otel_attributes.dropped(attributes)
      }
    end

    # Missing SDK status means the standard unset status.
    defp status(:undefined), do: %{code: :unset, message: ""}

    defp status(sdk_status(code: code, message: message)),
      do: %{code: code, message: text(message)}

    # Missing scope fields are empty identities, never the shipper's own identity.
    defp scope(:undefined), do: %{name: "", version: "", schema_url: ""}

    defp scope(sdk_scope(name: name, version: version, schema_url: schema)),
      do: %{name: text(name), version: text(version), schema_url: text(schema)}

    # The pinned API exposes its ordered members through this stable record layout.
    defp tracestate({:tracestate, members}), do: tracestate(members)

    defp tracestate(members) when is_list(members),
      do: Enum.map(members, fn {key, value} -> {text(key), text(value)} end)

    # SDK identifiers distinguish undefined parent/context fields from valid values.
    defp optional(:undefined), do: nil
    defp optional(value), do: value

    # SDK names may be atoms; schema URLs may be Unicode character lists.
    defp text(:undefined), do: ""
    defp text(value) when is_atom(value), do: Atom.to_string(value)
    defp text(value) when is_binary(value), do: value
    defp text(value) when is_list(value), do: List.to_string(value)
  end
end
