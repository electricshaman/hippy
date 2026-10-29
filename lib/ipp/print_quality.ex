defmodule Hippy.IPP.PrintQuality do
  use Hippy.IPP.Enum, %{
    draft: 0x03,
    normal: 0x04,
    high: 0x05
  }
end
