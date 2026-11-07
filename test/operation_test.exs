defmodule Hippy.OperationTest do
  use ExUnit.Case, async: true

  alias Hippy.{Message, Operation}

  alias Hippy.Operation.{
    CancelJob,
    CupsGetClasses,
    CupsGetDefault,
    CupsGetPrinters,
    GetJobAttributes,
    GetJobs,
    GetPrinterAttributes,
    PrintJob
  }

  @uri "http://localhost:631/printers/p"

  # The attributes of a message's first group with a tag, or [] if there isn't one.
  defp group(%Message{groups: groups}, tag) do
    case List.keyfind(groups, tag, 0) do
      {^tag, attributes} -> attributes
      nil -> []
    end
  end

  defp names(attributes), do: Enum.map(attributes, &elem(&1, 0))

  test "printer-uri uses ipp for http and ipps for https" do
    for {uri, target} <- [
          {"http://h/p", "ipp://h/p"},
          {"https://h/p", "ipps://h/p"},
          {"ipp://h/p", "ipp://h/p"},
          {"ipps://h/p", "ipps://h/p"}
        ] do
      message = uri |> GetPrinterAttributes.new() |> Operation.build_request()
      assert {"printer-uri", [uri: target]} in group(message, :operation)
    end
  end

  test "document-format is only sent when given" do
    message = @uri |> PrintJob.new("doc") |> Operation.build_request()
    refute "document-format" in names(group(message, :operation))

    message =
      @uri
      |> PrintJob.new("doc", document_format: "application/pdf")
      |> Operation.build_request()

    assert {"document-format", [mime_media_type: "application/pdf"]} in group(message, :operation)
  end

  test "extra attributes are appended, or replace attributes of the same name" do
    message =
      PrintJob.new(@uri, "doc",
        job_name: "Default",
        operation_attributes: [
          {:name_with_language, "job-name", {"fr", "Rapport"}},
          {:boolean, "ipp-attribute-fidelity", true}
        ],
        job_attributes: [{:integer, "copies", 2}, {:enum, "orientation-requested", 4}]
      )
      |> Operation.build_request()

    assert names(group(message, :operation)) == [
             "attributes-charset",
             "attributes-natural-language",
             "printer-uri",
             "job-name",
             "ipp-attribute-fidelity"
           ]

    assert {"job-name", [name_with_language: {"fr", "Rapport"}]} in group(message, :operation)

    assert group(message, :job) == [
             {"orientation-requested", [enum: 4]},
             {"copies", [integer: 2]}
           ]
  end

  describe "CUPS server operations" do
    test "have no printer-uri, and only send the filters given" do
      message = "ipp://localhost:631/" |> CupsGetPrinters.new() |> Operation.build_request()

      assert message.code == 0x4002

      assert group(message, :operation) == [
               {"attributes-charset", [charset: "utf-8"]},
               {"attributes-natural-language", [natural_language: "en"]},
               {"requested-attributes", [keyword: "all"]}
             ]

      message =
        CupsGetClasses.new("ipp://localhost:631/",
          requested_attributes: ["printer-name"],
          limit: 5,
          first_printer_name: "b",
          printer_location: "Lab",
          printer_type: 0,
          printer_type_mask: 1
        )
        |> Operation.build_request()

      assert message.code == 0x4005

      assert message |> group(:operation) |> Enum.drop(2) == [
               {"requested-attributes", [keyword: "printer-name"]},
               {"limit", [integer: 5]},
               {"first-printer-name", [name_without_language: "b"]},
               {"printer-location", [text_without_language: "Lab"]},
               {"printer-type", [enum: 0]},
               {"printer-type-mask", [enum: 1]}
             ]

      message = "ipp://localhost:631/" |> CupsGetDefault.new() |> Operation.build_request()
      assert message.code == 0x4001
      refute "printer-uri" in names(group(message, :operation))
    end
  end

  test "operations add their groups after any given to build_request/4" do
    subscription = {:subscription, [{:keyword, "notify-events", "job-completed"}]}

    message = @uri |> PrintJob.new("doc", groups: [subscription]) |> Operation.build_request()
    assert {:subscription, [{"notify-events", [keyword: "job-completed"]}]} in message.groups

    printer = {:printer, [{:text_without_language, "printer-location", "Lab"}]}
    op = GetPrinterAttributes.new(@uri, groups: [subscription])

    assert 0x0B
           |> Message.build_request(op, [], groups: [printer])
           |> Map.fetch!(:groups)
           |> Enum.map(&elem(&1, 0)) == [:operation, :printer, :subscription]
  end

  test "group names from before 0.7 are accepted" do
    old = {:subscription_attributes, [{:keyword, "notify-events", "job-completed"}]}
    message = @uri |> PrintJob.new("doc", groups: [old]) |> Operation.build_request()

    assert {:subscription, [{"notify-events", [keyword: "job-completed"]}]} in message.groups
  end

  test "attributes are placed by inference, and explicit options override them" do
    message =
      PrintJob.new(@uri, "doc",
        job_name: "Default",
        attributes: %{
          "copies" => 2,
          "job-name" => "Inferred",
          "orientation-requested" => :landscape
        },
        job_attributes: [{:integer, "copies", 3}]
      )
      |> Operation.build_request()

    # Inferred attributes replace the defaults; explicit ones replace inferred ones.
    assert {"job-name", [name_without_language: "Inferred"]} in group(message, :operation)

    assert group(message, :job) == [
             {"orientation-requested", [enum: 4]},
             {"copies", [integer: 3]}
           ]
  end

  test "every operation accepts operation attributes" do
    extra = {:name_without_language, "requesting-user-name", "hippy"}

    for op <- [
          GetPrinterAttributes.new(@uri, operation_attributes: [extra]),
          GetJobs.new(@uri, operation_attributes: [extra]),
          GetJobAttributes.new(@uri, 1, operation_attributes: [extra]),
          CancelJob.new(@uri, 1, operation_attributes: [extra]),
          PrintJob.new(@uri, "doc", operation_attributes: [extra]),
          CupsGetPrinters.new(@uri, operation_attributes: [extra]),
          CupsGetClasses.new(@uri, operation_attributes: [extra]),
          CupsGetDefault.new(@uri, operation_attributes: [extra])
        ] do
      assert op |> Operation.build_request() |> group(:operation) |> List.last() ==
               {"requesting-user-name", [name_without_language: "hippy"]}
    end
  end
end
