defmodule Hippy.Protocol.PrinterState do
  use Hippy.Protocol.Enum, %{
    idle: 0x03,
    processing: 0x04,
    stopped: 0x05
  }
end
