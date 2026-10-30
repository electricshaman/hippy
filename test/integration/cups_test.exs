defmodule Hippy.Integration.CupsTest do
  @moduledoc """
  End-to-end tests against a real CUPS server running in Docker.

  Excluded by default. Run with `mix test --only cups` (requires a running Docker daemon).
  A fresh container is started for each run and removed afterwards.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Hippy.{AttributeGroup, Response}

  alias Hippy.Operation.{
    CancelJob,
    CupsGetClasses,
    CupsGetDefault,
    CupsGetPrinters,
    GetJobAttributes,
    GetJobs,
    GetPrinterAttributes,
    PrintJob
  }

  alias Hippy.IPP.Orientation

  @moduletag :cups
  @moduletag timeout: 120_000

  @image "hippy-cups-test"
  @context Path.expand("cups", __DIR__)
  @credentials "hippy:hippy-pass"
  @tls [connect_options: [transport_opts: [verify: :verify_none]]]
  @anonymous [req_options: @tls]
  @admin [req_options: @tls ++ [auth: {:basic, "hippy-admin:admin-pass"}]]
  @user [req_options: @tls ++ [auth: {:basic, @credentials}]]

  setup_all do
    {_, 0} = docker(["build", "-q", "-t", @image, @context])
    name = "hippy-cups-#{System.unique_integer([:positive])}"
    {_, 0} = docker(["run", "-d", "--rm", "--name", name, "-p", "127.0.0.1::631", @image])
    on_exit(fn -> docker(["rm", "-f", name]) end)

    wait_until_ready(name)
    {port, 0} = docker(["port", name, "631/tcp"])
    port = port |> String.trim() |> String.split(":") |> List.last()

    %{container: name, http: "http://localhost:#{port}", https: "https://localhost:#{port}"}
  end

  setup do
    # Bypass the Req.Test plug configured for unit tests.
    previous = Application.fetch_env(:hippy, :req_options)
    Application.put_env(:hippy, :req_options, [])

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:hippy, :req_options, value)
        :error -> Application.delete_env(:hippy, :req_options)
      end
    end)
  end

  describe "Get-Printer-Attributes" do
    test "decodes every queue", %{http: http} do
      for {queue, state, accepting} <- [
            {"raw", :idle, true},
            {"filtered", :idle, true},
            {"held_jobs", :stopped, true},
            {"rejecting", :idle, false}
          ] do
        res = send!(GetPrinterAttributes.new(printer(http, queue)))
        attrs = Response.printer(res)

        assert res.status_code == :successful_ok
        assert map_size(attrs) > 50
        assert attrs["printer-state"] == state
        assert attrs["printer-is-accepting-jobs"] == accepting
        assert attrs["printer-type"] |> List.wrap() |> Enum.all?(&is_binary/1)
        assert :portrait in attrs["orientation-requested-supported"]

        # Every enum value CUPS sends is one Hippy knows.
        [printer] = res.printer_attributes

        for {:enum, name, value} <- printer, v <- List.wrap(value) do
          refute is_integer(v), "#{name} has an undecoded value #{v}"
        end
      end
    end

    test "accepts an ipp:// printer URI", %{http: http} do
      uri = String.replace(printer(http, "raw"), "http://", "ipp://")
      assert send!(GetPrinterAttributes.new(uri)).status_code == :successful_ok
    end

    test "missing queue returns not found", %{http: http} do
      res = send!(GetPrinterAttributes.new(printer(http, "missing")))
      assert res.status_code == :client_error_not_found
    end

    test "handles concurrent requests", %{http: http} do
      statuses =
        1..25
        |> Task.async_stream(
          fn _ -> send!(GetPrinterAttributes.new(printer(http, "raw"))).status_code end,
          max_concurrency: 25
        )
        |> Enum.map(fn {:ok, status} -> status end)

      assert Enum.all?(statuses, &(&1 == :successful_ok))
    end
  end

  describe "CUPS server operations" do
    @queues ~w(filtered held_cancel held_jobs raw rejecting secure)

    defp names(res), do: Enum.map(Response.printers(res), & &1["printer-name"])

    test "CUPS-Get-Printers returns each printer and class separately", %{http: http} do
      res =
        send!(
          CupsGetPrinters.new("#{http}/", requested_attributes: ["printer-name", "printer-state"])
        )

      states = Map.new(Response.printers(res), &{&1["printer-name"], &1["printer-state"]})

      assert res.status_code == :successful_ok
      assert names(res) == Enum.sort(["raw_class" | @queues])
      assert states["held_jobs"] == :stopped
      assert states["raw"] == :idle
    end

    test "CUPS-Get-Printers filters by type, and pages with limit and first-printer-name", ctx do
      op = &CupsGetPrinters.new("#{ctx.http}/", [requested_attributes: ["printer-name"]] ++ &1)

      assert names(send!(op.(printer_type: 0, printer_type_mask: 1))) == @queues
      assert names(send!(op.(printer_type: 1, printer_type_mask: 1))) == ["raw_class"]
      assert names(send!(op.(limit: 2))) == ["filtered", "held_cancel"]
      assert names(send!(op.(first_printer_name: "raw", limit: 2))) == ["raw", "raw_class"]
    end

    test "CUPS-Get-Classes returns classes and their members", %{http: http} do
      res = send!(CupsGetClasses.new("#{http}/"))

      assert [%{"printer-name" => "raw_class", "member-names" => ["raw", "filtered"]}] =
               Response.printers(res)
    end

    test "CUPS-Get-Default returns the default printer", %{http: http} do
      res = send!(CupsGetDefault.new("#{http}/", requested_attributes: ["printer-name"]))
      assert Response.printer(res) == %{"printer-name" => "raw"}
    end
  end

  describe "attribute groups in requests" do
    defp base_attributes,
      do: [
        {:charset, "attributes-charset", "utf-8"},
        {:natural_language, "attributes-natural-language", "en"}
      ]

    test "CUPS-Add-Modify-Printer creates a queue from a printer group, as an administrator",
         ctx do
      name = "created_#{System.unique_integer([:positive])}"
      on_exit(fn -> docker(["exec", ctx.container, "lpadmin", "-x", name]) end)

      req = %Hippy.Request{
        operation_id: Hippy.IPP.Operation.cups_add_modify_printer(),
        operation_attributes:
          base_attributes() ++ [{:uri, "printer-uri", "ipp://localhost/printers/#{name}"}],
        groups: [
          {:printer_attributes,
           [
             {:uri, "device-uri", "file:///dev/null"},
             {:text_without_language, "printer-location", "Front desk"},
             {:text_without_language, "printer-info", "Made by Hippy"},
             {:boolean, "printer-is-accepting-jobs", true},
             {:enum, "printer-state", 3}
           ]}
        ]
      }

      admin = "#{ctx.https}/admin/"

      assert {:error, {:http_error, 401, _}} = Hippy.Server.send_request(req, admin, @anonymous)
      assert {:ok, %{status_code: :successful_ok}} = Hippy.Server.send_request(req, admin, @admin)

      attrs = Response.printer(send!(GetPrinterAttributes.new(printer(ctx.http, name))))
      assert attrs["printer-location"] == "Front desk"
      assert attrs["printer-info"] == "Made by Hippy"
      assert attrs["printer-is-accepting-jobs"] == true
      assert attrs["device-uri"] == URI.parse("file:///dev/null")
    end

    test "Create-Printer-Subscriptions creates one subscription per group", %{http: http} do
      subscription = fn events ->
        {:subscription_attributes,
         [{:keyword, "notify-pull-method", "ippget"}, {:keyword, "notify-events", events}]}
      end

      uri = printer(http, "raw")

      req = %Hippy.Request{
        operation_id: Hippy.IPP.Operation.create_printer_subscription(),
        operation_attributes:
          base_attributes() ++ [{:uri, "printer-uri", String.replace(uri, "http", "ipp")}],
        groups: [subscription.(["printer-state-changed"]), subscription.(["job-completed"])]
      }

      {:ok, res} = Hippy.Server.send_request(req, uri)
      assert res.status_code == :successful_ok

      ids =
        Enum.map(
          res.subscription_attributes,
          &AttributeGroup.to_map(&1)["notify-subscription-id"]
        )

      assert length(ids) == 2 and Enum.all?(ids, &is_integer/1)

      # Each subscription got its own group's events.
      list = %Hippy.Request{
        operation_id: Hippy.IPP.Operation.get_subscriptions(),
        operation_attributes:
          base_attributes() ++
            [
              {:uri, "printer-uri", String.replace(uri, "http", "ipp")},
              {{:set1, :keyword}, "requested-attributes",
               ["notify-subscription-id", "notify-events"]}
            ]
      }

      {:ok, res} = Hippy.Server.send_request(list, uri)

      events =
        Map.new(res.subscription_attributes, fn group ->
          map = AttributeGroup.to_map(group)
          {map["notify-subscription-id"], map["notify-events"]}
        end)

      assert events[Enum.at(ids, 0)] == "printer-state-changed"
      assert events[Enum.at(ids, 1)] == "job-completed"
    end

    test "Print-Job with a subscription group subscribes to the job", %{http: http} do
      op =
        PrintJob.new(printer(http, "raw"), pdf(),
          groups: [
            {:subscription_attributes,
             [
               {:keyword, "notify-pull-method", "ippget"},
               {:keyword, "notify-events", "job-completed"}
             ]}
          ]
        )

      res = send!(op)
      assert res.status_code == :successful_ok
      assert [[{:integer, "notify-subscription-id", id}]] = res.subscription_attributes
      assert is_integer(id)
    end
  end

  describe "Print-Job" do
    test "PDF goes through the filter pipeline with job attributes applied", ctx do
      uri = printer(ctx.http, "filtered")

      op =
        PrintJob.new(uri, pdf(), job_name: "Hippy PDF ✓", orientation: Orientation.landscape())

      id = print!(op)
      assert wait_for_state(uri, id) == :completed

      attrs = job_attributes!(uri, id)
      assert attrs["job-name"] == "Hippy PDF ✓"
      assert attrs["orientation-requested"] == :landscape
      assert attrs["job-sheets"] == ["none", "none"]

      # orientation-requested=4 (landscape) was handed to the CUPS filters. CUPS also accepts
      # job attributes sent in the operation group, so correct grouping is covered by
      # Hippy.EncoderTest rather than here.
      log = container_exec(ctx.container, ["cat", "/var/log/cups/error_log"])
      assert log =~ ~r/\[Job #{id}\] argv\[5\]="orientation-requested=4/
      assert container_exec(ctx.container, ["head", "-c", "4", "/spool/filtered.ps"]) == "%!PS"
    end

    test "document format and extra job attributes reach the filters", ctx do
      uri = printer(ctx.http, "filtered")
      a4 = %{"x-dimension" => {:integer, 21000}, "y-dimension" => {:integer, 29700}}

      op =
        PrintJob.new(uri, pdf(),
          document_format: "application/pdf",
          job_attributes: [
            {:integer, "copies", 2},
            {:keyword, "sides", "two-sided-long-edge"},
            {:collection, "media-col", %{"media-size" => {:collection, a4}}},
            {:enum, "orientation-requested", Orientation.landscape()}
          ]
        )

      id = print!(op)
      assert wait_for_state(uri, id) == :completed

      attrs = job_attributes!(uri, id)
      assert attrs["document-format"] == "application/pdf"
      assert attrs["copies"] == 2
      assert attrs["sides"] == "two-sided-long-edge"
      assert attrs["orientation-requested"] == :landscape

      # CUPS converts media-col to a media size for the filters.
      log = container_exec(ctx.container, ["cat", "/var/log/cups/error_log"])
      [options] = Regex.run(~r/\[Job #{id}\] argv\[5\]="([^"]*)"/, log, capture: :all_but_first)
      assert options =~ "media=A4"
      assert options =~ "sides=two-sided-long-edge"
      assert options =~ "orientation-requested=4"
    end

    test "unsupported document format is reported", %{http: http} do
      res =
        send!(PrintJob.new(printer(http, "raw"), pdf(), document_format: "application/x-nope"))

      assert res.status_code == :client_error_document_format_not_supported

      assert Response.unsupported(res) == %{"document-format" => "application/x-nope"}
    end

    test "plain text is auto-typed and converted by CUPS", %{http: http} do
      uri = printer(http, "filtered")
      id = print!(PrintJob.new(uri, "Hello from Hippy\n", job_name: "Hippy text"))
      assert wait_for_state(uri, id) == :completed
    end

    test "large documents", %{http: http} do
      uri = printer(http, "raw")
      id = print!(PrintJob.new(uri, :crypto.strong_rand_bytes(25 * 1024 * 1024)))
      assert wait_for_state(uri, id) == :completed
    end

    test "queue rejecting jobs returns not accepting jobs", %{http: http} do
      res = send!(PrintJob.new(printer(http, "rejecting"), pdf()))
      assert res.status_code == :server_error_not_accepting_jobs
    end
  end

  describe "Get-Jobs and Get-Job-Attributes" do
    test "which_jobs filters pending jobs", %{http: http} do
      uri = printer(http, "held_jobs")
      ids = for n <- 1..2, do: print!(PrintJob.new(uri, pdf(), job_name: "Held #{n}"))

      assert Enum.map(ids, &job_attributes!(uri, &1)["job-state"]) == [:pending, :pending]
      assert job_ids(uri, :not_completed) == ids
      assert job_ids(uri, :completed) == []
      assert job_ids(uri, :all) == ids
    end

    test "missing job returns not found", %{http: http} do
      res = send!(GetJobAttributes.new(printer(http, "raw"), 99_999))
      assert res.status_code == :client_error_not_found
    end
  end

  describe "Cancel-Job with the default CUPS policy" do
    test "anonymous cancel over plain HTTP requires an upgrade to TLS", %{http: http} do
      uri = printer(http, "held_cancel")
      id = print!(PrintJob.new(uri, pdf()))

      assert {:error, {:http_error, 426, _}} = Hippy.send_operation(CancelJob.new(uri, id))
    end

    test "anonymous cancel over HTTPS requires authentication", ctx do
      id = print!(PrintJob.new(printer(ctx.http, "held_cancel"), pdf()))
      op = CancelJob.new(printer(ctx.https, "held_cancel"), id)

      assert {:error, {:http_error, 401, _}} = Hippy.send_operation(op, @anonymous)
    end

    test "authenticated user can cancel only their own jobs", ctx do
      anonymous_id = print!(PrintJob.new(printer(ctx.http, "held_cancel"), pdf()))
      uri = printer(ctx.https, "held_cancel")

      assert {:error, {:http_error, 403, _}} =
               Hippy.send_operation(CancelJob.new(uri, anonymous_id), @user)

      id = print!(PrintJob.new(uri, pdf(), job_name: "Mine"), @user)
      assert job_attributes!(uri, id, @user)["job-originating-user-name"] == "hippy"

      assert send!(CancelJob.new(uri, id), @user).status_code == :successful_ok
      assert job_attributes!(uri, id, @user)["job-state"] == :canceled
      assert send!(CancelJob.new(uri, id), @user).status_code == :client_error_not_possible
    end
  end

  describe "authentication and transport" do
    test "Basic auth over HTTPS", %{https: https} do
      op = GetPrinterAttributes.new(printer(https, "secure"))
      wrong = [req_options: @tls ++ [auth: {:basic, "hippy:wrong"}]]

      assert {:error, {:http_error, 401, _}} = Hippy.send_operation(op, @anonymous)
      assert {:error, {:http_error, 401, _}} = Hippy.send_operation(op, wrong)
      assert send!(op, @user).status_code == :successful_ok
      assert is_integer(print!(PrintJob.new(op.printer_uri, pdf()), @user))
    end

    test "concurrent requests use their own credentials", %{https: https} do
      op = GetPrinterAttributes.new(printer(https, "secure"))

      results =
        1..20
        |> Enum.map(fn n -> if rem(n, 2) == 0, do: @user, else: @anonymous end)
        |> Task.async_stream(&{&1, Hippy.send_operation(op, &1)}, max_concurrency: 20)
        |> Enum.map(fn {:ok, result} -> result end)

      for {opts, result} <- results do
        if opts == @user do
          assert {:ok, %Hippy.Response{status_code: :successful_ok}} = result
        else
          assert {:error, {:http_error, 401, _}} = result
        end
      end
    end

    test "ipps:// printer URI", %{https: https} do
      uri = String.replace(printer(https, "secure"), "https://", "ipps://")

      assert send!(GetPrinterAttributes.new(uri), @user).status_code == :successful_ok
    end

    test "self-signed certificate is rejected when verification is on", %{https: https} do
      capture_log(fn ->
        assert {:error, %Req.TransportError{reason: {:tls_alert, _}}} =
                 Hippy.send_operation(GetPrinterAttributes.new(printer(https, "raw")))
      end)
    end

    test "a pinned self-signed certificate is accepted (as in the README)", ctx do
      op = GetPrinterAttributes.new(printer(ctx.https, "raw"))

      # CUPS creates its certificate on the first HTTPS connection, which may not have happened
      # yet depending on test order.
      send!(op, @anonymous)
      pem = container_exec(ctx.container, ["sh", "-c", "cat /etc/cups/ssl/*.crt"])
      [{:Certificate, pinned, _}] = :public_key.pem_decode(pem)

      # Erlang never trusts a self-signed server certificate through cacerts.
      capture_log(fn ->
        assert {:error, %Req.TransportError{reason: {:tls_alert, {:bad_certificate, msg}}}} =
                 Hippy.send_operation(op, tls_options(cacerts: [pinned]))

        assert to_string(msg) =~ "selfsigned_peer"
      end)

      assert send!(op, tls_options(verify_fun: {pinning_verify_fun(pinned), nil})).status_code ==
               :successful_ok

      capture_log(fn ->
        assert {:error, %Req.TransportError{reason: {:tls_alert, _}}} =
                 Hippy.send_operation(
                   op,
                   tls_options(verify_fun: {pinning_verify_fun(<<"other">>), nil})
                 )
      end)
    end

    test "receive timeout surfaces as a transport error", %{http: http} do
      op = PrintJob.new(printer(http, "raw"), :crypto.strong_rand_bytes(25 * 1024 * 1024))

      assert {:error, %Req.TransportError{reason: :timeout}} =
               Hippy.send_operation(op, req_options: [receive_timeout: 1])
    end
  end

  # Helpers

  defp docker(args), do: System.cmd("docker", args, stderr_to_stdout: true)

  defp container_exec(container, cmd) do
    {out, 0} = docker(["exec", container | cmd])
    out
  end

  defp wait_until_ready(name, attempts \\ 300) do
    {logs, _} = docker(["logs", name])

    cond do
      logs =~ "READY" -> :ok
      attempts == 0 -> flunk("CUPS container did not become ready:\n#{logs}")
      true -> Process.sleep(100) && wait_until_ready(name, attempts - 1)
    end
  end

  defp printer(base, queue), do: "#{base}/printers/#{queue}"

  defp tls_options(transport_opts),
    do: [req_options: [connect_options: [transport_opts: transport_opts]]]

  # Same as the README's "Self-signed certificates" example.
  defp pinning_verify_fun(pinned) do
    fn
      cert, {:bad_cert, :selfsigned_peer}, state ->
        if :public_key.pkix_encode(:OTPCertificate, cert, :otp) == pinned,
          do: {:valid, state},
          else: {:fail, :selfsigned_peer}

      _cert, {:bad_cert, _} = reason, _state ->
        {:fail, reason}

      _cert, {:extension, _}, state ->
        {:unknown, state}

      _cert, _valid, state ->
        {:valid, state}
    end
  end

  defp send!(op, opts \\ []) do
    {:ok, %Hippy.Response{} = res} = Hippy.send_operation(op, opts)
    res
  end

  defp print!(op, opts \\ []) do
    res = send!(op, opts)
    assert res.status_code == :successful_ok
    Response.job(res)["job-id"]
  end

  defp job_attributes!(uri, id, opts \\ []) do
    Response.job(send!(GetJobAttributes.new(uri, id), opts))
  end

  defp job_ids(uri, which) do
    send!(GetJobs.new(uri, which_jobs: which))
    |> Response.jobs()
    |> Enum.map(& &1["job-id"])
    |> Enum.sort()
  end

  defp wait_for_state(uri, id, attempts \\ 100) do
    state = job_attributes!(uri, id)["job-state"]

    cond do
      state in [:completed, :canceled, :aborted] -> state
      attempts == 0 -> state
      true -> Process.sleep(100) && wait_for_state(uri, id, attempts - 1)
    end
  end

  # A minimal one-page PDF, built here so no binary fixture is needed.
  defp pdf do
    content = "BT /F1 24 Tf 72 720 Td (Hello from Hippy) Tj ET"

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R " <>
        "/Resources << /Font << /F1 5 0 R >> >> >>",
      "<< /Length #{byte_size(content)} >>\nstream\n#{content}\nendstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]

    {body, offsets} =
      objects
      |> Enum.with_index(1)
      |> Enum.reduce({"%PDF-1.4\n", []}, fn {obj, n}, {acc, offsets} ->
        {acc <> "#{n} 0 obj\n#{obj}\nendobj\n", [byte_size(acc) | offsets]}
      end)

    xref =
      offsets
      |> Enum.reverse()
      |> Enum.map_join(fn offset ->
        String.pad_leading(Integer.to_string(offset), 10, "0") <> " 00000 n \n"
      end)

    count = length(objects) + 1

    body <>
      "xref\n0 #{count}\n0000000000 65535 f \n" <>
      xref <>
      "trailer\n<< /Size #{count} /Root 1 0 R >>\nstartxref\n#{byte_size(body)}\n%%EOF\n"
  end
end
