defmodule Hippy.OperationTest do
  use ExUnit.Case, async: true

  alias Hippy.Operation
  alias Hippy.Operation.{CancelJob, GetJobAttributes, GetJobs, GetPrinterAttributes, PrintJob}

  @uri "http://localhost:631/printers/p"

  test "printer-uri uses ipp for http and ipps for https" do
    for {uri, target} <- [
          {"http://h/p", "ipp://h/p"},
          {"https://h/p", "ipps://h/p"},
          {"ipp://h/p", "ipp://h/p"},
          {"ipps://h/p", "ipps://h/p"}
        ] do
      req = Operation.build_request(GetPrinterAttributes.new(uri))
      assert {:uri, "printer-uri", target} in req.operation_attributes
    end
  end

  test "document-format is only sent when given" do
    req = Operation.build_request(PrintJob.new(@uri, "doc"))
    refute List.keymember?(req.operation_attributes, "document-format", 1)

    req = Operation.build_request(PrintJob.new(@uri, "doc", document_format: "application/pdf"))
    assert {:mime_media_type, "document-format", "application/pdf"} in req.operation_attributes
  end

  test "extra attributes are appended, or replace attributes of the same name" do
    req =
      PrintJob.new(@uri, "doc",
        job_name: "Default",
        operation_attributes: [
          {:name_with_language, "job-name", {"fr", "Rapport"}},
          {:boolean, "ipp-attribute-fidelity", true}
        ],
        job_attributes: [{:integer, "copies", 2}, {:enum, "orientation-requested", 4}]
      )
      |> Operation.build_request()

    assert Enum.map(req.operation_attributes, &elem(&1, 1)) == [
             "attributes-charset",
             "attributes-natural-language",
             "printer-uri",
             "job-name",
             "ipp-attribute-fidelity"
           ]

    assert {:name_with_language, "job-name", {"fr", "Rapport"}} in req.operation_attributes

    assert req.job_attributes == [
             {:enum, "orientation-requested", 4},
             {:integer, "copies", 2}
           ]
  end

  test "every operation accepts operation attributes" do
    extra = {:name_without_language, "requesting-user-name", "hippy"}

    for op <- [
          GetPrinterAttributes.new(@uri, operation_attributes: [extra]),
          GetJobs.new(@uri, operation_attributes: [extra]),
          GetJobAttributes.new(@uri, 1, operation_attributes: [extra]),
          CancelJob.new(@uri, 1, operation_attributes: [extra]),
          PrintJob.new(@uri, "doc", operation_attributes: [extra])
        ] do
      assert List.last(Operation.build_request(op).operation_attributes) == extra
    end
  end
end
