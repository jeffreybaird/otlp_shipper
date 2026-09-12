defmodule OtlpShipper do
  @moduledoc """
  OtlpShipper — replace this with what the lib actually does.

  Keep the work in here, in plain functions. What makes a library usable from a
  command line is that none of it knows there is one.
  """

  @typedoc "Output shapes `greet/2` knows how to render."
  @type format :: :text | :json

  @formats [:text, :json]

  @doc "The formats `greet/2` accepts, in the order a usage message should list them."
  @spec formats() :: [format()]
  def formats, do: @formats

  @doc """
  An example of the shape: takes what it needs, returns a string.

      iex> OtlpShipper.greet(["world"])
      "hello world"

      iex> OtlpShipper.greet(["you"], :json)
      ~s({"greeting":"hello","subject":"you"})

  """
  @spec greet([String.t()], format()) :: String.t()
  def greet(words, format \\ :text)

  def greet([], format), do: greet(["world"], format)

  def greet(words, :text), do: "hello #{Enum.join(words, " ")}"

  def greet(words, :json),
    do: ~s({"greeting":"hello","subject":"#{Enum.join(words, " ")}"})
end
