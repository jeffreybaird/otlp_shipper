defmodule OtlpShipper.Metrics.Registration do
  @moduledoc false
  use GenServer
  alias OtlpShipper.Metrics.Definition
  @guard_key {__MODULE__, :handling}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    [{:ingress, ingress}] = :ets.lookup(opts[:handles], :ingress)
    groups = Enum.group_by(opts[:definitions], & &1.metric.event_name)

    ids =
      Enum.map(groups, fn {event, definitions} ->
        id = {__MODULE__, opts[:token], event}
        :telemetry.detach(id)
        :ok = :telemetry.attach(id, event, &__MODULE__.handle_event/4, {definitions, ingress})
        id
      end)

    {:ok, ids}
  end

  @impl true
  def terminate(_, ids) do
    Enum.each(ids, &:telemetry.detach/1)
    :ok
  end

  @doc false
  def handle_event(event, measurements, metadata, {definitions, ingress}) do
    unless Process.get(@guard_key, false) or internal_event?(event, metadata, ingress) do
      Process.put(@guard_key, true)

      try do
        Enum.each(definitions, fn definition ->
          case Definition.sample(definition, measurements, metadata, ingress.max_tag_bytes) do
            {:ok, attributes, value} -> enqueue(ingress, definition.name, attributes, value)
            :skip -> :ok
            {:error, reason} -> dropped(reason)
          end
        end)
      after
        Process.delete(@guard_key)
      end
    end

    :ok
  end

  defp enqueue(ingress, name, attributes, value) do
    cond do
      not Process.alive?(ingress.owner) or :atomics.get(ingress.credits, 2) == 1 ->
        dropped(:unavailable)

      :atomics.add_get(ingress.credits, 1, 1) > ingress.max_pending ->
        :atomics.sub(ingress.credits, 1, 1)
        dropped(:queue_full)

      true ->
        send(ingress.owner, {:sample, name, attributes, value, System.os_time(:nanosecond)})
    end
  end

  defp internal_event?(event, metadata, ingress) do
    process_meta =
      case :logger.get_process_metadata() do
        :undefined -> %{}
        meta -> meta
      end

    domain?(Map.get(process_meta, :domain, [])) or
      (match?([:finch | _], event) and Map.get(metadata, :name) == ingress.finch_name)
  end

  defp domain?([:otlp_shipper | _]), do: true
  defp domain?([_ | rest]), do: domain?(rest)
  defp domain?(_), do: false

  defp dropped(reason),
    do:
      :telemetry.execute([:otlp_shipper, :dropped], %{count: 1}, %{
        signal: :metrics,
        reason: reason
      })
end
