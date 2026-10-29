defmodule Hippy.IPP.PrinterState do
  use Hippy.IPP.Enum, %{
    idle: 0x03,
    processing: 0x04,
    stopped: 0x05
  }
end
