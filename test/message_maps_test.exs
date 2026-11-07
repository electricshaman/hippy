defmodule Hippy.MessageMapsTest do
  use ExUnit.Case, async: true

  alias Hippy.Message

  defp capture(name), do: "test/captures/#{name}" |> File.read!() |> Message.decode()

  test "jobs returns a map per job" do
    res = capture("ipp_get_jobs_res.bin")
    jobs = Message.jobs(res)

    assert length(jobs) == Enum.count(res.groups, &match?({:job, _}, &1))
    assert length(jobs) > 1
    assert Enum.all?(jobs, &is_integer(&1["job-id"]))
    assert jobs |> Enum.map(& &1["job-id"]) |> Enum.uniq() |> length() == length(jobs)
    assert Message.job(res) == hd(jobs)
  end

  test "printer and operation attributes as maps, with values converted" do
    res = capture("get_printer_attributes_res.bin")
    printer = Message.printer(res)

    assert printer["printer-state"] in [:idle, :processing, :stopped]
    assert printer["printer-is-accepting-jobs"] in [true, false]
    assert %URI{} = hd(printer["printer-uri-supported"])
    assert Message.operation_attributes(res)["attributes-charset"] == "utf-8"
    assert Message.job(res) == nil
    assert Message.jobs(res) == []
    assert Message.unsupported(res) == %{}
  end

  test "printers returns a map per printer, and printer the first" do
    res = %Message{
      groups: [
        {:operation, []},
        {:printer,
         [{"printer-name", [name_without_language: "a"]}, {"printer-state", [enum: 3]}]},
        {:job, [{"job-id", [integer: 1]}]},
        {:printer, [{"printer-name", [name_without_language: "b"]}]}
      ]
    }

    assert Message.printers(res) == [
             %{"printer-name" => "a", "printer-state" => :idle},
             %{"printer-name" => "b"}
           ]

    assert Message.printer(res) == hd(Message.printers(res))
    assert Message.groups(res, :job) == [%{"job-id" => 1}]
    assert Message.printer(%Message{}) == nil
    assert Message.printers(%Message{}) == []
  end

  test "unsupported attributes as a map" do
    res = %Message{
      groups: [
        {:unsupported,
         [
           {"document-format", [mime_media_type: "application/x-nope"]},
           {"sides", [keyword: "a", keyword: "b"]}
         ]}
      ]
    }

    assert Message.unsupported(res) == %{
             "document-format" => "application/x-nope",
             "sides" => ["a", "b"]
           }
  end

  test "built messages hold values in their wire form" do
    {:ok, date, _} = DateTime.from_iso8601("2026-11-07T10:15:30.5Z")

    message =
      Message.build_request(0x02, %{charset: "utf-8", language: "en"}, [
        {:boolean, "ipp-attribute-fidelity", true},
        {:datetime, "x-time", date},
        {:uri, "x-uri", URI.parse("ipp://h/p")},
        {:collection, "media-col", %{"media-type" => {:keyword, "plain"}}}
      ])

    {:operation, attributes} = hd(message.groups)

    assert Enum.drop(attributes, 2) == [
             {"ipp-attribute-fidelity", [boolean: 1]},
             {"x-time", [datetime: {2026, 11, 7, 10, 15, 30, 5, "+", 0, 0}]},
             {"x-uri", [uri: "ipp://h/p"]},
             {"media-col", [collection: [{"media-type", [keyword: "plain"]}]]}
           ]

    # So they survive a round trip unchanged.
    message = %{message | request_id: 1}

    assert message |> Message.encode() |> Message.decode() == %{
             message
             | request_id: 1
           }
  end

  test "Hippy.Response's helpers and Hippy.Request.new/4 are deprecated aliases" do
    res = capture("ipp_get_jobs_res.bin")
    assert apply(Hippy.Response, :jobs, [res]) == Message.jobs(res)
    assert apply(Hippy.Response, :operation, [res]) == Message.operation_attributes(res)
    op = %{charset: "utf-8", language: "en", printer_uri: "ipp://h/p"}
    assert apply(Hippy.Request, :new, [0x0B, op]) == Message.build_request(0x0B, op)
  end
end
