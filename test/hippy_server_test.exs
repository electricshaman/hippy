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

  test "ipp and ipps URIs are sent over http and https, on port 631 by default" do
    assert Server.format_endpoint("ipp://h/p") == {:ok, "http://h:631/p"}
    assert Server.format_endpoint("ipps://h/p") == {:ok, "https://h:631/p"}
    assert Server.format_endpoint("ipp://h:8631/p") == {:ok, "http://h:8631/p"}
    assert Server.format_endpoint("http://h/p") == {:ok, "http://h/p"}
    assert Server.format_endpoint("lpd://h/p") == {:error, {:unsupported_uri_scheme, "lpd"}}
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

  test "assigns a request id unless one is set" do
    response = File.read!("test/captures/ipp_get_jobs_res.bin")
    test = self()

    Req.Test.stub(Server, fn conn ->
      {:ok, <<_version::16, _operation::16, request_id::32, _::binary>>, conn} =
        Plug.Conn.read_body(conn)

      send(test, {:request_id, request_id})
      Plug.Conn.send_resp(conn, 200, response)
    end)

    req = Hippy.Operation.build_request(GetJobs.new(@endpoint))
    assert req.request_id == nil

    {:ok, _} = Server.send_request(req, @endpoint)
    {:ok, _} = Server.send_request(req, @endpoint)
    assert_received {:request_id, first}
    assert_received {:request_id, second}
    assert first > 0 and second > first

    {:ok, _} = Server.send_request(%{req | request_id: 1234}, @endpoint)
    assert_received {:request_id, 1234}
  end

  describe "options" do
    setup do
      test = self()
      response = File.read!("test/captures/ipp_get_jobs_res.bin")

      Req.Test.stub(Server, fn conn ->
        send(test, {:request, conn})
        Plug.Conn.send_resp(conn, 200, response)
      end)

      :ok
    end

    test "req_options apply to one call" do
      {:ok, _} =
        Server.send_operation(GetJobs.new(@endpoint), req_options: [auth: {:basic, "u:p"}])

      assert_received {:request, conn}
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Basic " <> Base.encode64("u:p")]

      {:ok, _} = Server.send_operation(GetJobs.new(@endpoint))
      assert_received {:request, conn}
      assert Plug.Conn.get_req_header(conn, "authorization") == []
    end

    test "req_options are merged over the configured ones" do
      Req.Test.stub(:other, &Plug.Conn.send_resp(&1, 401, "other"))

      assert {:error, {:http_error, 401, "other"}} =
               Server.send_operation(GetJobs.new(@endpoint),
                 req_options: [plug: {Req.Test, :other}]
               )
    end

    test "configured and per-call headers keep the IPP content type" do
      configured = Application.get_env(:hippy, :req_options)
      Application.put_env(:hippy, :req_options, configured ++ [headers: [{"x-config", "1"}]])
      on_exit(fn -> Application.put_env(:hippy, :req_options, configured) end)

      {:ok, _} =
        Server.send_operation(GetJobs.new(@endpoint), req_options: [headers: [{"x-call", "2"}]])

      assert_received {:request, conn}
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/ipp"]
      assert Plug.Conn.get_req_header(conn, "x-config") == ["1"]
      assert Plug.Conn.get_req_header(conn, "x-call") == ["2"]
    end

    test "endpoint can be given as an option or as the second argument" do
      op = GetJobs.new("ipp://printer.example/printers/p")

      {:ok, _} = Server.send_operation(op)
      assert_received {:request, %{host: "printer.example", port: 631}}

      {:ok, _} = Server.send_operation(op, endpoint: "http://other.example:8631/ipp")
      assert_received {:request, %{host: "other.example", port: 8631, request_path: "/ipp"}}

      {:ok, _} = Server.send_operation(op, "http://legacy.example/ipp")
      assert_received {:request, %{host: "legacy.example", port: 80}}

      assert Server.send_operation(op, endpoint: nil) == {:error, :printer_uri_required}
    end
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
