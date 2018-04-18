defmodule Hippy.Protocol.Orientation do
  use Hippy.Protocol.Enum, %{
    portrait: 0x03,
    landscape: 0x04,
    reverse_landscape: 0x05,
    reverse_portrait: 0x06,
    none: 0x07
  }
end
