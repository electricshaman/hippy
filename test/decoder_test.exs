defmodule Hippy.DecoderTest do
  use ExUnit.Case

  alias Hippy.{Decoder, Message}

  @header <<1, 1, 0, 0, 0, 0, 0, 1>>
  @operation_group <<0x01, 0x47, 18::16, "attributes-charset", 5::16, "utf-8">>

  defp decode(groups), do: (@header <> @operation_group <> groups <> <<0x03>>) |> Decoder.decode()

  # The attributes of the first group with a tag, exactly as decoded.
  defp group(%Message{groups: groups}, tag) do
    {^tag, attributes} = List.keyfind(groups, tag, 0)
    attributes
  end

  defp keyword(name, value),
    do: <<0x44, byte_size(name)::16, name::binary, byte_size(value)::16, value::binary>>

  defp name(name, value),
    do: <<0x42, byte_size(name)::16, name::binary, byte_size(value)::16, value::binary>>

  defp enum(name, value), do: <<0x23, byte_size(name)::16, name::binary, 4::16, value::32>>
  defp additional(tag, value), do: <<tag, 0::16, byte_size(value)::16, value::binary>>

  test "decodes captured responses" do
    res = "test/captures/get_printer_attributes_res.bin" |> File.read!() |> Decoder.decode()
    assert Message.status(res) == :successful_ok
    assert map_size(Message.printer(res)) > 50

    res = "test/captures/ipp_get_jobs_res.bin" |> File.read!() |> Decoder.decode()
    assert length(Message.jobs(res)) > 1
  end

  test "status codes Hippy doesn't know are kept as integers" do
    res = Decoder.decode(<<1, 1, 0x0499::16, 0, 0, 0, 1, 0x01, 0x03>>)
    assert Message.status(res) == 0x0499

    res = Decoder.decode(<<1, 1, 0x0406::16, 0, 0, 0, 1, 0x01, 0x03>>)
    assert Message.status(res) == :client_error_not_found
  end

  describe "exactly as sent" do
    test "groups, in order, with repeats and tags IANA hasn't assigned" do
      res =
        decode(
          <<0x04>> <>
            keyword("a", "1") <>
            <<0x0B>> <>
            keyword("x", "1") <> <<0x04>> <> keyword("b", "1") <> <<0x05>> <> keyword("c", "1")
        )

      assert res.groups == [
               {:operation, [{"attributes-charset", [charset: "utf-8"]}]},
               {:printer, [{"a", [keyword: "1"]}]},
               {0x0B, [{"x", [keyword: "1"]}]},
               {:printer, [{"b", [keyword: "1"]}]},
               {:unsupported, [{"c", [keyword: "1"]}]}
             ]
    end

    test "each value with its own syntax, and repeated attributes kept" do
      res =
        decode(
          <<0x04>> <>
            keyword("media", "a4") <>
            additional(0x42, "custom") <>
            enum("printer-state", 3) <> keyword("media", "letter")
        )

      assert group(res, :printer) == [
               {"media", [keyword: "a4", name_without_language: "custom"]},
               {"printer-state", [enum: 3]},
               {"media", [keyword: "letter"]}
             ]
    end

    test "textWithLanguage and nameWithLanguage" do
      text = <<0x35, 4::16, "text", 9::16, 2::16, "en", 3::16, "abc">>
      name = <<0x36, 4::16, "name", 9::16, 2::16, "fr", 3::16, "xyz">>

      assert decode(<<0x04>> <> text <> name) |> group(:printer) == [
               {"text", [text_with_language: {"en", "abc"}]},
               {"name", [name_with_language: {"fr", "xyz"}]}
             ]
    end

    test "collections, with members in order" do
      collection =
        <<0x34, 3::16, "col", 0::16, 0x4A, 0::16, 1::16, "m">> <>
          additional(0x44, "a") <>
          additional(0x44, "b") <>
          <<0x4A, 0::16, 1::16, "n">> <> additional(0x21, <<5::32>>) <> <<0x37, 0::32>>

      assert decode(<<0x04>> <> collection) |> group(:printer) == [
               {"col", [collection: [{"m", [keyword: "a", keyword: "b"]}, {"n", [integer: 5]}]]}
             ]
    end

    test "out-of-band values, and value tags Hippy doesn't know" do
      out_of_band = fn tag, name -> <<tag, byte_size(name)::16, name::binary, 0::16>> end

      res =
        decode(
          <<0x04>> <>
            out_of_band.(0x15, "printer-name") <>
            out_of_band.(0x16, "job-hold-until") <>
            out_of_band.(0x17, "media") <>
            out_of_band.(0x13, "x") <>
            out_of_band.(0x1F, "y") <> <<0x60, 1::16, "z", 2::16, 1, 2>>
        )

      assert group(res, :printer) == [
               {"printer-name", [not_settable: nil]},
               {"job-hold-until", [delete_attribute: nil]},
               {"media", [admin_define: nil]},
               {"x", [no_value: nil]},
               {"y", [{0x1F, ""}]},
               {"z", [{0x60, <<1, 2>>}]}
             ]
    end
  end

  describe "as maps" do
    test "sets are lists in every group" do
      set = keyword("reasons", "a") <> additional(0x44, "b") <> additional(0x44, "c")

      for tag <- [0x01, 0x04, 0x05] do
        res = decode(<<tag>> <> set)
        {_tag, attributes} = List.last(res.groups)
        assert Message.to_map(attributes)["reasons"] == ["a", "b", "c"]
      end
    end

    test "sets are kept per job" do
      res =
        decode(
          <<0x02>> <>
            keyword("job-state-reasons", "job-incoming") <>
            additional(0x44, "job-hold-until-specified") <>
            <<0x02>> <> keyword("job-state-reasons", "none")
        )

      assert Enum.map(Message.jobs(res), & &1["job-state-reasons"]) == [
               ["job-incoming", "job-hold-until-specified"],
               # job-state-reasons is a set, so it's a list even with one value.
               ["none"]
             ]
    end

    test "values of different syntaxes stay together, and values are converted" do
      res =
        decode(
          <<0x04>> <>
            keyword("media", "a4") <>
            additional(0x42, "custom") <>
            additional(0x44, "a4") <>
            enum("printer-state", 3) <>
            <<0x23, 0::16, 4::16, 5::32>> <>
            enum("x-unknown-state", 3) <> enum("finishings-supported", 0x40000001)
        )

      assert Message.printer(res) == %{
               "media" => ["a4", "custom", "a4"],
               "printer-state" => [:idle, :stopped],
               "x-unknown-state" => 3,
               "finishings-supported" => [0x40000001]
             }
    end

    test "attributes repeated by name within a group are merged" do
      res =
        decode(
          <<0x04>> <>
            keyword("types", "a") <>
            additional(0x44, "b") <>
            keyword("sheet-back", "normal") <>
            keyword("types", "b") <> keyword("types", "c") <> keyword("sheet-back", "normal")
        )

      assert Message.printer(res) == %{"types" => ["a", "b", "c"], "sheet-back" => "normal"}
    end

    test "several printers are separate maps" do
      printer = fn name, state, reason ->
        <<0x04>> <>
          name("printer-name", name) <> enum("printer-state", state) <> keyword("r", reason)
      end

      res =
        decode(
          printer.("front-desk", 3, "none") <>
            printer.("warehouse", 5, "none") <> printer.("lab", 3, "media-empty")
        )

      assert Message.printers(res) == [
               %{"printer-name" => "front-desk", "printer-state" => :idle, "r" => "none"},
               %{"printer-name" => "warehouse", "printer-state" => :stopped, "r" => "none"},
               %{"printer-name" => "lab", "printer-state" => :idle, "r" => "media-empty"}
             ]
    end

    test "collections are maps, and out-of-band values are their syntax" do
      collection =
        <<0x34, 3::16, "col", 0::16, 0x4A, 0::16, 1::16, "m">> <>
          additional(0x44, "a") <> additional(0x44, "b") <> <<0x37, 0::32>>

      res = decode(<<0x04>> <> collection <> <<0x13, 1::16, "x", 0::16>>)
      assert Message.printer(res) == %{"col" => %{"m" => ["a", "b"]}, "x" => :no_value}
    end
  end
end
