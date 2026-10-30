defmodule Hippy.ResponseTest do
  use ExUnit.Case, async: true

  alias Hippy.{Decoder, Response}

  defp capture(name), do: Decoder.decode(File.read!("test/captures/#{name}"))

  test "jobs returns a map per job" do
    res = capture("ipp_get_jobs_res.bin")
    jobs = Response.jobs(res)

    assert length(jobs) == length(res.job_attributes)
    assert length(jobs) > 1
    assert Enum.all?(jobs, &is_integer(&1["job-id"]))
    assert jobs |> Enum.map(& &1["job-id"]) |> Enum.uniq() |> length() == length(jobs)
    assert Response.job(res) == hd(jobs)
  end

  test "printer and operation attributes as maps" do
    res = capture("get_printer_attributes_res.bin")

    assert Response.printer(res)["printer-state"] in [:idle, :processing, :stopped]
    assert Response.operation(res)["attributes-charset"] == "utf-8"
    assert Response.job(res) == nil
    assert Response.jobs(res) == []
    assert Response.unsupported(res) == %{}
  end

  test "printers returns a map per printer, and printer the first" do
    res = %Response{
      printer_attributes: [
        [{:name_without_language, "printer-name", "a"}, {:enum, "printer-state", :idle}],
        [{:name_without_language, "printer-name", "b"}]
      ]
    }

    assert Response.printers(res) == [
             %{"printer-name" => "a", "printer-state" => :idle},
             %{"printer-name" => "b"}
           ]

    assert Response.printer(res) == hd(Response.printers(res))
    assert Response.printer(%Response{}) == nil
    assert Response.printers(%Response{}) == []
  end

  test "unsupported attributes as a map" do
    res = %Response{
      unsupported_attributes: [
        {:mime_media_type, "document-format", "application/x-nope"},
        {:keyword, "sides", ["a", "b"]}
      ]
    }

    assert Response.unsupported(res) == %{
             "document-format" => "application/x-nope",
             "sides" => ["a", "b"]
           }
  end

  test "an empty job group is an empty map" do
    assert Response.job(%Response{job_attributes: [[]]}) == %{}
  end
end
