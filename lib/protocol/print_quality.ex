defmodule Hippy.Protocol.PrintQuality do
  use Hippy.Protocol.Enum, %{
    draft: 0x03,
    normal: 0x04,
    high: 0x05
  }
end
