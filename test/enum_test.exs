defmodule Hippy.EnumTest do
  use ExUnit.Case, async: false

  alias Hippy.Decoder

  defmodule VendorState do
    use Hippy.IPP.Enum, %{
      idle: 0x01,
      busy: 0x02
    }
  end

  defp decode_printer_attributes(attributes) do
    groups =
      for {name, values} <- attributes, into: <<0x04>> do
        [first | rest] = List.wrap(values)

        for value <- rest, into: <<0x23, byte_size(name)::16, name::binary, 4::16, first::32>> do
          <<0x23, 0::16, 4::16, value::32>>
        end
      end

    Decoder.decode(<<1, 1, 0, 0, 0, 0, 0, 1>> <> groups <> <<0x03>>).printer_attributes
    |> Hippy.AttributeGroup.to_map()
  end

  defp put_enums(enums) do
    Application.put_env(:hippy, :enums, enums)
    on_exit(fn -> Application.delete_env(:hippy, :enums) end)
  end

  test "enum modules implement the behaviour" do
    for mod <- [
          Hippy.IPP.JobState,
          Hippy.IPP.Orientation,
          Hippy.IPP.PrinterType,
          Hippy.IPP.PrinterWifiState
        ] do
      assert Hippy.IPP.Enum in Keyword.get(mod.module_info(:attributes), :behaviour, [])
    end
  end

  test "printer-type is decoded into capabilities" do
    assert decode_printer_attributes([{"printer-type", 0x0000100C}])["printer-type"] == [
             "Can print in black.",
             "Can print in color.",
             "Can handle media up to US-Legal/A4."
           ]
  end

  test "job-state values outside RFC 8011 are left as integers" do
    assert decode_printer_attributes([{"job-state", 0}])["job-state"] == 0
    assert decode_printer_attributes([{"job-state", 9}])["job-state"] == :completed
  end

  test "printer-wifi-state is left as an integer" do
    assert decode_printer_attributes([{"printer-wifi-state", 3}])["printer-wifi-state"] == 3
  end

  test "-default and -supported variants use the base enum" do
    attrs =
      decode_printer_attributes([
        {"orientation-requested-default", 3},
        {"orientation-requested-supported", [3, 4]},
        {"print-quality-supported", [3, 5]}
      ])

    assert attrs["orientation-requested-default"] == :portrait
    assert attrs["orientation-requested-supported"] == [:portrait, :landscape]
    assert attrs["print-quality-supported"] == [:draft, :high]
  end

  test "enums can be registered in config" do
    attrs = [{"x-vendor-state", 2}, {"x-vendor-state-supported", [1, 2]}]
    assert decode_printer_attributes(attrs)["x-vendor-state"] == 2

    put_enums(%{"x-vendor-state" => VendorState})
    assert decode_printer_attributes(attrs)["x-vendor-state"] == :busy
    assert decode_printer_attributes(attrs)["x-vendor-state-supported"] == [:idle, :busy]
  end

  test "config overrides built-in enums" do
    put_enums(%{
      "printer-type" => VendorState,
      "input-orientation-requested" => Hippy.IPP.Orientation
    })

    attrs = decode_printer_attributes([{"printer-type", 1}, {"input-orientation-requested", 4}])
    assert attrs["printer-type"] == :idle
    assert attrs["input-orientation-requested"] == :landscape
  end
end
