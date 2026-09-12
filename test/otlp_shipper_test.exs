defmodule OtlpShipperTest do
  use ExUnit.Case, async: true
  doctest OtlpShipper

  test "greet/1 joins the words it is given" do
    assert OtlpShipper.greet(["hi", "there"]) == "hello hi there"
  end

  test "greet/1 defaults to the world" do
    assert OtlpShipper.greet([]) == "hello world"
  end

  test "greet/2 renders json" do
    assert OtlpShipper.greet(["you"], :json) == ~s({"greeting":"hello","subject":"you"})
  end
end
