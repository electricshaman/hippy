defmodule Hippy.EncoderTest do
  use ExUnit.Case

  alias Hippy.{Encoder, Operation}

  test "job attributes are encoded in a job attributes group" do
    bin =
      Operation.PrintJob.new("http://localhost:631/printers/p", "DOC")
      |> Operation.build_request()
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
      |> Encoder.encode()

    assert String.ends_with?(bin, <<"ipp://localhost:631/printers/p", 0x03>>)
  end

  test "which-jobs atoms are encoded as hyphenated keywords" do
    req =
      Operation.GetJobs.new("http://localhost:631/printers/p", which_jobs: :not_completed)
      |> Operation.build_request()

    assert {:keyword, "which-jobs", "not-completed"} in req.operation_attributes
  end
end
