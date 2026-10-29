defmodule Hippy.Protocol.Binary do
  @moduledoc false

  @deprecated "Hippy.Protocol.Binary is unused and will be removed"
  defmacro byte do
    quote do: signed - 8
  end
end
