defmodule ReplacementCollector do
  @moduledoc false

  # One loopback listener handles instrumented application requests and all signals.
  def start_link do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    pid = spawn_link(fn -> loop(listener, []) end)
    {pid, listener, "http://127.0.0.1:#{port}"}
  end

  # Snapshot after provider shutdown includes every acknowledged export.
  def snapshot(pid) do
    ref = make_ref()
    send(pid, {:snapshot, self(), ref})

    receive do
      {^ref, requests} -> requests
    after
      5000 -> raise "collector snapshot timed out"
    end
  end

  # Closing the listener ends the accept loop without leaving a detached task.
  def stop(pid, listener) do
    monitor = Process.monitor(pid)
    :gen_tcp.close(listener)

    receive do
      {:DOWN, ^monitor, :process, ^pid, :normal} -> :ok
    after
      1000 -> raise "collector did not stop"
    end
  end

  # A short accept timeout makes snapshot requests responsive without polling sleeps.
  defp loop(listener, requests) do
    receive do
      {:snapshot, caller, ref} ->
        send(caller, {ref, Enum.reverse(requests)})
        loop(listener, requests)
    after
      0 ->
        case :gen_tcp.accept(listener, 50) do
          {:ok, socket} -> loop(listener, [read_request(socket) | requests])
          {:error, :timeout} -> loop(listener, requests)
          {:error, :closed} -> :ok
        end
    end
  end

  # Decode generated protobufs before acknowledging export success.
  defp read_request(socket) do
    {:ok, {:http_request, method, {:abs_path, path}, _}} = :gen_tcp.recv(socket, 0, 5000)
    length = content_length(socket, 0)
    :ok = :inet.setopts(socket, packet: :raw)
    body = if length == 0, do: "", else: read_body(socket, length)
    decoded = decode(method, path, body)

    :ok =
      :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")

    :gen_tcp.close(socket)
    {path, decoded}
  end

  # HTTP content length determines a bounded read for this trusted smoke producer.
  defp read_body(socket, length) when length <= 1_048_576 do
    {:ok, body} = :gen_tcp.recv(socket, length, 5000)
    body
  end

  # Header packet mode stops exactly at the body boundary.
  defp content_length(socket, length) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, :http_eoh} ->
        length

      {:ok, {:http_header, _, name, _, value}} ->
        next =
          if String.downcase(to_string(name)) == "content-length",
            do: String.to_integer(to_string(value)),
            else: length

        content_length(socket, next)
    end
  end

  # Unknown paths or unexpected methods fail the proof instead of being discarded.
  defp decode(:GET, "/ordinary", ""), do: :ordinary

  defp decode(:POST, "/v1/logs", body),
    do:
      :otlp_shipper_logs_service.decode_msg(
        body,
        :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest"
      )

  defp decode(:POST, "/v1/metrics", body),
    do:
      :otlp_shipper_metrics_service.decode_msg(
        body,
        :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest"
      )

  defp decode(:POST, "/v1/traces", body),
    do:
      :otlp_shipper_trace_service.decode_msg(
        body,
        :"opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest"
      )
end
