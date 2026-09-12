defmodule OtlpShipper.TestCollector do
  @moduledoc false
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/v1/:signal" do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    body =
      if get_req_header(conn, "content-encoding") == ["gzip"], do: :zlib.gunzip(body), else: body

    {module, type} = request_type(signal)
    decoded = module.decode_msg(body, type)
    owner = conn.private.owner
    send(owner, {:export, self(), signal, conn.req_headers, decoded, body})

    receive do
      {:respond, status, headers, response} ->
        conn =
          Enum.reduce(headers, conn, fn {key, value}, acc -> put_resp_header(acc, key, value) end)

        send_resp(conn, status, response)
    after
      2_000 -> send_resp(conn, 500, "test did not supply a response")
    end
  end

  match _ do
    send_resp(conn, 404, "unknown path")
  end

  defp request_type("logs"),
    do:
      {:otlp_shipper_logs_service,
       :"opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest"}

  defp request_type("metrics"),
    do:
      {:otlp_shipper_metrics_service,
       :"opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest"}
end

defmodule OtlpShipper.CollectorCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  setup do
    owner = self()

    plug = fn conn, _ ->
      conn
      |> Plug.Conn.put_private(:owner, owner)
      |> OtlpShipper.TestCollector.call(OtlpShipper.TestCollector.init([]))
    end

    server =
      start_supervised!({Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0, startup_log: false})

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    finch = Module.concat(__MODULE__, "Pool#{System.unique_integer([:positive])}")
    start_supervised!({Finch, name: finch})
    %{endpoint: "http://127.0.0.1:#{port}", finch: finch}
  end
end
