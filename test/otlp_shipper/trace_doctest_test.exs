defmodule OtlpShipper.TraceDoctestTest do
  @moduledoc false
  use ExUnit.Case, async: true

  doctest OtlpShipper.TraceRecord
  doctest OtlpShipper.TraceEncoder
end
