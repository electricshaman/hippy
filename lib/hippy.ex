defmodule Hippy do
  @moduledoc """
  IPP client API
  """

  defdelegate send_operation(op), to: Hippy.Server
  defdelegate send_operation(op, endpoint), to: Hippy.Server
end
