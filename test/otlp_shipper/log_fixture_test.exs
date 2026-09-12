defmodule OtlpShipper.LogFixtureTest do
  use ExUnit.Case, async: true
  alias OtlpShipper.{Encoder, LogRecord}

  test "new records preserve the recorded recipe's body, metadata, severity and IDs" do
    fixture = File.read!(Path.expand("../fixtures/otlp/elixir_fallback_logs.bin", __DIR__))
    expected = fixture |> decode() |> records()
    assert length(expected) == 6

    events = [
      {:info, {:string, "request finished"},
       %{status: 200, request_id: "F0oR8", duration_ms: 12.5}},
      {:warning, {:string, "buffer overloaded"}, %{pending: 20_000, table: "spans"}},
      {:debug, {:string, "checking mux asset"}, %{asset_id: "abc123", org_id: 42}},
      {:error, {:string, "webhook delivery failed"},
       %{endpoint: "https://example.com/hook", attempt: 3}},
      {:info, {:report, %{ok: true, msg: "structured body", n: 1}}, %{}},
      {:info, {:string, "unicode ünïcödé ✓"}, %{}}
    ]

    {:ok, limits} = LogRecord.limits()

    actual =
      Enum.zip_with(events, expected, fn {level, msg, meta}, recorded ->
        meta =
          Map.merge(meta, %{
            time: div(recorded.time_unix_nano, 1000),
            otel_trace_id: recorded.trace_id,
            otel_span_id: recorded.span_id
          })

        {:ok, record} =
          LogRecord.new(
            %{level: level, msg: msg, meta: meta},
            limits,
            %{},
            recorded.observed_time_unix_nano
          )

        record
      end)

    {:ok, wire} = Encoder.encode(:logs, actual, %{attributes: []})
    # Attribute ordering is not semantically significant. Scope now identifies
    # this package; the record-level contract remains compatible with the recipe.
    assert Enum.map(records(decode(wire)), &canonical_record/1) ==
             Enum.map(expected, &canonical_record/1)
  end

  defp canonical_record(record) do
    record
    |> Map.update!(:attributes, &Enum.sort_by(&1, fn attr -> attr.key end))
    |> Map.update!(:body, fn
      %{value: {:kvlist_value, %{values: values}}} ->
        %{value: {:kvlist_value, %{values: Enum.sort_by(values, & &1.key)}}}

      value ->
        value
    end)
  end

  defp decode(body),
    do:
      :otlp_shipper_logs_service.decode_msg(
        body,
        :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest"
      )

  defp records(message), do: hd(hd(message.resource_logs).scope_logs).log_records
end
