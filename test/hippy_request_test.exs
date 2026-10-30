defmodule Hippy.RequestTest do
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

  # The request as sent, decoded exactly (requests and responses share a layout, so the
  # operation id is in status_code).
  defp sent do
    assert_received {:request, path, body}
    {path, Hippy.Decoder.decode(body, raw: true)}
  end

  defp names(attributes), do: Enum.map(attributes, &elem(&1, 1))

  test "sends any operation by name, placing attributes by inference" do
    {:ok, _} =
      Hippy.request(@printer, :validate_job, %{
        "document-format" => "application/pdf",
        "copies" => 2
      })

    {path, req} = sent()
    assert path == "/printers/p"
    assert req.status_code == Hippy.IPP.Operation.validate_job()

    assert names(req.operation_attributes) == [
             "attributes-charset",
             "attributes-natural-language",
             "printer-uri",
             "document-format"
           ]

    assert {:uri, "printer-uri", @printer} in req.operation_attributes
    assert req.job_attributes == [[{:integer, "copies", 2}]]
  end

  test "takes operation ids, documents and explicit attributes" do
    {:ok, _} =
      Hippy.request(@printer, 0x0002, %{"job-name" => "Report"},
        document: "%PDF",
        job_attributes: [{:keyword, "x-acme-finish", "matte"}]
      )

    {_path, req} = sent()
    assert req.status_code == 0x0002
    assert {:name_without_language, "job-name", "Report"} in req.operation_attributes
    assert req.job_attributes == [[{:keyword, "x-acme-finish", "matte"}]]
    assert req.data == "%PDF"
  end

  test "CUPS server operations have no printer-uri" do
    {:ok, _} = Hippy.request("ipp://localhost:631/", :cups_get_printers, %{"limit" => 2})

    {path, req} = sent()
    assert path == "/"

    assert names(req.operation_attributes) == [
             "attributes-charset",
             "attributes-natural-language",
             "limit"
           ]
  end

  test "job URIs are sent as job-uri" do
    {:ok, _} = Hippy.request("ipp://localhost:631/jobs/12", :get_job_attributes)

    {path, req} = sent()
    assert path == "/jobs/12"
    assert {:uri, "job-uri", "ipp://localhost:631/jobs/12"} in req.operation_attributes
    refute "printer-uri" in names(req.operation_attributes)
  end

  test "the target can be given, or replaced by an attribute" do
    {:ok, _} = Hippy.request(@printer, :get_printer_attributes, %{}, target: :server)
    {_path, req} = sent()
    refute "printer-uri" in names(req.operation_attributes)

    other = "ipp://localhost:631/printers/other"

    {:ok, _} =
      Hippy.request("ipp://localhost:631/admin/", :cups_add_modify_printer, %{
        "printer-uri" => other
      })

    {path, req} = sent()
    assert path == "/admin/"

    assert Enum.filter(req.operation_attributes, &(elem(&1, 1) == "printer-uri")) == [
             {:uri, "printer-uri", other}
           ]
  end

  test "unknown operation names return an error" do
    assert Hippy.request(@printer, :print_everything) ==
             {:error, {:unknown_operation, :print_everything}}

    refute_received {:request, _, _}
  end
end
