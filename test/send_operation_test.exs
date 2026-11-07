defmodule Hippy.SendOperationTest do
  use ExUnit.Case

  @printer "ipp://localhost:631/printers/p"

  setup do
    test = self()
    response = File.read!("test/captures/ipp_get_jobs_res.bin")

    Req.Test.stub(Hippy.Server, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, conn.request_path, body})
      Plug.Conn.send_resp(conn, 200, response)
    end)

    :ok
  end

  # The request as sent, decoded exactly.
  defp sent do
    assert_received {:request, path, body}
    {path, Hippy.Message.decode(body)}
  end

  defp group(%Hippy.Message{groups: groups}, tag) do
    case List.keyfind(groups, tag, 0) do
      {^tag, attributes} -> attributes
      nil -> []
    end
  end

  defp names(attributes), do: Enum.map(attributes, &elem(&1, 0))

  test "sends any operation by name, placing attributes by inference" do
    {:ok, _} =
      Hippy.send_operation(@printer, :validate_job, %{
        "document-format" => "application/pdf",
        "copies" => 2
      })

    {path, req} = sent()
    assert path == "/printers/p"
    assert Hippy.Message.operation_name(req) == :validate_job

    assert names(group(req, :operation)) == [
             "attributes-charset",
             "attributes-natural-language",
             "printer-uri",
             "document-format"
           ]

    assert {"printer-uri", [uri: @printer]} in group(req, :operation)
    assert group(req, :job) == [{"copies", [integer: 2]}]
  end

  test "takes operation ids, documents and explicit attributes" do
    {:ok, _} =
      Hippy.send_operation(@printer, 0x0002, %{"job-name" => "Report"},
        document: "%PDF",
        job_attributes: [{:keyword, "x-acme-finish", "matte"}]
      )

    {_path, req} = sent()
    assert req.code == 0x0002
    assert {"job-name", [name_without_language: "Report"]} in group(req, :operation)
    assert group(req, :job) == [{"x-acme-finish", [keyword: "matte"]}]
    assert req.data == "%PDF"
  end

  test "CUPS server operations have no printer-uri" do
    {:ok, _} = Hippy.send_operation("ipp://localhost:631/", :cups_get_printers, %{"limit" => 2})

    {path, req} = sent()
    assert path == "/"

    assert names(group(req, :operation)) == [
             "attributes-charset",
             "attributes-natural-language",
             "limit"
           ]
  end

  test "job URIs are sent as job-uri" do
    {:ok, _} = Hippy.send_operation("ipp://localhost:631/jobs/12", :get_job_attributes, %{})

    {path, req} = sent()
    assert path == "/jobs/12"
    assert {"job-uri", [uri: "ipp://localhost:631/jobs/12"]} in group(req, :operation)
    refute "printer-uri" in names(group(req, :operation))
  end

  test "the target can be given, or replaced by an attribute" do
    {:ok, _} = Hippy.send_operation(@printer, :get_printer_attributes, %{}, target: :server)
    {_path, req} = sent()
    refute "printer-uri" in names(group(req, :operation))

    other = "ipp://localhost:631/printers/other"

    {:ok, _} =
      Hippy.send_operation("ipp://localhost:631/admin/", :cups_add_modify_printer, %{
        "printer-uri" => other
      })

    {path, req} = sent()
    assert path == "/admin/"

    assert Enum.filter(group(req, :operation), &(elem(&1, 0) == "printer-uri")) == [
             {"printer-uri", [uri: other]}
           ]
  end

  test "documents can be streamed, and arrive as the same bytes" do
    chunks = for n <- 1..50, do: :binary.copy(<<n>>, 1000)

    {:ok, _} = Hippy.send_operation(@printer, :print_job, %{}, document: Stream.map(chunks, & &1))
    assert_received {:request, _, streamed}

    {:ok, _} = Hippy.send_operation(@printer, :print_job, %{}, document: Enum.join(chunks))
    assert_received {:request, _, binary}

    # Request ids differ; everything else is the same.
    <<header::binary-size(4), _id::32, rest::binary>> = streamed
    assert <<^header::binary-size(4), _::32, ^rest::binary>> = binary
    assert String.ends_with?(streamed, Enum.join(chunks))
  end

  test "streamed documents are sent with chunked transfer encoding, not buffered" do
    # A bare TCP server, so the request goes through Req's real HTTP client rather than the
    # Req.Test plug configured for tests.
    configured = Application.get_env(:hippy, :req_options)
    Application.put_env(:hippy, :req_options, [])
    on_exit(fn -> Application.put_env(:hippy, :req_options, configured) end)

    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    test = self()
    response = File.read!("test/captures/ipp_get_jobs_res.bin")

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      request = read_until(socket, "0\r\n\r\n", "")
      send(test, {:raw_request, request})

      :gen_tcp.send(socket, [
        "HTTP/1.1 200 OK\r\ncontent-type: application/ipp\r\n",
        "content-length: #{byte_size(response)}\r\nconnection: close\r\n\r\n",
        response
      ])

      :gen_tcp.close(socket)
    end)

    document = Stream.map(1..3, &:binary.copy(<<?a + &1>>, 10_000))

    {:ok, _} =
      Hippy.send_operation("ipp://localhost:#{port}/printers/p", :print_job, %{},
        document: document
      )

    assert_received {:raw_request, request}
    [headers, _body] = String.split(request, "\r\n\r\n", parts: 2)
    headers = String.downcase(headers)

    assert headers =~ "transfer-encoding: chunked"
    refute headers =~ "content-length"
    assert request =~ :binary.copy("c", 10_000)
  end

  defp read_until(socket, terminator, acc) do
    if String.ends_with?(acc, terminator) do
      acc
    else
      {:ok, data} = :gen_tcp.recv(socket, 0, 5000)
      read_until(socket, terminator, acc <> data)
    end
  end

  test "unknown operation names return an error" do
    assert Hippy.send_operation(@printer, :print_everything, %{}) ==
             {:error, {:unknown_operation, :print_everything}}

    refute_received {:request, _, _}
  end
end
