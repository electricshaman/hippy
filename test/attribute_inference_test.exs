defmodule Hippy.AttributeInferenceTest do
  use ExUnit.Case, async: true

  alias Hippy.AttributeInference
  alias Hippy.IPP.Operation

  describe "syntax" do
    test "comes from the registry and the value" do
      assert AttributeInference.attribute("copies", 2) == [{:integer, "copies", 2}]

      assert AttributeInference.attribute("sides", "one-sided") == [
               {:keyword, "sides", "one-sided"}
             ]

      assert AttributeInference.attribute("job-name", "Report") == [
               {:name_without_language, "job-name", "Report"}
             ]

      assert AttributeInference.attribute("document-format", "application/pdf") ==
               [{:mime_media_type, "document-format", "application/pdf"}]

      assert AttributeInference.attribute("ipp-attribute-fidelity", false) ==
               [{:boolean, "ipp-attribute-fidelity", false}]

      assert AttributeInference.attribute("page-ranges", [1..2, 5..5]) ==
               [{:range_of_integer, "page-ranges", [1..2, 5..5]}]

      res = Hippy.PrintResolution.new(600, 600, :dpi)

      assert AttributeInference.attribute("printer-resolution", res) == [
               {:resolution, "printer-resolution", res}
             ]
    end

    test "enums take integers or atoms" do
      assert AttributeInference.attribute("orientation-requested", :landscape) ==
               [{:enum, "orientation-requested", 4}]

      assert AttributeInference.attribute("print-quality", 5) == [{:enum, "print-quality", 5}]
    end

    test "keyword or name is chosen by how the value is spelt" do
      assert AttributeInference.attribute("media", "iso_a4_210x297mm") ==
               [{:keyword, "media", "iso_a4_210x297mm"}]

      assert AttributeInference.attribute("media", "My Paper") ==
               [{:name_without_language, "media", "My Paper"}]

      assert AttributeInference.attribute("media", {:name_without_language, "plain"}) ==
               [{:name_without_language, "media", "plain"}]
    end

    test "collections use their members' syntaxes" do
      media_col = %{
        "media-size" => %{"x-dimension" => 21000, "y-dimension" => 29700},
        "media-type" => "stationery"
      }

      assert AttributeInference.attribute("media-col", media_col) == [
               {:collection, "media-col",
                %{
                  "media-size" =>
                    {:collection,
                     %{"x-dimension" => {:integer, 21000}, "y-dimension" => {:integer, 29700}}},
                  "media-type" => {:keyword, "stationery"}
                }}
             ]
    end

    test "sets whose values have different syntaxes give one tuple per value" do
      assert AttributeInference.attribute("number-up-supported", [1, 2..4]) == [
               {:integer, "number-up-supported", 1},
               {:range_of_integer, nil, 2..4}
             ]
    end

    test "values that don't fit raise" do
      for {name, value, message} <- [
            {"copies", "two", ~s(can't send "two" as copies, which takes integer)},
            {"orientation-requested", :sideways,
             ":sideways isn't a value of orientation-requested"},
            {"media-col", %{"nope" => 1}, ~s("media-col/nope" isn't in the IANA registry)},
            {"notify-events", [], "can't send an empty list"}
          ] do
        assert_raise ArgumentError, ~r/#{Regex.escape(message)}/, fn ->
          AttributeInference.attribute(name, value)
        end
      end
    end
  end

  describe "group" do
    test "prefers the group the operation is about" do
      print_job = Operation.print_job()

      assert AttributeInference.group(print_job, "copies") == :job
      assert AttributeInference.group(print_job, "job-hold-until") == :job
      assert AttributeInference.group(print_job, "job-name") == :operation
      assert AttributeInference.group(print_job, "notify-events") == :subscription_attributes

      assert AttributeInference.group(Operation.cups_add_modify_printer(), "printer-location") ==
               :printer_attributes

      assert AttributeInference.group(Operation.cups_get_printers(), "printer-location") ==
               :operation
    end

    test "attributes the registry doesn't know need their syntax, and go in the main group" do
      assert_raise ArgumentError, ~r/isn't in the IANA registry.*\{syntax, value\}/, fn ->
        AttributeInference.place(Operation.print_job(), %{"x-acme-finish" => "matte"})
      end

      assert AttributeInference.place(Operation.print_job(), %{
               "x-acme-finish" => {:keyword, "matte"}
             }).job ==
               [{:keyword, "x-acme-finish", "matte"}]

      assert AttributeInference.place(Operation.cups_add_modify_printer(), %{
               "device-uri" => {:uri, "socket://10.0.0.5"}
             }).groups == [printer_attributes: [{:uri, "device-uri", "socket://10.0.0.5"}]]

      assert AttributeInference.place(Operation.get_printer_attributes(), %{
               "x-acme-detail" => {:keyword, "full"}
             }).operation == [{:keyword, "x-acme-detail", "full"}]
    end
  end

  test "place groups the attributes for an operation" do
    assert AttributeInference.place(Operation.print_job(), %{
             "copies" => 2,
             "job-name" => "Report",
             "notify-events" => "job-completed"
           }) == %{
             operation: [{:name_without_language, "job-name", "Report"}],
             job: [{:integer, "copies", 2}],
             groups: [subscription_attributes: [{:keyword, "notify-events", "job-completed"}]]
           }
  end
end
