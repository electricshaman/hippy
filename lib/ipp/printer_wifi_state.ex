defmodule Hippy.IPP.PrinterWifiState do
  @moduledoc """
  Not sure what these values represent yet! :)
  """

  @behaviour Hippy.IPP.Enum

  @impl Hippy.IPP.Enum
  def decode(value), do: {:ok, value}
  def decode!(value), do: value
end
