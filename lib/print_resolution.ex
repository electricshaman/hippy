defmodule Hippy.PrintResolution do
  @moduledoc """
  Defines a two-dimensional resolution in the indicated unit.
  """
  alias __MODULE__

  defstruct [:xfeed, :feed, :unit]

  @type t :: %PrintResolution{xfeed: integer, feed: integer, unit: atom}
  @type t(xfeed, feed, unit) :: %PrintResolution{xfeed: xfeed, feed: feed, unit: unit}

  @spec new(integer, integer, atom) :: t
  def new(xfeed, feed, unit) do
    %PrintResolution{xfeed: xfeed, feed: feed, unit: unit}
  end
end

defimpl Inspect, for: Hippy.PrintResolution do
  import Inspect.Algebra

  def inspect(res, opts) do
    concat([to_doc(res.xfeed, opts), "x", to_doc(res.feed, opts), to_doc(res.unit, opts)])
  end
end
