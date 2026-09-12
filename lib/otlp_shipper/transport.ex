defmodule OtlpShipper.Transport do
  @moduledoc """
  Bounded OTLP/HTTP export over a caller-owned Finch pool.

  `export/4` waits for one logical export; call it from a supervised batch worker,
  never from Logger or a telemetry event callback. Its total deadline covers pool
  checkout, connection, response, and retry waits. Redirects are not followed.

  Returns `:ok`, `{:ok, :partial, rejected_count}`, or a tagged error. A response
  lost after acceptance can lead to duplicates. Partial acceptance is never retried.
  Response bodies are bounded and never included in diagnostics or error details.
  """
  alias OtlpShipper.{Config, Retry}

  @type result ::
          :ok | {:ok, :partial, non_neg_integer()} | {:error, atom()} | {:error, atom(), term()}
  @retry_statuses [429, 502, 503, 504]

  @doc "Exports an encoded request, recording one outcome and any rejected/dropped records."
  @spec export(Config.t(), atom(), binary(), non_neg_integer()) :: result()
  def export(%Config{} = config, finch, body, count)
      when is_binary(body) and is_integer(count) and count >= 0 do
    started = System.monotonic_time(:millisecond)

    result =
      if byte_size(body) > config.max_batch_bytes do
        {:error, :batch_too_large}
      else
        task = Task.async(fn -> safely_export(config, finch, body, started + config.timeout) end)

        case Task.yield(task, config.timeout) || Task.shutdown(task, :brutal_kill) do
          {:ok, result} -> result
          _ -> {:error, :timeout}
        end
      end

    record_outcome(
      config.signal,
      count,
      byte_size(body),
      System.monotonic_time(:millisecond) - started,
      result
    )

    result
  end

  defp safely_export(config, finch, body, deadline) do
    {body, compression_headers} =
      case config.compression do
        :gzip -> {:zlib.gzip(body), [{"content-encoding", "gzip"}]}
        :none -> {body, []}
      end

    headers = [{"content-type", "application/x-protobuf"} | compression_headers] ++ config.headers
    request = Finch.build(:post, config.endpoint, headers, body)
    attempt(request, config, finch, deadline, 0)
  rescue
    _ -> {:error, :transport, :request_failed}
  catch
    :exit, _ -> {:error, :transport, :unavailable}
    _, _ -> {:error, :request_failed}
  end

  defp attempt(request, config, finch, deadline, number) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      response = request(request, config, finch, remaining)

      case classify(response, config.signal) do
        {:retry, _error, headers} when number < config.max_retries ->
          delay = retry_delay(headers, number, config)

          if delay < deadline - System.monotonic_time(:millisecond) do
            Process.sleep(delay)
            attempt(request, config, finch, deadline, number + 1)
          else
            {:error, :timeout}
          end

        {:retry, error, _} ->
          error

        result ->
          result
      end
    end
  end

  defp request(request, config, finch, remaining) do
    initial = %{status: nil, headers: [], body: [], bytes: 0, oversized: false}

    callback = fn
      {:status, status}, acc ->
        {:cont, %{acc | status: status}}

      {:headers, headers}, acc ->
        {:cont, %{acc | headers: acc.headers ++ headers}}

      {:trailers, _headers}, acc ->
        {:cont, acc}

      {:data, data}, acc ->
        size = acc.bytes + byte_size(data)

        if size > config.max_response_bytes,
          do: {:halt, %{acc | oversized: true, body: []}},
          else: {:cont, %{acc | body: [data | acc.body], bytes: size}}
    end

    Finch.stream_while(request, finch, initial, callback,
      pool_timeout: remaining,
      receive_timeout: remaining,
      request_timeout: remaining
    )
  end

  defp classify({:ok, %{oversized: true}}, _signal), do: {:error, :response_too_large}

  defp classify({:ok, %{status: 200, body: chunks}}, signal) do
    chunks |> Enum.reverse() |> IO.iodata_to_binary() |> decode_response(signal)
  end

  defp classify({:ok, %{status: status, headers: headers}}, _) when status in @retry_statuses,
    do: {:retry, {:error, :http_status, status}, headers}

  defp classify({:ok, %{status: status}}, _), do: {:error, :http_status, status}

  defp classify({:error, error, _acc}, _),
    do: {:retry, {:error, :transport, transport_reason(error)}, []}

  defp transport_reason(%{reason: reason})
       when reason in [:timeout, :closed, :econnrefused, :nxdomain, :enetunreach], do: reason

  defp transport_reason(_), do: :request_failed

  defp decode_response(body, signal) do
    {module, type, rejected_key} =
      case signal do
        :logs ->
          {:otlp_shipper_logs_service,
           :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceResponse",
           :rejected_log_records}

        :metrics ->
          {:otlp_shipper_metrics_service,
           :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceResponse",
           :rejected_data_points}
      end

    case module.decode_msg(body, type) do
      %{partial_success: partial} ->
        rejected = Map.get(partial, rejected_key, 0)
        if rejected >= 0, do: {:ok, :partial, rejected}, else: {:error, :invalid_response}

      _ ->
        :ok
    end
  rescue
    _ -> {:error, :invalid_response}
  end

  defp retry_delay(headers, number, config) do
    header =
      Enum.find_value(headers, fn {key, value} ->
        if String.downcase(key) == "retry-after", do: value
      end)

    case header && Retry.retry_after(header, DateTime.utc_now()) do
      {:ok, delay} -> delay
      _ -> Retry.backoff(number, config.retry_base_ms, config.retry_max_ms, :rand.uniform())
    end
  end

  defp record_outcome(signal, count, bytes, duration, result) do
    {status, dropped} =
      case result do
        :ok -> {:ok, 0}
        {:ok, :partial, rejected} -> {:partial, min(rejected, count)}
        _ -> {:error, count}
      end

    metadata = %{signal: signal, status: status}

    :telemetry.execute(
      [:otlp_shipper, :export, :stop],
      %{count: count, duration: duration, byte_size: bytes},
      metadata
    )

    if status == :error do
      :telemetry.execute(
        [:otlp_shipper, :export, :exception],
        %{count: count},
        Map.put(metadata, :reason, error_tag(result))
      )
    end

    if dropped > 0 do
      :telemetry.execute([:otlp_shipper, :dropped], %{count: dropped}, %{
        signal: signal,
        reason: :export_failed
      })
    end
  end

  defp error_tag({:error, reason}), do: reason
  defp error_tag({:error, reason, _}), do: reason
end
