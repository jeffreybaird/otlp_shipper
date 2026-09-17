defmodule OtlpShipper.TraceRecordEvidence do
  @moduledoc false
  require Record

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  Record.defrecordp(
    :event,
    Record.extract(:event, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  Record.defrecordp(:link, Record.extract(:link, from_lib: "opentelemetry/include/otel_span.hrl"))

  Record.defrecordp(
    :span_ctx,
    Record.extract(:span_ctx, from_lib: "opentelemetry_api/include/opentelemetry.hrl")
  )

  Record.defrecordp(
    :scope,
    :instrumentation_scope,
    Record.extract(:instrumentation_scope,
      from_lib: "opentelemetry_api/include/opentelemetry.hrl"
    )
  )

  @doc false
  # Create a child of a remote span and exceed each observed SDK collection limit.
  def emit(tracer) do
    limits = %{
      configured_attribute_limit: :otel_span_limits.attribute_count_limit(),
      configured_event_limit: :otel_span_limits.event_count_limit(),
      configured_link_limit: :otel_span_limits.link_count_limit()
    }

    remote = :otel_tracer.from_remote_span(1, 2, 1)
    remote = span_ctx(remote, tracestate: :otel_tracestate.new([{"vendor", "value"}]))
    context = :otel_tracer.set_current_span(:otel_ctx.new(), remote)
    link_attributes = attributes(:otel_span_limits.attribute_per_link_limit() + 1)
    links = for id <- 1..(limits.configured_link_limit + 1), do: {3, id, link_attributes, []}

    started =
      :otel_tracer.start_span(context, tracer, "fidelity", %{
        kind: :client,
        attributes: attributes(limits.configured_attribute_limit + 1),
        links: links
      })

    event_attributes = attributes(:otel_span_limits.attribute_per_event_limit() + 1)

    Enum.each(1..(limits.configured_event_limit + 1), fn _ ->
      :otel_span.add_event(started, "probe-event", event_attributes)
    end)

    :otel_span.set_status(started, :error, "probe failure")
    :otel_span.end_span(started)
    limits
  end

  @doc false
  # Decode only the probed SDK records; this is evidence, not a production codec.
  def describe(record, resource, limits) do
    fields = Map.new(span(record))
    # API 1.5.0 exposes no members accessor; pin its observed private record shape.
    {:tracestate, members} = fields.tracestate
    scope = fields.instrumentation_scope
    events = :otel_events.list(fields.events)
    links = :otel_links.list(fields.links)
    first_event = hd(events)
    first_link = hd(links)

    limits
    |> Map.merge(
      Map.take(fields, [
        :trace_id,
        :span_id,
        :parent_span_id,
        :parent_span_is_remote,
        :name,
        :kind,
        :trace_flags,
        :status
      ])
    )
    |> Map.merge(%{
      tracestate: members,
      resource_attributes: resource_attributes(resource),
      resource_schema_url: :otel_resource.schema_url(resource),
      scope_name: scope(scope, :name),
      scope_version: scope(scope, :version),
      scope_schema_url: scope(scope, :schema_url),
      start_unix_nano: :opentelemetry.timestamp_to_nano(fields.start_time),
      end_unix_nano: :opentelemetry.timestamp_to_nano(fields.end_time),
      event_unix_nano: :opentelemetry.timestamp_to_nano(event(first_event, :system_time_native)),
      attribute_count: fields.attributes |> :otel_attributes.map() |> map_size(),
      dropped_attributes: :otel_attributes.dropped(fields.attributes),
      event_count: length(events),
      dropped_events: :otel_events.dropped(fields.events),
      link_count: length(links),
      dropped_links: :otel_links.dropped(fields.links),
      dropped_event_attributes: :otel_attributes.dropped(event(first_event, :attributes)),
      dropped_link_attributes: :otel_attributes.dropped(link(first_link, :attributes))
    })
  end

  # Normalize SDK atom/binary attribute keys to the OTLP string-key representation.
  defp resource_attributes(resource) do
    resource
    |> :otel_resource.attributes()
    |> :otel_attributes.map()
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  # Generate distinct valid keys so SDK loss counters reflect capacity alone.
  defp attributes(count), do: Map.new(1..count, &{"attribute-#{&1}", &1})
end
