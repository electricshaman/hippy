defmodule Hippy.DecoderTest do
  use ExUnit.Case

  alias Hippy.Decoder

  @header <<1, 1, 0, 0, 0, 0, 0, 1>>
  @operation_group <<0x01, 0x47, 18::16, "attributes-charset", 5::16, "utf-8">>

  defp response(groups), do: @header <> @operation_group <> groups <> <<0x03>>

  defp keyword(name, value),
    do: <<0x44, byte_size(name)::16, name::binary, byte_size(value)::16, value::binary>>

  defp enum(name, value), do: <<0x23, byte_size(name)::16, name::binary, 4::16, value::32>>

  test "decodes captured Get-Printer-Attributes response" do
    res = Decoder.decode(File.read!("test/captures/get_printer_attributes_res.bin"))
    assert res.status_code == :successful_ok
    assert length(res.printer_attributes) > 0
  end

  test "decodes captured Get-Jobs response" do
    res = Decoder.decode(File.read!("test/captures/ipp_get_jobs_res.bin"))
    assert res.status_code == :successful_ok
    assert length(res.job_attributes) > 0
  end

  test "decodes unsupported attributes group" do
    res = Decoder.decode(response(<<0x05>> <> keyword("foo", "bar")))
    assert res.unsupported_attributes == [{:keyword, "foo", "bar"}]
  end

  test "keeps attribute order across repeated groups" do
    res =
      Decoder.decode(
        response(
          <<0x04>> <> keyword("a", "1") <> keyword("b", "1") <> <<0x04>> <> keyword("c", "1")
        )
      )

    assert Enum.map(res.printer_attributes, &elem(&1, 1)) == ["a", "b", "c"]
  end

  test "decodes textWithLanguage and nameWithLanguage" do
    text = <<0x35, 4::16, "text", 9::16, 2::16, "en", 3::16, "abc">>
    name = <<0x36, 4::16, "name", 9::16, 2::16, "fr", 3::16, "xyz">>
    res = Decoder.decode(response(<<0x04>> <> text <> name))

    assert res.printer_attributes == [
             {:text_with_language, "text", {"en", "abc"}},
             {:name_with_language, "name", {"fr", "xyz"}}
           ]
  end

  test "leaves unknown enum attributes and values as integers" do
    res =
      Decoder.decode(
        response(
          <<0x04>> <>
            enum("document-state", 3) <>
            enum("finishings-supported", 0x40000001) <> enum("printer-state", 3)
        )
      )

    assert res.printer_attributes == [
             {:enum, "document-state", 3},
             {:enum, "finishings-supported", 0x40000001},
             {:enum, "printer-state", :idle}
           ]
  end

  test "keeps order of multi-valued collection members" do
    value = fn v -> <<0x44, 0::16, byte_size(v)::16, v::binary>> end

    collection =
      <<0x34, 3::16, "col", 0::16, 0x4A, 0::16, 1::16, "m">> <>
        value.("a") <> value.("b") <> value.("c") <> value.("d") <> <<0x37, 0::32>>

    res = Decoder.decode(response(<<0x04>> <> collection))
    [{:collection, "col", %{"m" => members}}] = res.printer_attributes
    assert Enum.map(members, &elem(&1, 2)) == ["a", "b", "c", "d"]
  end
end
