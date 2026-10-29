defmodule Hippy do
  @moduledoc """
  IPP client API
  """

  @doc "Sends an operation to a printer. See `Hippy.Server.send_operation/2` for the options."
  defdelegate send_operation(op, opts \\ []), to: Hippy.Server
end
