defmodule Hippy.Protocol.PrinterWifiState do
  @moduledoc """
  Not sure what these values represent yet! :)
  """

  @behaviour Hippy.Protocol.Enum

  @impl Hippy.Protocol.Enum
  def decode(value), do: {:ok, value}
  def decode!(value), do: value
end
