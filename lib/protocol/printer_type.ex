defmodule Hippy.Protocol.PrinterType do
  import Bitwise

  @masks %{
    0x00000001 => "Is a printer class.",
    0x00000002 => "Is a remote destination.",
    0x00000004 => "Can print in black.",
    0x00000008 => "Can print in color.",
    0x00000010 => "Can print on both sides of the page in hardware.",
    0x00000020 => "Can staple output.",
    0x00000040 => "Can do fast copies in hardware.",
    0x00000080 => "Can do fast copy collation in hardware.",
    0x00000100 => "Can punch output.",
    0x00000200 => "Can cover output.",
    0x00000400 => "Can bind output.",
    0x00000800 => "Can sort output.",
    0x00001000 => "Can handle media up to US-Legal/A4.",
    0x00002000 => "Can handle media from US-Legal/A4 to ISO-C/A2.",
    0x00004000 => "Can handle media larger than ISO-C/A2.",
    0x00008000 => "Can handle user-defined media sizes.",
    0x00010000 => "Is an implicit (server-generated) class.",
    0x00020000 => "Is the a default printer on the network.",
    0x00040000 => "Is a facsimile device.",
    0x00080000 => "Is rejecting jobs.",
    0x00100000 => "Delete this queue.",
    0x00200000 => "Queue is not shared.",
    0x00400000 => "Queue requires authentication.",
    0x00800000 => "Queue supports CUPS command files.",
    0x01000000 => "Queue was automatically discovered and added.",
    0x02000000 => "Queue is a scanner with no printing capabilities.",
    0x04000000 => "Queue is a printer with scanning capabilities.",
    0x08000000 => "Queue is a printer with 3D capabilities."
  }

  def decode(value) do
    {:ok, value}
  end

  def decode!(value) do
    pairs = Map.to_list(@masks)
    decode_masks(value, pairs, [])
  end

  defp decode_masks(value, [{mask, cap} | t], acc) do
    if (value &&& mask) > 0 do
      decode_masks(value, t, [cap | acc])
    else
      decode_masks(value, t, acc)
    end
  end

  defp decode_masks(_value, [], acc) do
    Enum.reverse(acc)
  end
end
