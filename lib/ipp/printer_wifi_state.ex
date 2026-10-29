defmodule Hippy.IPP.PrinterWifiState do
  @moduledoc "Values of the `printer-wifi-state` attribute, from the IANA IPP registry."

  use Hippy.IPP.Enum, %{
    off: 3,
    not_configured: 4,
    not_visible: 5,
    cannot_join: 6,
    joining: 7,
    on: 8
  }
end
