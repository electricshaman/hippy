defmodule Hippy.Protocol.Binary do
  defmacro byte do
    quote do: signed - 8
  end
end
