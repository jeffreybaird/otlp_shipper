defmodule OtlpShipper.LogHandler.Pool do
  @moduledoc false

  # A brutally killed Finch supervisor may leave its named descendants shutting
  # down when our supervisor tries to restart it. Allow that teardown to finish
  # instead of exhausting the supervisor restart intensity in a tight loop.
  # Initial startup never retries, so another instance's name collision is an error.
  def start_link(name, started) do
    deadline = System.monotonic_time(:millisecond) + 1000
    start_pool(name, started, deadline)
  end

  defp start_pool(name, started, deadline) do
    case Finch.start_link(name: name) do
      {:ok, pid} ->
        :atomics.put(started, 1, 1)
        {:ok, pid}

      {:error, _} = error ->
        if :atomics.get(started, 1) == 1 and System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          start_pool(name, started, deadline)
        else
          error
        end
    end
  end
end
