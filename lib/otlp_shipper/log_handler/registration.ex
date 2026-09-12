defmodule OtlpShipper.LogHandler.Registration do
  @moduledoc false
  use GenServer
  alias OtlpShipper.{Buffer, LogHandler}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    id = Keyword.fetch!(opts, :handler_id)
    token = Keyword.fetch!(opts, :token)
    # A killed registration process cannot run terminate. Only replace the
    # previous incarnation belonging to this supervision tree, never a host handler.
    remove_owned_handler(id, token)

    config = %{
      level: Keyword.fetch!(opts, :level),
      config: %{
        handle: Buffer.handle(Keyword.fetch!(opts, :buffer)),
        limits: Keyword.fetch!(opts, :limits),
        token: token
      }
    }

    case :logger.add_handler(id, LogHandler, config) do
      :ok -> {:ok, %{id: id, token: token}}
      {:error, reason} -> {:stop, {:handler_registration_failed, reason}}
    end
  end

  @impl true
  def terminate(_, state), do: remove_owned_handler(state.id, state.token)

  defp remove_owned_handler(id, token) do
    case :logger.get_handler_config(id) do
      {:ok, %{module: LogHandler, config: %{token: ^token}}} -> :logger.remove_handler(id)
      _ -> :ok
    end
  end
end
