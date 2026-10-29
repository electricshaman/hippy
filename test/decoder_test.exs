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
            enum("x-unknown-state", 3) <>
            enum("finishings-supported", 0x40000001) <> enum("printer-state", 3)
        )
      )

    assert res.printer_attributes == [
             {:enum, "x-unknown-state", 3},
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

  describe "multi-valued attributes" do
    defp additional(tag, value), do: <<tag, 0::16, byte_size(value)::16, value::binary>>

    test "are decoded as a list in every group" do
      set = keyword("reasons", "a") <> additional(0x44, "b") <> additional(0x44, "c")

      for {delimiter, field} <- [
            {0x01, :operation_attributes},
            {0x04, :printer_attributes},
            {0x05, :unsupported_attributes}
          ] do
        res = Decoder.decode(response(<<delimiter>> <> set))
        assert {:keyword, "reasons", ["a", "b", "c"]} in res[field]
      end
    end

    test "are kept per job" do
      res =
        Decoder.decode(
          response(
            <<0x02>> <>
              keyword("job-state-reasons", "job-incoming") <>
              additional(0x44, "job-hold-until-specified") <>
              <<0x02>> <> keyword("job-state-reasons", "none")
          )
        )

      assert Hippy.AttributeGroup.to_map(res.job_attributes, 0)["job-state-reasons"] ==
               ["job-incoming", "job-hold-until-specified"]

      assert Hippy.AttributeGroup.to_map(res.job_attributes, 1)["job-state-reasons"] == "none"
    end

    test "keep repeated values and values of different syntaxes" do
      res =
        Decoder.decode(
          response(
            <<0x04>> <>
              keyword("media", "a4") <>
              additional(0x42, "custom") <>
              additional(0x44, "a4") <> keyword("other", "x")
          )
        )

      assert res.printer_attributes == [
               {:keyword, "media", ["a4", "custom", "a4"]},
               {:keyword, "other", "x"}
             ]
    end

    test "transform each value" do
      res =
        Decoder.decode(
          response(<<0x04>> <> enum("printer-state", 3) <> <<0x23, 0::16, 4::16, 5::32>>)
        )

      assert res.printer_attributes == [{:enum, "printer-state", [:idle, :stopped]}]
    end
  end

  test "merges attributes repeated by name within a group" do
    res =
      Decoder.decode(
        response(
          <<0x04>> <>
            keyword("types", "a") <>
            additional(0x44, "b") <>
            keyword("sheet-back", "normal") <>
            keyword("types", "b") <> keyword("types", "c") <> keyword("sheet-back", "normal")
        )
      )

    assert res.printer_attributes == [
             {:keyword, "types", ["a", "b", "c"]},
             {:keyword, "sheet-back", "normal"}
           ]
  end

  describe "groups and values added after RFC 8011" do
    test "subscription, event notification, resource and document groups are kept per group" do
      for {tag, field} <- [
            {0x06, :subscription_attributes},
            {0x07, :event_notification_attributes},
            {0x08, :resource_attributes},
            {0x09, :document_attributes}
          ] do
        res =
          Decoder.decode(response(<<tag>> <> keyword("a", "1") <> <<tag>> <> keyword("a", "2")))

        assert res[field] == [[{:keyword, "a", "1"}], [{:keyword, "a", "2"}]]
      end
    end

    test "system attributes are a single group" do
      res = Decoder.decode(response(<<0x0A>> <> keyword("system-state-reasons", "none")))
      assert res.system_attributes == [{:keyword, "system-state-reasons", "none"}]
    end

    test "group tags not assigned by IANA go to unknown_attributes" do
      res =
        Decoder.decode(response(<<0x0B>> <> keyword("x", "1") <> <<0x04>> <> keyword("y", "2")))

      assert res.unknown_attributes == [{:keyword, "x", "1"}]
      assert res.printer_attributes == [{:keyword, "y", "2"}]
    end

    test "out-of-band values" do
      out_of_band = fn tag, name -> <<tag, byte_size(name)::16, name::binary, 0::16>> end

      res =
        Decoder.decode(
          response(
            <<0x04>> <>
              out_of_band.(0x15, "printer-name") <>
              out_of_band.(0x16, "job-hold-until") <>
              out_of_band.(0x17, "media") <>
              out_of_band.(0x13, "x") <> out_of_band.(0x1F, "y")
          )
        )

      assert res.printer_attributes == [
               {:not_settable, "printer-name", :not_settable},
               {:delete_attribute, "job-hold-until", :delete_attribute},
               {:admin_define, "media", :admin_define},
               {:no_value, "x", :no_value},
               {:out_of_band, "y", :out_of_band}
             ]
    end

    test "syntaxes reserved for future use are kept as raw bytes" do
      res = Decoder.decode(response(<<0x04, 0x60, 1::16, "x", 2::16, 1, 2>>))
      assert res.printer_attributes == [{:octet_string, "x", <<1, 2>>}]
    end
  end
end
