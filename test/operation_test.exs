defmodule Hippy.OperationTest do
  use ExUnit.Case, async: true

  alias Hippy.{Message, Operation}

  alias Hippy.Operation.{
    CancelJob,
    CancelSubscription,
    CreateJob,
    CreateJobSubscriptions,
    CreatePrinterSubscriptions,
    CupsGetClasses,
    CupsGetDefault,
    CupsGetPrinters,
    GetJobAttributes,
    GetJobs,
    GetNotifications,
    GetPrinterAttributes,
    HoldJob,
    PausePrinter,
    PrintJob,
    ReleaseJob,
    RenewSubscription,
    ResumePrinter,
    SendDocument,
    ValidateJob
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

  test "Get-Printer-Attributes sends requested-attributes only when given" do
    message = @uri |> GetPrinterAttributes.new() |> Operation.build_request()
    refute "requested-attributes" in names(group(message, :operation))

    message =
      @uri
      |> GetPrinterAttributes.new(requested_attributes: ["printer-state", "queued-job-count"])
      |> Operation.build_request()

    assert {"requested-attributes", [keyword: "printer-state", keyword: "queued-job-count"]} in group(
             message,
             :operation
           )
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
          CupsGetDefault.new(@uri, operation_attributes: [extra]),
          ValidateJob.new(@uri, operation_attributes: [extra]),
          CreateJob.new(@uri, operation_attributes: [extra]),
          SendDocument.new(@uri, 1, "doc", operation_attributes: [extra]),
          HoldJob.new(@uri, 1, operation_attributes: [extra]),
          ReleaseJob.new(@uri, 1, operation_attributes: [extra]),
          PausePrinter.new(@uri, operation_attributes: [extra]),
          ResumePrinter.new(@uri, operation_attributes: [extra]),
          CreatePrinterSubscriptions.new(@uri, operation_attributes: [extra]),
          CreateJobSubscriptions.new(@uri, 1, operation_attributes: [extra]),
          GetNotifications.new(@uri, 1, operation_attributes: [extra]),
          RenewSubscription.new(@uri, 1, operation_attributes: [extra]),
          CancelSubscription.new(@uri, 1, operation_attributes: [extra])
        ] do
      assert op |> Operation.build_request() |> group(:operation) |> List.last() ==
               {"requesting-user-name", [name_without_language: "hippy"]}
    end
  end

  describe "job and printer control" do
    test "Validate-Job sends what the same Print-Job would, without a document" do
      opts = [
        job_name: "Report",
        document_format: "application/pdf",
        attributes: %{"copies" => 2}
      ]

      validate = @uri |> ValidateJob.new(opts) |> Operation.build_request()
      print = @uri |> PrintJob.new("doc", opts) |> Operation.build_request()

      assert validate.code == 0x0004
      assert validate.groups == print.groups
      assert validate.data == <<>>
    end

    test "Create-Job sends the job's attributes, and Send-Document each document" do
      create = @uri |> CreateJob.new(job_name: "Contract") |> Operation.build_request()

      assert create.code == 0x0005
      assert {"job-name", [name_without_language: "Contract"]} in group(create, :operation)
      assert {"orientation-requested", [enum: 3]} in group(create, :job)

      send = @uri |> SendDocument.new(7, "doc") |> Operation.build_request()

      assert send.code == 0x0006
      assert send.data == "doc"

      assert group(send, :operation) |> Enum.drop(3) == [
               {"job-id", [integer: 7]},
               {"last-document", [boolean: 1]}
             ]

      send =
        @uri
        |> SendDocument.new(7, "doc",
          last_document: false,
          document_format: "application/pdf",
          document_name: "cover.pdf"
        )
        |> Operation.build_request()

      assert group(send, :operation) |> Enum.drop(3) == [
               {"job-id", [integer: 7]},
               {"last-document", [boolean: 0]},
               {"document-format", [mime_media_type: "application/pdf"]},
               {"document-name", [name_without_language: "cover.pdf"]}
             ]
    end

    test "Hold-Job and Release-Job are about a job, and job-hold-until is optional" do
      for {op, code} <- [{HoldJob, 0x000C}, {ReleaseJob, 0x000D}] do
        message = @uri |> op.new(5) |> Operation.build_request()
        assert message.code == code
        assert group(message, :operation) |> List.last() == {"job-id", [integer: 5]}
      end

      message =
        @uri
        |> HoldJob.new(5, attributes: %{"job-hold-until" => "night"})
        |> Operation.build_request()

      assert {"job-hold-until", [keyword: "night"]} in group(message, :operation)
    end

    test "Pause-Printer and Resume-Printer are about the printer" do
      for {op, code} <- [{PausePrinter, 0x0010}, {ResumePrinter, 0x0011}] do
        message = @uri |> op.new() |> Operation.build_request()
        assert message.code == code
        assert names(group(message, :operation)) |> List.last() == "printer-uri"
        assert Enum.map(message.groups, &elem(&1, 0)) == [:operation]
      end
    end
  end

  describe "subscriptions" do
    test "Create-Printer-Subscriptions sends one subscription group" do
      message = @uri |> CreatePrinterSubscriptions.new() |> Operation.build_request()

      assert message.code == 0x0016

      assert group(message, :subscription) == [
               {"notify-pull-method", [keyword: "ippget"]},
               {"notify-events", [keyword: "job-state-changed", keyword: "printer-state-changed"]}
             ]

      message =
        @uri
        |> CreatePrinterSubscriptions.new(
          events: ["job-completed"],
          lease_duration: 600,
          user_data: "station-3",
          attributes: %{"notify-time-interval" => 5}
        )
        |> Operation.build_request()

      assert group(message, :subscription) == [
               {"notify-pull-method", [keyword: "ippget"]},
               {"notify-events", [keyword: "job-completed"]},
               {"notify-lease-duration", [integer: 600]},
               {"notify-user-data", [octet_string: "station-3"]},
               {"notify-time-interval", [integer: 5]}
             ]
    end

    test "Create-Job-Subscriptions names the job in the subscription" do
      message = @uri |> CreateJobSubscriptions.new(9) |> Operation.build_request()

      assert message.code == 0x0017

      assert group(message, :subscription) == [
               {"notify-job-id", [integer: 9]},
               {"notify-pull-method", [keyword: "ippget"]},
               {"notify-events", [keyword: "job-state-changed"]}
             ]
    end

    test "Get-Notifications sends ids, and sequence numbers and wait when given" do
      message = @uri |> GetNotifications.new(4) |> Operation.build_request()

      assert message.code == 0x001C

      assert group(message, :operation) |> Enum.drop(3) == [
               {"notify-subscription-ids", [integer: 4]}
             ]

      message =
        @uri
        |> GetNotifications.new([4, 5], sequence_numbers: [10, 1], wait: true)
        |> Operation.build_request()

      assert group(message, :operation) |> Enum.drop(3) == [
               {"notify-subscription-ids", [integer: 4, integer: 5]},
               {"notify-sequence-numbers", [integer: 10, integer: 1]},
               {"notify-wait", [boolean: 1]}
             ]
    end

    test "Renew-Subscription and Cancel-Subscription name the subscription" do
      message = @uri |> RenewSubscription.new(4, lease_duration: 60) |> Operation.build_request()

      assert message.code == 0x001A

      assert group(message, :operation) |> Enum.drop(3) == [
               {"notify-subscription-id", [integer: 4]},
               {"notify-lease-duration", [integer: 60]}
             ]

      message = @uri |> CancelSubscription.new(4) |> Operation.build_request()
      assert message.code == 0x001B
      assert group(message, :operation) |> List.last() == {"notify-subscription-id", [integer: 4]}
    end

    test "subscriptions and events are read as maps" do
      message = %Message{
        code: 0,
        request_id: 1,
        groups: [
          {:operation, [{"notify-get-interval", [integer: 60]}]},
          {:subscription, [{"notify-subscription-id", [integer: 4]}]},
          {:event_notification,
           [
             {"notify-sequence-number", [integer: 1]},
             {"notify-subscribed-event", [keyword: "job-completed"]},
             {"job-state", [enum: 9]}
           ]},
          {:event_notification,
           [
             {"notify-sequence-number", [integer: 2]},
             {"notify-subscribed-event", [keyword: "printer-state-changed"]},
             {"printer-state", [enum: 5]}
           ]}
        ]
      }

      assert Message.subscriptions(message) == [%{"notify-subscription-id" => 4}]

      assert Message.events(message) == [
               %{
                 "notify-sequence-number" => 1,
                 "notify-subscribed-event" => "job-completed",
                 "job-state" => :completed
               },
               %{
                 "notify-sequence-number" => 2,
                 "notify-subscribed-event" => "printer-state-changed",
                 "printer-state" => :stopped
               }
             ]
    end
  end
end
