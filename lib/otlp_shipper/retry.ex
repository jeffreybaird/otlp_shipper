defmodule OtlpShipper.Retry do
  @moduledoc "Pure retry timing helpers. Delays and timestamps use milliseconds."

  @doc """
  Calculates capped exponential backoff with caller-supplied jitter in `[0, 1]`.

      iex> OtlpShipper.Retry.backoff(2, 100, 1000, 0.5)
      400
      iex> OtlpShipper.Retry.backoff(20, 100, 1000, 1.0)
      1000
  """
  @spec backoff(non_neg_integer(), pos_integer(), pos_integer(), float()) :: non_neg_integer()
  def backoff(attempt, base, maximum, jitter)
      when attempt >= 0 and base > 0 and maximum > 0 and jitter >= 0 and jitter <= 1 do
    min(round(base * 2 ** min(attempt, 30) * (0.5 + jitter)), maximum)
  end

  @doc """
  Parses Retry-After seconds or an IMF-fixdate relative to an explicit clock.

      iex> OtlpShipper.Retry.retry_after("2", ~U[2026-09-12 12:00:00Z])
      {:ok, 2000}
      iex> OtlpShipper.Retry.retry_after("Sat, 12 Sep 2026 12:00:03 GMT", ~U[2026-09-12 12:00:00Z])
      {:ok, 3000}
      iex> OtlpShipper.Retry.retry_after("invalid", ~U[2026-09-12 12:00:00Z])
      :error
  """
  @spec retry_after(String.t(), DateTime.t()) :: {:ok, non_neg_integer()} | :error
  def retry_after(value, now) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 -> {:ok, seconds * 1000}
      _ -> parse_date(value, now)
    end
  end

  defp parse_date(value, now) do
    case Regex.run(
           ~r/^[A-Z][a-z]{2}, (\d{2}) ([A-Z][a-z]{2}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$/,
           value
         ) do
      [_, day, month, year, hour, minute, second] ->
        month_number =
          Enum.find_index(~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec), &(&1 == month))

        with true <- is_integer(month_number),
             {:ok, date} <-
               Date.new(String.to_integer(year), month_number + 1, String.to_integer(day)),
             {:ok, time} <-
               Time.new(
                 String.to_integer(hour),
                 String.to_integer(minute),
                 String.to_integer(second)
               ),
             {:ok, datetime} <- DateTime.new(date, time, "Etc/UTC") do
          {:ok, max(DateTime.diff(datetime, now, :millisecond), 0)}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end
end
