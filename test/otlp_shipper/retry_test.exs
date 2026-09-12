defmodule OtlpShipper.RetryTest do
  use ExUnit.Case, async: true
  alias OtlpShipper.Retry
  doctest Retry

  test "jitter stays bounded and HTTP dates do not schedule in the past" do
    assert Retry.backoff(0, 100, 1000, 0.0) == 50
    assert Retry.backoff(0, 100, 1000, 1.0) == 150

    assert Retry.retry_after("Sat, 12 Sep 2026 11:00:00 GMT", ~U[2026-09-12 12:00:00Z]) ==
             {:ok, 0}

    for value <- [
          "-1",
          "2ms",
          "Sat, 99 Sep 2026 12:00:00 GMT",
          "Sat, 12 Xxx 2026 12:00:00 GMT",
          "Sat, 12 Sep 2026 99:00:00 GMT"
        ] do
      assert Retry.retry_after(value, ~U[2026-09-12 12:00:00Z]) == :error
    end
  end
end
