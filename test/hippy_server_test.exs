defmodule Hippy.ServerTest do
  use ExUnit.Case

  alias Hippy.{Server, Operation.GetJobs}

  @endpoint "http://localhost:631/printers/p"

  test "nil printer_uri in operation returns an error when using send_operation/1" do
    op = %GetJobs{printer_uri: nil}
    {:error, :printer_uri_required} = Server.send_operation(op)
  end

  test "nil endpoint returns an error when using send_operation/2" do
    op = %GetJobs{printer_uri: "http://valid"}
    {:error, :printer_uri_required} = Server.send_operation(op, nil)
  end

  test "posts an IPP request and decodes the response" do
    response = File.read!("test/captures/ipp_get_jobs_res.bin")

    Req.Test.stub(Server, fn conn ->
      assert conn.method == "POST"
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/ipp"]

      conn
      |> Plug.Conn.put_resp_content_type("application/ipp", nil)
      |> Plug.Conn.send_resp(200, response)
    end)

    assert {:ok, %Hippy.Response{status_code: :successful_ok}} =
             Server.send_operation(GetJobs.new(@endpoint))
  end

  test "non-200 HTTP responses return an error" do
    Req.Test.stub(Server, &Plug.Conn.send_resp(&1, 401, "Unauthorized"))

    assert {:error, {:http_error, 401, "Unauthorized"}} =
             Server.send_operation(GetJobs.new(@endpoint))
  end

  test "transport errors return an error" do
    Req.Test.stub(Server, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             Server.send_operation(GetJobs.new(@endpoint))
  end
end
