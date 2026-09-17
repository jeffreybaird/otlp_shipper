defmodule OtlpShipper.TraceBatch do
  @moduledoc """
  Converts and exports bounded trace requests within one monotonic deadline.

  The caller supplies an enumerable and its known cardinality, for example the SDK
  ETS table size. Only a bounded chunk is materialized. A late cardinality mismatch
  returns `:invalid_batch`; it cannot undo requests already accepted. There is no
  second queue, and accepted chunks are never replayed after subsequent failure.

  The returned counters partition the declared count into accepted, rejected,
  invalid, failed, and unsent spans. In-flight requests interrupted by a deadline
  count as failed; remote acceptance is unknown. Transport owns diagnostics for
  submitted requests; this module reports only invalid and unsubmitted spans.
  Forced deadline cancellation may prevent final telemetry emission.
  """
  alias OtlpShipper.{Config, TraceEncoder, TraceRecord, Transport}

  @typedoc "Observed span outcomes and number of submitted logical requests."
  @type summary :: %{
          accepted: non_neg_integer(),
          rejected: non_neg_integer(),
          invalid: non_neg_integer(),
          failed: non_neg_integer(),
          unsent: non_neg_integer(),
          requests: non_neg_integer()
        }

  @doc """
  Exports an enumerable of normalized spans using a caller-owned Finch pool.

  `time_offset` uses native units and `total_count` must match the enumerable.
  Local invalid/oversized spans are counted and skipped. Transport errors stop
  further requests and return a specific reason with the current summary. Local
  validation drops and partial rejection are visible in a successful summary;
  callers must inspect it before mapping an SDK callback result.
  """
  @spec export(Config.t(), atom(), Enumerable.t(), map(), integer(), non_neg_integer()) ::
          {:ok, summary()} | {:error, term(), summary()}
  def export(%Config{signal: :traces} = config, pool, spans, resource, offset, total_count)
      when is_integer(total_count) and total_count >= 0 do
    deadline = System.monotonic_time(:millisecond) + config.timeout
    ledger = :ets.new(__MODULE__, [:set, :public])
    publish(ledger, summary(total_count))

    try do
      task =
        Task.async(fn ->
          run(config, pool, spans, resource, offset, total_count, deadline, ledger)
        end)

      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      case Task.yield(task, remaining) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        _ -> {:error, :timeout, snapshot(ledger)}
      end
    after
      :ets.delete(ledger)
    end
  end

  def export(_, _, _, _, _, count),
    do:
      {:error, :invalid_batch, summary(if(is_integer(count) and count >= 0, do: count, else: 0))}

  # The parent owns the table, so cancellation cannot destroy the last coherent tally.
  defp summary(count),
    do: %{accepted: 0, rejected: 0, invalid: 0, failed: 0, unsent: count, requests: 0}

  defp publish(ledger, counters), do: :ets.insert(ledger, {:summary, counters})
  defp snapshot(ledger), do: :ets.lookup_element(ledger, :summary, 2)

  # Every conversion, encode, request and synchronous diagnostic runs in this worker.
  defp run(config, pool, spans, resource, offset, count, deadline, ledger) do
    context = %{
      config: config,
      pool: pool,
      resource: resource,
      offset: offset,
      count: count,
      deadline: deadline,
      ledger: ledger
    }

    result =
      with {:ok, _} <- TraceEncoder.encode([], resource, config.max_batch_bytes) do
        initial = %{records: [], body: nil, seen: 0, error: nil}
        final = Enum.reduce_while(spans, initial, &consume(&1, &2, context))
        finish(final, context)
      end

    conclude(result, context)
  rescue
    _ -> conclude({:error, :invalid_batch}, %{ledger: ledger})
  catch
    _, _ -> conclude({:error, :invalid_batch}, %{ledger: ledger})
  end

  # Enforce cardinality before conversion so excess elements cannot be submitted.
  defp consume(input, state, context) do
    cond do
      expired?(context) -> {:halt, %{state | error: :timeout}}
      state.seen >= context.count -> {:halt, %{state | error: :invalid_batch}}
      true -> convert_next(input, %{state | seen: state.seen + 1}, context)
    end
  end

  # Conversion errors affect one span and never alter accepted earlier chunks.
  defp convert_next(input, state, context) do
    case TraceRecord.convert(input, context.offset, context.config.max_item_bytes) do
      {:ok, converted} -> add_record(converted, state, context)
      {:error, _} -> reject_local(state, context)
      {:error, _, _} -> reject_local(state, context)
    end
  end

  # Publish before telemetry, which may block until the parent's deadline fires.
  defp reject_local(state, context) do
    counters = snapshot(context.ledger)

    publish(context.ledger, %{
      counters
      | invalid: counters.invalid + 1,
        unsent: counters.unsent - 1
    })

    dropped(1, :invalid_span)
    {:cont, state}
  end

  # Generated request bytes account for resource/scope envelopes before chunking.
  defp add_record(converted, state, context) do
    records = state.records ++ [converted]

    case TraceEncoder.encode(records, context.resource, context.config.max_batch_bytes) do
      {:ok, body} -> maybe_submit(%{state | records: records, body: body}, context)
      {:error, :batch_too_large} -> split_chunk(converted, state, context)
      {:error, reason} -> {:halt, %{state | error: reason}}
    end
  end

  # An indivisible span with its envelope is dropped, never split or truncated.
  defp split_chunk(_converted, %{records: []} = state, context), do: reject_local(state, context)

  defp split_chunk(converted, state, context) do
    case submit(state, context) do
      %{error: nil} = empty -> add_record(converted, empty, context)
      failed -> {:halt, failed}
    end
  end

  # Flush full chunks immediately, before asking a potentially blocking source for more.
  defp maybe_submit(state, context) do
    if length(state.records) >= context.config.max_batch do
      case submit(state, context) do
        %{error: nil} = empty -> {:cont, empty}
        failed -> {:halt, failed}
      end
    else
      {:cont, state}
    end
  end

  # Move the entire in-flight chunk out of unsent in one atomic ETS replacement.
  defp submit(state, context) do
    if expired?(context) do
      %{state | error: :timeout}
    else
      count = length(state.records)
      counters = snapshot(context.ledger)

      submitted = %{
        counters
        | unsent: counters.unsent - count,
          failed: counters.failed + count,
          requests: counters.requests + 1
      }

      publish(context.ledger, submitted)
      observer = fn result -> publish(context.ledger, outcome(submitted, result, count)) end

      result =
        Transport.export_until(
          context.config,
          context.pool,
          state.body,
          count,
          context.deadline,
          observer
        )

      %{state | records: [], body: nil, error: reason(result)}
    end
  end

  # Terminal results are committed before transport emits synchronous telemetry.
  defp outcome(counters, :ok, count),
    do: %{counters | accepted: counters.accepted + count, failed: counters.failed - count}

  defp outcome(counters, {:ok, :partial, rejected}, count),
    do: %{
      counters
      | accepted: counters.accepted + count - rejected,
        rejected: counters.rejected + rejected,
        failed: counters.failed - count
    }

  defp outcome(counters, _, _), do: counters

  # Preserve transport error detail without nesting another error tuple.
  defp reason(:ok), do: nil
  defp reason({:ok, :partial, _}), do: nil
  defp reason({:error, tag}), do: tag
  defp reason({:error, tag, detail}), do: {tag, detail}

  # A cardinality failure retains successful prior requests but submits no new suffix.
  defp finish(%{error: reason}, _) when not is_nil(reason), do: {:error, reason}

  defp finish(%{seen: seen}, %{count: expected}) when seen != expected,
    do: {:error, :invalid_batch}

  defp finish(%{records: []}, _), do: :ok

  defp finish(state, context) do
    case submit(state, context) do
      %{error: nil} -> :ok
      %{error: reason} -> {:error, reason}
    end
  end

  # Only the never-submitted suffix is reported here; transport owns its own losses.
  defp conclude(result, context) do
    counters = snapshot(context.ledger)
    dropped(counters.unsent, :unsent)

    case result do
      :ok -> {:ok, counters}
      {:error, reason} -> {:error, reason, counters}
    end
  end

  # Keep diagnostics free of input payloads and collector details.
  defp dropped(0, _), do: :ok

  defp dropped(count, reason),
    do:
      :telemetry.execute([:otlp_shipper, :dropped], %{count: count}, %{
        signal: :traces,
        reason: reason
      })

  defp expired?(context), do: System.monotonic_time(:millisecond) >= context.deadline
end
