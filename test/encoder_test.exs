defmodule Hippy.EncoderTest do
  use ExUnit.Case

  alias Hippy.{Encoder, Operation}

  test "job attributes are encoded in a job attributes group" do
    bin =
      Operation.PrintJob.new("http://localhost:631/printers/p", "DOC")
      |> Operation.build_request()
      |> Map.put(:request_id, 1)
      |> Encoder.encode()

    orientation = Hippy.Protocol.Orientation.portrait()

    assert String.ends_with?(
             bin,
             <<0x02, 0x23, 21::16, "orientation-requested", 4::16, orientation::32, 0x03, "DOC">>
           )
  end

  test "requests without job attributes have no job attributes group" do
    bin =
      Operation.GetPrinterAttributes.new("http://localhost:631/printers/p")
      |> Operation.build_request()
      |> Map.put(:request_id, 1)
      |> Encoder.encode()

    assert String.ends_with?(bin, <<"ipp://localhost:631/printers/p", 0x03>>)
  end

  test "requests start with the common operation attributes" do
    req =
      Operation.CancelJob.new("https://localhost/printers/p", 7,
        charset: "us-ascii",
        language: "fr"
      )
      |> Operation.build_request()

    assert req.operation_attributes == [
             {:charset, "attributes-charset", "us-ascii"},
             {:natural_language, "attributes-natural-language", "fr"},
             {:uri, "printer-uri", "ipp://localhost/printers/p"},
             {:integer, "job-id", 7}
           ]
  end

  test "requests without a request id are rejected" do
    assert_raise ArgumentError, ~r/request_id is required/, fn ->
      Encoder.encode(%Hippy.Request{operation_id: 0x0B})
    end
  end

  test "requests built by hand default to no document" do
    bin = Encoder.encode(%Hippy.Request{operation_id: 0x0B, request_id: 1})
    assert bin == <<1, 1, 0x0B::16, 1::32, 0x01, 0x03>>
  end

  test "which-jobs atoms are encoded as hyphenated keywords" do
    req =
      Operation.GetJobs.new("http://localhost:631/printers/p", which_jobs: :not_completed)
      |> Operation.build_request()

    assert {:keyword, "which-jobs", "not-completed"} in req.operation_attributes
  end
end
