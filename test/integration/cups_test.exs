defmodule Hippy.Integration.CupsTest do
  @moduledoc """
  End-to-end tests against a real CUPS server running in Docker.

  Excluded by default. Run with `mix test --only cups` (requires a running Docker daemon).
  A fresh container is started for each run and removed afterwards.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias Hippy.Message

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

    {_, 0} =
      docker([
        "run",
        "-d",
        "--rm",
        "--name",
        name,
        "-p",
        "127.0.0.1::631",
        "-p",
        "127.0.0.1::8631",
        @image
      ])

    on_exit(fn -> docker(["rm", "-f", name]) end)

    wait_until_ready(name)

    port = fn container_port ->
      {port, 0} = docker(["port", name, "#{container_port}/tcp"])
      port |> String.trim() |> String.split(":") |> List.last()
    end

    %{
      container: name,
      http: "http://localhost:#{port.(631)}",
      https: "https://localhost:#{port.(631)}",
      # An emulated driverless printer, as at home.
      home: "ipp://localhost:#{port.(8631)}/ipp/print"
    }
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
        res = printer(http, queue) |> GetPrinterAttributes.new() |> send!()
        attrs = Message.printer(res)

        assert Message.status(res) == :successful_ok
        assert map_size(attrs) > 50
        assert attrs["printer-state"] == state
        assert attrs["printer-is-accepting-jobs"] == accepting
        assert attrs["printer-type"] |> List.wrap() |> Enum.all?(&is_binary/1)
        assert :portrait in attrs["orientation-requested-supported"]

        # Every enum value CUPS sends is one Hippy knows.
        {:printer, printer} = List.keyfind(res.groups, :printer, 0)

        for {name, values} <- printer, {:enum, value} <- values do
          assert {:ok, _} = Hippy.IPP.Enum.decode(name, value),
                 "#{name} has an unknown value #{value}"
        end
      end
    end

    test "responses decode exactly and re-encode to the same bytes", %{http: http} do
      for queue <- ["raw", "filtered", "held_jobs"] do
        uri = printer(http, queue)

        body =
          GetPrinterAttributes.new(uri)
          |> Hippy.Operation.build_request()
          |> Map.put(:request_id, 1)
          |> Hippy.Encoder.encode()

        %Req.Response{status: 200, body: bin} =
          Req.post!(uri,
            body: body,
            headers: [{"content-type", "application/ipp"}],
            decode_body: false
          )

        assert bin |> Message.decode() |> Message.encode() == bin, "#{queue} didn't round-trip"
      end

      res = printer(http, "raw") |> GetPrinterAttributes.new() |> send!()
      assert res.code == 0
      {:printer, printer} = List.keyfind(res.groups, :printer, 0)
      assert {"printer-state", [enum: 3]} in printer
    end

    test "accepts an ipp:// printer URI", %{http: http} do
      uri = String.replace(printer(http, "raw"), "http://", "ipp://")
      assert uri |> GetPrinterAttributes.new() |> send!() |> Message.status() == :successful_ok
    end

    test "missing queue returns not found", %{http: http} do
      error = printer(http, "missing") |> GetPrinterAttributes.new() |> ipp_error!()
      assert error.status == :client_error_not_found
      assert error.message =~ "does not exist"
    end

    test "handles concurrent requests", %{http: http} do
      statuses =
        1..25
        |> Task.async_stream(
          fn _ ->
            printer(http, "raw") |> GetPrinterAttributes.new() |> send!() |> Message.status()
          end,
          max_concurrency: 25
        )
        |> Enum.map(fn {:ok, status} -> status end)

      assert Enum.all?(statuses, &(&1 == :successful_ok))
    end
  end

  # The examples in the README's "What you can do with it" section.
  describe "README examples" do
    test "fleet status reports printers that need attention", %{http: http} do
      fleet = [
        printer(http, "raw"),
        printer(http, "held_jobs"),
        printer(http, "rejecting"),
        printer(http, "missing"),
        "ipp://localhost:1/printers/unplugged"
      ]

      output =
        capture_io(fn ->
          fleet
          |> Hippy.ReadmeFleet.status()
          |> Enum.each(fn
            {_uri,
             {:ok,
              %{
                "printer-state" => :idle,
                "printer-state-reasons" => ["none"],
                "printer-is-accepting-jobs" => true
              }}} ->
              :ok

            {uri, {:ok, printer}} ->
              IO.puts(
                "#{uri}: #{printer["printer-state"]} " <>
                  "(#{Enum.join(printer["printer-state-reasons"], ", ")})"
              )

            {uri, {:error, error}} ->
              IO.puts("#{uri}: #{Exception.message(error)}")
          end)
        end)

      assert output =~ "/printers/held_jobs: stopped (paused)"
      assert output =~ "/printers/rejecting: idle (none)"
      assert output =~ "/printers/missing: IPP error client_error_not_found"
      assert output =~ "/printers/unplugged: connection refused"
      refute output =~ "/printers/raw:"
    end

    test "Hippy.printer_ready? on real printers", %{http: http} do
      ready =
        for queue <- ["raw", "held_jobs", "rejecting"], into: %{} do
          printer =
            http
            |> printer(queue)
            |> GetPrinterAttributes.new(
              requested_attributes: [
                "printer-state",
                "printer-state-reasons",
                "printer-is-accepting-jobs"
              ]
            )
            |> send!()
            |> Message.printer()

          {queue, Hippy.printer_ready?(printer)}
        end

      assert ready == %{"raw" => true, "held_jobs" => false, "rejecting" => false}
    end

    test "Hippy.safe_to_resend? on real errors", ctx do
      error = fn op, opts ->
        {:error, error} = Hippy.send_operation(op, opts)
        error
      end

      # An IPP error, an HTTP error and a refused connection: nothing was printed.
      assert Hippy.safe_to_resend?(
               printer(ctx.http, "rejecting")
               |> PrintJob.new(pdf())
               |> error.([])
             )

      assert Hippy.safe_to_resend?(
               printer(ctx.https, "secure")
               |> GetPrinterAttributes.new()
               |> error.(@anonymous)
             )

      assert Hippy.safe_to_resend?(
               PrintJob.new("ipp://localhost:1/printers/p", pdf())
               |> error.([])
             )

      # A timeout after sending: it may have printed.
      big = :crypto.strong_rand_bytes(25 * 1024 * 1024)

      refute Hippy.safe_to_resend?(
               printer(ctx.http, "raw")
               |> PrintJob.new(big)
               |> error.(req_options: [receive_timeout: 1])
             )
    end

    test "fleet print sends the job to an available printer", %{http: http} do
      fleet = [printer(http, "rejecting"), printer(http, "held_jobs"), printer(http, "raw")]

      assert {:ok, uri, job_id} = Hippy.ReadmeFleet.print(fleet, pdf())
      assert uri == printer(http, "raw")
      assert is_integer(job_id)

      assert Hippy.ReadmeFleet.print(Enum.take(fleet, 2), pdf()) ==
               {:error, :no_printer_available}
    end

    test "print and wait", %{http: http} do
      assert {:completed, job_id} =
               Hippy.ReadmePrinting.print_and_wait(
                 printer(http, "filtered"),
                 "Hello from Hippy\n"
               )

      assert is_integer(job_id)
    end
  end

  describe "CUPS server operations" do
    @queues ~w(filtered held_cancel held_jobs raw rejecting secure)

    defp names(res), do: Enum.map(Message.printers(res), & &1["printer-name"])

    test "CUPS-Get-Printers returns each printer and class separately", %{http: http} do
      res =
        CupsGetPrinters.new("#{http}/", requested_attributes: ["printer-name", "printer-state"])
        |> send!()

      states = Message.printers(res) |> Map.new(&{&1["printer-name"], &1["printer-state"]})

      assert Message.status(res) == :successful_ok
      assert names(res) == Enum.sort(["raw_class" | @queues])
      assert states["held_jobs"] == :stopped
      assert states["raw"] == :idle
    end

    test "CUPS-Get-Printers filters by type, and pages with limit and first-printer-name", ctx do
      op = &CupsGetPrinters.new("#{ctx.http}/", [requested_attributes: ["printer-name"]] ++ &1)

      assert names(op.(printer_type: 0, printer_type_mask: 1) |> send!()) == @queues
      assert names(op.(printer_type: 1, printer_type_mask: 1) |> send!()) == ["raw_class"]
      assert names(op.(limit: 2) |> send!()) == ["filtered", "held_cancel"]
      assert names(op.(first_printer_name: "raw", limit: 2) |> send!()) == ["raw", "raw_class"]
    end

    test "CUPS-Get-Classes returns classes and their members", %{http: http} do
      res = CupsGetClasses.new("#{http}/") |> send!()

      assert [%{"printer-name" => "raw_class", "member-names" => ["raw", "filtered"]}] =
               Message.printers(res)
    end

    test "CUPS-Get-Default returns the default printer", %{http: http} do
      res = CupsGetDefault.new("#{http}/", requested_attributes: ["printer-name"]) |> send!()
      assert Message.printer(res) == %{"printer-name" => "raw"}
    end
  end

  describe "attribute groups in requests" do
    @base %{charset: "utf-8", language: "en"}

    test "CUPS-Add-Modify-Printer creates a queue from a printer group, as an administrator",
         ctx do
      name = "created_#{System.unique_integer([:positive])}"
      on_exit(fn -> docker(["exec", ctx.container, "lpadmin", "-x", name]) end)

      req =
        Hippy.IPP.Operation.cups_add_modify_printer()
        |> Message.build_request(
          @base,
          [{:uri, "printer-uri", "ipp://localhost/printers/#{name}"}],
          groups: [
            {:printer,
             [
               {:uri, "device-uri", "file:///dev/null"},
               {:text_without_language, "printer-location", "Front desk"},
               {:text_without_language, "printer-info", "Made by Hippy"},
               {:boolean, "printer-is-accepting-jobs", true},
               {:enum, "printer-state", 3}
             ]}
          ]
        )

      admin = "#{ctx.https}/admin/"

      assert {:error, %Hippy.HTTPError{status: 401}} =
               Hippy.send_message(req, admin, @anonymous)

      assert {:ok, %Message{code: 0}} = Hippy.send_message(req, admin, @admin)

      attrs =
        printer(ctx.http, name) |> GetPrinterAttributes.new() |> send!() |> Message.printer()

      assert attrs["printer-location"] == "Front desk"
      assert attrs["printer-info"] == "Made by Hippy"
      assert attrs["printer-is-accepting-jobs"] == true
      assert attrs["device-uri"] == URI.parse("file:///dev/null")
    end

    test "inferred printer attributes create a queue with CUPS-Add-Modify-Printer", ctx do
      name = "inferred_#{System.unique_integer([:positive])}"
      on_exit(fn -> docker(["exec", ctx.container, "lpadmin", "-x", name]) end)

      # The operation decides where printer-location goes: here, the printer group.
      op = %{
        charset: "utf-8",
        language: "en",
        printer_uri: "ipp://localhost/printers/#{name}",
        attributes: %{
          # CUPS's own attribute, so it needs its syntax.
          "device-uri" => {:uri, "file:///dev/null"},
          "printer-location" => "Back office",
          "printer-info" => "Inferred by Hippy"
        }
      }

      req = Hippy.IPP.Operation.cups_add_modify_printer() |> Message.build_request(op)
      assert Enum.map(req.groups, &elem(&1, 0)) == [:operation, :printer]

      assert {:ok, %Message{code: 0}} =
               Hippy.send_message(req, "#{ctx.https}/admin/", @admin)

      attrs =
        printer(ctx.http, name) |> GetPrinterAttributes.new() |> send!() |> Message.printer()

      assert attrs["printer-location"] == "Back office"
      assert attrs["printer-info"] == "Inferred by Hippy"
      assert attrs["device-uri"] == URI.parse("file:///dev/null")
    end

    test "Create-Printer-Subscriptions creates one subscription per group", %{http: http} do
      subscription = fn events ->
        {:subscription,
         [{:keyword, "notify-pull-method", "ippget"}, {:keyword, "notify-events", events}]}
      end

      uri = printer(http, "raw")

      req =
        Hippy.IPP.Operation.create_printer_subscription()
        |> Message.build_request(Map.put(@base, :printer_uri, uri), [],
          groups: [subscription.(["printer-state-changed"]), subscription.(["job-completed"])]
        )

      {:ok, res} = Hippy.send_message(req, uri)
      assert Message.status(res) == :successful_ok

      ids = res |> Message.groups(:subscription) |> Enum.map(& &1["notify-subscription-id"])

      assert length(ids) == 2 and Enum.all?(ids, &is_integer/1)

      # Each subscription got its own group's events.
      list =
        Hippy.IPP.Operation.get_subscriptions()
        |> Message.build_request(Map.put(@base, :printer_uri, uri), [
          {{:set1, :keyword}, "requested-attributes", ["notify-subscription-id", "notify-events"]}
        ])

      {:ok, res} = Hippy.send_message(list, uri)

      events =
        res
        |> Message.groups(:subscription)
        |> Map.new(&{&1["notify-subscription-id"], &1["notify-events"]})

      assert events[Enum.at(ids, 0)] == ["printer-state-changed"]
      assert events[Enum.at(ids, 1)] == ["job-completed"]
    end

    test "Print-Job with a subscription group subscribes to the job", %{http: http} do
      op =
        printer(http, "raw")
        |> PrintJob.new(pdf(),
          groups: [
            {:subscription,
             [
               {:keyword, "notify-pull-method", "ippget"},
               {:keyword, "notify-events", "job-completed"}
             ]}
          ]
        )

      res = send!(op)
      assert Message.status(res) == :successful_ok
      assert [%{"notify-subscription-id" => id}] = Message.groups(res, :subscription)
      assert is_integer(id)
    end
  end

  describe "Hippy.send_operation/4" do
    test "Validate-Job checks attributes without printing", %{http: http} do
      uri = printer(http, "raw")

      {:ok, res} =
        Hippy.send_operation(uri, :validate_job, %{
          "document-format" => "application/pdf",
          "copies" => 2
        })

      assert Message.status(res) == :successful_ok

      {:error, error} =
        Hippy.send_operation(uri, :validate_job, %{"document-format" => "application/x-nope"})

      assert error.status == :client_error_document_format_not_supported
    end

    test "Print-Job, then job operations by job URI, as the job's owner", %{https: https} do
      {:ok, res} =
        printer(https, "held_cancel")
        |> Hippy.send_operation(
          :print_job,
          %{"job-name" => "By request"},
          [document: pdf()] ++ @user
        )

      assert Message.status(res) == :successful_ok

      # CUPS's job-uri names its own host, so address the job through the test's port.
      job_uri = "#{https}/jobs/#{Message.job(res)["job-id"]}"

      state = fn ->
        {:ok, res} = Hippy.send_operation(job_uri, :get_job_attributes, %{}, @user)
        Message.job(res)["job-state"]
      end

      assert state.() == :pending

      {:ok, res} = Hippy.send_operation(job_uri, :hold_job, %{}, @user)
      assert Message.status(res) == :successful_ok
      assert state.() == :pending_held

      {:ok, res} = Hippy.send_operation(job_uri, :release_job, %{}, @user)
      assert Message.status(res) == :successful_ok
      assert state.() == :pending

      {:ok, res} = Hippy.send_operation(job_uri, :cancel_job, %{}, @user)
      assert Message.status(res) == :successful_ok
      assert state.() == :canceled
    end

    test "CUPS server operations", %{http: http} do
      {:ok, res} =
        Hippy.send_operation("#{http}/", :cups_get_printers, %{
          "requested-attributes" => ["printer-name"]
        })

      assert "raw" in Enum.map(Message.printers(res), & &1["printer-name"])

      {:ok, res} =
        Hippy.send_operation("#{http}/", :cups_get_default, %{
          "requested-attributes" => ["printer-name"]
        })

      assert Message.printer(res)["printer-name"] == "raw"
    end

    test "administration: add, pause, resume and delete a printer", ctx do
      name = "requested_#{System.unique_integer([:positive])}"
      on_exit(fn -> docker(["exec", ctx.container, "lpadmin", "-x", name]) end)

      admin = [endpoint: "#{ctx.https}/admin/"] ++ @admin
      printer_uri = "ipp://localhost/printers/#{name}"
      queue = printer(ctx.https, name)

      printer_state = fn ->
        printer(ctx.http, name)
        |> GetPrinterAttributes.new()
        |> send!()
        |> Message.printer()
        |> Map.get("printer-state")
      end

      {:ok, res} =
        Hippy.send_operation(
          queue,
          :cups_add_modify_printer,
          %{
            "printer-uri" => printer_uri,
            "device-uri" => {:uri, "file:///dev/null"},
            "printer-info" => "Made by Hippy.send_operation"
          },
          admin
        )

      assert Message.status(res) == :successful_ok

      assert printer(ctx.http, name)
             |> GetPrinterAttributes.new()
             |> send!()
             |> Message.printer()
             |> Map.get("printer-info") == "Made by Hippy.send_operation"

      {:ok, %Message{code: 0}} =
        Hippy.send_operation(queue, :pause_printer, %{}, @admin)

      assert printer_state.() == :stopped

      {:ok, %Message{code: 0}} =
        Hippy.send_operation(queue, :resume_printer, %{}, @admin)

      assert printer_state.() == :idle

      {:ok, %Message{code: 0}} =
        Hippy.send_operation(queue, :cups_delete_printer, %{"printer-uri" => printer_uri}, admin)

      error = printer(ctx.http, name) |> GetPrinterAttributes.new() |> ipp_error!()
      assert error.status == :client_error_not_found
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

    test "attributes given as plain names and values", ctx do
      uri = printer(ctx.http, "filtered")
      a4 = %{"x-dimension" => 21000, "y-dimension" => 29700}

      op =
        PrintJob.new(uri, pdf(),
          attributes: %{
            "job-name" => "Inferred",
            "document-format" => "application/pdf",
            "copies" => 2,
            "sides" => "two-sided-long-edge",
            "media-col" => %{"media-size" => a4},
            "orientation-requested" => :landscape
          }
        )

      id = print!(op)
      assert wait_for_state(uri, id) == :completed

      attrs = job_attributes!(uri, id)
      assert attrs["job-name"] == "Inferred"
      assert attrs["document-format"] == "application/pdf"
      assert attrs["copies"] == 2
      assert attrs["sides"] == "two-sided-long-edge"
      assert attrs["orientation-requested"] == :landscape

      log = container_exec(ctx.container, ["cat", "/var/log/cups/error_log"])
      [options] = Regex.run(~r/\[Job #{id}\] argv\[5\]="([^"]*)"/, log, capture: :all_but_first)
      assert options =~ "media=A4"
      assert options =~ "sides=two-sided-long-edge"
    end

    test "unsupported document format is reported", %{http: http} do
      error =
        printer(http, "raw")
        |> PrintJob.new(pdf(), document_format: "application/x-nope")
        |> ipp_error!()

      assert error.status == :client_error_document_format_not_supported
      res = error.response

      assert Message.unsupported(res) == %{"document-format" => "application/x-nope"}
    end

    test "plain text is auto-typed and converted by CUPS", %{http: http} do
      uri = printer(http, "filtered")
      id = PrintJob.new(uri, "Hello from Hippy\n", job_name: "Hippy text") |> print!()
      assert wait_for_state(uri, id) == :completed
    end

    test "streamed documents arrive whole", %{http: http} do
      uri = printer(http, "raw")
      chunks = Stream.repeatedly(fn -> :crypto.strong_rand_bytes(64_000) end) |> Stream.take(400)

      id = PrintJob.new(uri, chunks) |> print!()
      assert wait_for_state(uri, id) == :completed
      # 400 × 64,000 bytes.
      assert job_attributes!(uri, id)["job-k-octets"] == 25_000
    end

    @tag :tmp_dir
    test "a document streamed from a file goes through the filters",
         %{http: http, tmp_dir: dir} = ctx do
      path = Path.join(dir, "doc.pdf")
      File.write!(path, pdf())
      uri = printer(http, "filtered")

      id = PrintJob.new(uri, File.stream!(path), document_format: "application/pdf") |> print!()
      assert wait_for_state(uri, id) == :completed
      assert container_exec(ctx.container, ["head", "-c", "4", "/spool/filtered.ps"]) == "%!PS"
    end

    test "large documents", %{http: http} do
      uri = printer(http, "raw")
      id = PrintJob.new(uri, :crypto.strong_rand_bytes(25 * 1024 * 1024)) |> print!()
      assert wait_for_state(uri, id) == :completed
    end

    test "queue rejecting jobs returns not accepting jobs", %{http: http} do
      error = printer(http, "rejecting") |> PrintJob.new(pdf()) |> ipp_error!()
      assert error.status == :server_error_not_accepting_jobs
    end
  end

  describe "job and printer control" do
    test "Validate-Job checks a job without printing it", %{http: http} do
      uri = printer(http, "filtered")

      jobs = fn ->
        uri |> GetJobs.new(which_jobs: :all) |> send!() |> Message.jobs() |> length()
      end

      before = jobs.()

      assert uri
             |> ValidateJob.new(document_format: "application/pdf", attributes: %{"copies" => 2})
             |> send!()
             |> Message.status() == :successful_ok

      error =
        uri
        |> ValidateJob.new(document_format: "application/x-nope")
        |> ipp_error!()

      assert error.status == :client_error_document_format_not_supported
      assert Message.unsupported(error.response) == %{"document-format" => "application/x-nope"}
      assert jobs.() == before
    end

    test "Create-Job and Send-Document print one job made of two documents", %{https: https} do
      uri = printer(https, "raw")

      id =
        uri
        |> CreateJob.new(job_name: "Two documents", attributes: %{"copies" => 1})
        |> send!(@user)
        |> Message.job()
        |> Map.fetch!("job-id")

      assert uri
             |> SendDocument.new(id, "first", document_name: "first.txt", last_document: false)
             |> send!(@user)
             |> Message.status() == :successful_ok

      assert job_attributes!(uri, id, @user)["job-state"] in [
               :pending,
               :pending_held,
               :processing
             ]

      uri
      |> SendDocument.new(id, "second", document_format: "application/octet-stream")
      |> send!(@user)

      job = wait_for_job_state(uri, id, [:completed], @user)
      assert job["number-of-documents"] == 2
      assert job["job-name"] == "Two documents"
    end

    test "Send-Document needs the job's owner", %{http: http, https: https} do
      uri = printer(https, "raw")
      id = uri |> CreateJob.new() |> send!(@user) |> Message.job() |> Map.fetch!("job-id")

      assert {:error, %Hippy.HTTPError{status: 401}} =
               uri |> SendDocument.new(id, "doc") |> Hippy.send_operation(@anonymous)

      assert {:error, %Hippy.HTTPError{status: 426}} =
               http |> printer("raw") |> SendDocument.new(id, "doc") |> Hippy.send_operation()

      uri |> CancelJob.new(id) |> send!(@user)
    end

    test "Hold-Job and Release-Job", %{https: https} do
      uri = printer(https, "held_cancel")
      id = uri |> PrintJob.new(pdf(), job_name: "Held") |> print!(@user)

      assert uri |> HoldJob.new(id) |> send!(@user) |> Message.status() == :successful_ok
      assert job_attributes!(uri, id, @user)["job-state"] == :pending_held

      assert uri |> ReleaseJob.new(id) |> send!(@user) |> Message.status() == :successful_ok
      assert job_attributes!(uri, id, @user)["job-state"] == :pending

      uri |> CancelJob.new(id) |> send!(@user)
    end

    test "Hold-Job until a time", %{https: https} do
      uri = printer(https, "held_cancel")
      id = uri |> PrintJob.new(pdf()) |> print!(@user)

      uri |> HoldJob.new(id, attributes: %{"job-hold-until" => "night"}) |> send!(@user)
      job = job_attributes!(uri, id, @user)

      assert job["job-state"] == :pending_held
      assert job["job-hold-until"] == "night"

      uri |> CancelJob.new(id) |> send!(@user)
    end

    test "Pause-Printer and Resume-Printer, as an administrator", ctx do
      name = "pausable_#{System.unique_integer([:positive])}"
      on_exit(fn -> docker(["exec", ctx.container, "lpadmin", "-x", name]) end)

      container_exec(ctx.container, [
        "lpadmin",
        "-p",
        name,
        "-E",
        "-v",
        "file:///dev/null",
        "-m",
        "raw"
      ])

      uri = printer(ctx.https, name)

      state = fn ->
        ctx.http |> printer(name) |> GetPrinterAttributes.new() |> send!() |> Message.printer()
      end

      assert {:error, %Hippy.HTTPError{status: 401}} =
               uri |> PausePrinter.new() |> Hippy.send_operation(@anonymous)

      assert uri |> PausePrinter.new() |> send!(@admin) |> Message.status() == :successful_ok
      assert %{"printer-state" => :stopped, "printer-state-reasons" => reasons} = state.()
      assert "paused" in reasons
      refute Hippy.printer_ready?(state.())

      assert uri |> ResumePrinter.new() |> send!(@admin) |> Message.status() == :successful_ok
      assert state.()["printer-state"] == :idle
      assert Hippy.printer_ready?(state.())
    end
  end

  describe "subscriptions and notifications" do
    defp subscribe!(op, opts) do
      [%{"notify-subscription-id" => id}] = op |> send!(opts) |> Message.subscriptions()
      id
    end

    defp events!(uri, id, opts, auth \\ @user) do
      uri |> GetNotifications.new([id], opts) |> send!(auth) |> Message.events()
    end

    defp event_names(events), do: Enum.map(events, & &1["notify-subscribed-event"])

    test "a printer subscription collects its events in order, and only new ones", ctx do
      uri = printer(ctx.https, "raw")

      id =
        uri
        |> CreatePrinterSubscriptions.new(events: ["job-created", "job-completed"])
        |> subscribe!(@user)

      job_id = uri |> PrintJob.new("hello") |> print!(@user)
      wait_for_job_state(uri, job_id, [:completed], @user)

      events = events!(uri, id, [])
      assert event_names(events) == ["job-created", "job-completed"]
      assert Enum.map(events, & &1["notify-sequence-number"]) == [1, 2]
      assert Enum.all?(events, &(&1["notify-job-id"] == job_id))
      assert List.last(events)["job-state"] == :completed

      # Only events after the last one seen, and how long to wait before asking again.
      res = uri |> GetNotifications.new(id, sequence_numbers: 3) |> send!(@user)
      assert Message.events(res) == []
      assert is_integer(Message.operation_attributes(res)["notify-get-interval"])

      assert uri
             |> RenewSubscription.new(id, lease_duration: 120)
             |> send!(@user)
             |> Message.status() == :successful_ok

      assert uri |> CancelSubscription.new(id) |> send!(@user) |> Message.status() ==
               :successful_ok

      assert ipp_error!(GetNotifications.new(uri, id), @user).status == :client_error_not_found
    end

    test "a job subscription follows one job (CUPS: administrators only)", ctx do
      uri = printer(ctx.https, "held_cancel")
      job_id = uri |> PrintJob.new(pdf()) |> print!(@user)

      # CUPS checks Create-Job-Subscriptions without the job's owner, so even the owner is
      # forbidden; administrators aren't.
      assert {:error, %Hippy.HTTPError{status: 403}} =
               uri |> CreateJobSubscriptions.new(job_id) |> Hippy.send_operation(@user)

      id = uri |> CreateJobSubscriptions.new(job_id) |> subscribe!(@admin)

      uri |> HoldJob.new(job_id) |> send!(@user)

      assert [%{"notify-subscribed-event" => "job-state-changed", "job-state" => :pending_held}] =
               events!(uri, id, [], @admin)

      # CUPS deletes a job subscription, and its events, once the job has ended.
      uri |> CancelJob.new(job_id) |> send!(@user)
      assert ipp_error!(GetNotifications.new(uri, id), @admin).status == :client_error_not_found
    end

    test "the job's owner can subscribe while creating the job", ctx do
      uri = printer(ctx.https, "held_cancel")

      subscription =
        {:subscription,
         [
           {:keyword, "notify-pull-method", "ippget"},
           {:keyword, "notify-events", "job-state-changed"}
         ]}

      res = uri |> PrintJob.new(pdf(), groups: [subscription]) |> send!(@user)
      job_id = Message.job(res)["job-id"]
      [%{"notify-subscription-id" => id}] = Message.subscriptions(res)

      uri |> HoldJob.new(job_id) |> send!(@user)

      # Subscribing with the job also reports its creation.
      events = events!(uri, id, [])
      assert event_names(events) == ["job-created", "job-state-changed"]
      assert Enum.all?(events, &(&1["notify-job-id"] == job_id))
      assert List.last(events)["job-state"] == :pending_held

      uri |> CancelJob.new(job_id) |> send!(@user)
    end

    test "send_operation/4 takes IANA's names for the subscription operations", ctx do
      uri = printer(ctx.https, "raw")

      {:ok, res} =
        Hippy.send_operation(
          uri,
          :create_printer_subscriptions,
          %{"notify-pull-method" => "ippget", "notify-events" => ["job-completed"]},
          @user
        )

      assert [%{"notify-subscription-id" => id}] = Message.subscriptions(res)
      uri |> CancelSubscription.new(id) |> send!(@user)
    end

    test "only the subscription's owner can collect its notifications", ctx do
      uri = printer(ctx.https, "raw")
      id = uri |> CreatePrinterSubscriptions.new() |> subscribe!(@user)

      assert {:error, %Hippy.HTTPError{status: 401}} =
               uri |> GetNotifications.new(id) |> Hippy.send_operation(@anonymous)

      uri |> CancelSubscription.new(id) |> send!(@user)
    end
  end

  describe "Hippy.stream_events/2" do
    # Runs a stream in a task until `done?` is true for an event, so it stops on its own.
    defp collect_events(uri, opts, done?) do
      Task.async(fn ->
        uri
        |> Hippy.stream_events(opts)
        |> Enum.reduce_while([], fn event, events ->
          if done?.(event), do: {:halt, [event | events]}, else: {:cont, [event | events]}
        end)
        |> Enum.reverse()
      end)
    end

    defp summary(events) do
      Enum.map(events, fn
        %{"notify-subscribed-event" => "printer-state-changed"} = e ->
          {:printer, e["printer-state"], e["printer-state-reasons"]}

        e ->
          {e["notify-job-id"], e["job-state"]}
      end)
    end

    test "reports each change to the printer and its jobs, as it is now", ctx do
      name = "events_#{System.unique_integer([:positive])}"
      on_exit(fn -> docker(["exec", ctx.container, "lpadmin", "-x", name]) end)

      container_exec(ctx.container, [
        "lpadmin",
        "-p",
        name,
        "-E",
        "-v",
        "file:///dev/null",
        "-m",
        "raw"
      ])

      container_exec(ctx.container, ["cupsdisable", name])

      uri = printer(ctx.https, name)

      events =
        collect_events(uri, [interval: 200] ++ @user, &(&1["printer-state"] == :idle))

      step = fn -> Process.sleep(600) end

      step.()
      id = uri |> PrintJob.new(pdf(), job_name: "Watched") |> print!(@user)
      step.()
      uri |> HoldJob.new(id) |> send!(@user)
      step.()
      uri |> ReleaseJob.new(id) |> send!(@user)
      step.()
      uri |> CancelJob.new(id) |> send!(@user)
      step.()
      uri |> ResumePrinter.new() |> send!(@admin)

      events = Task.await(events, 15_000)

      # Including what CUPS doesn't send notifications for (hold, release, cancel), and the
      # printer's reasons as they are after resuming.
      assert summary(events) == [
               {:printer, :stopped, ["paused"]},
               {id, :pending},
               {id, :pending_held},
               {id, :pending},
               {id, :canceled},
               {:printer, :idle, ["none"]}
             ]

      assert %{"job-name" => "Watched", "job-state-reasons" => [_ | _]} = Enum.at(events, 1)
    end

    test "a job that starts and finishes between two checks is still reported", ctx do
      uri = printer(ctx.http, "raw")

      # More finished jobs than the stream asks for at a time. CUPS lists them oldest first.
      ids = for n <- 1..55, do: uri |> PrintJob.new("old #{n}") |> print!()
      wait_for_job_state(uri, List.last(ids), [:completed], [])
      # Jobs that completed before the stream started aren't reported, so this is the new one.
      events = collect_events(uri, [interval: 3_000], &(&1["job-state"] == :completed))

      Process.sleep(500)
      id = uri |> PrintJob.new("tiny", job_name: "Quick") |> print!()

      events = events |> Task.await(15_000) |> Enum.filter(&(&1["notify-job-id"] == id))
      assert summary(events) == [{id, :completed}]
    end

    test "works the same with a printer at home", %{home: home} do
      # The emulated printer takes one job at a time, and may still be printing another test's.
      Stream.repeatedly(fn ->
        Process.sleep(200)
        home |> GetPrinterAttributes.new() |> send!() |> Message.printer()
      end)
      |> Enum.find(&(&1["printer-state"] == :idle))

      events = collect_events(home, [interval: 200], &(&1["job-state"] == :completed))
      Process.sleep(500)
      id = home |> PrintJob.new(pdf(), document_format: "application/pdf") |> print!()

      [printer | jobs] = Task.await(events, 30_000)

      assert printer["notify-subscribed-event"] == "printer-state-changed"
      assert List.last(jobs)["notify-job-id"] == id
      assert List.last(jobs)["job-state"] == :completed
    end

    test "can report only the printer's state", ctx do
      events =
        ctx.http
        |> printer("held_jobs")
        |> Hippy.stream_events(events: ["printer-state-changed"])
        |> Enum.take(1)

      # A paused queue, so its state doesn't depend on other tests' jobs.
      assert [
               %{
                 "notify-subscribed-event" => "printer-state-changed",
                 "printer-state" => :stopped
               }
             ] =
               events
    end

    test "a printer that can't be reached raises" do
      assert_raise Req.TransportError, fn ->
        "ipp://localhost:1/printers/none" |> Hippy.stream_events() |> Enum.take(1)
      end
    end
  end

  describe "Get-Jobs and Get-Job-Attributes" do
    test "which_jobs filters pending jobs", %{http: http} do
      uri = printer(http, "held_jobs")
      ids = for n <- 1..2, do: PrintJob.new(uri, pdf(), job_name: "Held #{n}") |> print!()

      assert Enum.map(ids, &job_attributes!(uri, &1)["job-state"]) == [:pending, :pending]
      assert job_ids(uri, :not_completed) == ids
      assert job_ids(uri, :completed) == []
      assert job_ids(uri, :all) == ids
    end

    test "missing job returns not found", %{http: http} do
      error = printer(http, "raw") |> GetJobAttributes.new(99_999) |> ipp_error!()
      assert error.status == :client_error_not_found
    end
  end

  describe "Cancel-Job with the default CUPS policy" do
    test "anonymous cancel over plain HTTP requires an upgrade to TLS", %{http: http} do
      uri = printer(http, "held_cancel")
      id = PrintJob.new(uri, pdf()) |> print!()

      assert {:error, %Hippy.HTTPError{status: 426}} =
               CancelJob.new(uri, id) |> Hippy.send_operation()
    end

    test "anonymous cancel over HTTPS requires authentication", ctx do
      id = printer(ctx.http, "held_cancel") |> PrintJob.new(pdf()) |> print!()
      op = printer(ctx.https, "held_cancel") |> CancelJob.new(id)

      assert {:error, %Hippy.HTTPError{status: 401}} = Hippy.send_operation(op, @anonymous)
    end

    test "authenticated user can cancel only their own jobs", ctx do
      anonymous_id = printer(ctx.http, "held_cancel") |> PrintJob.new(pdf()) |> print!()
      uri = printer(ctx.https, "held_cancel")

      assert {:error, %Hippy.HTTPError{status: 403}} =
               CancelJob.new(uri, anonymous_id) |> Hippy.send_operation(@user)

      id = PrintJob.new(uri, pdf(), job_name: "Mine") |> print!(@user)
      assert job_attributes!(uri, id, @user)["job-originating-user-name"] == "hippy"

      assert uri |> CancelJob.new(id) |> send!(@user) |> Message.status() == :successful_ok
      assert job_attributes!(uri, id, @user)["job-state"] == :canceled
      assert ipp_error!(CancelJob.new(uri, id), @user).status == :client_error_not_possible
    end
  end

  describe "authentication and transport" do
    test "Basic auth over HTTPS", %{https: https} do
      op = printer(https, "secure") |> GetPrinterAttributes.new()
      wrong = [req_options: @tls ++ [auth: {:basic, "hippy:wrong"}]]

      assert {:error, %Hippy.HTTPError{status: 401}} = Hippy.send_operation(op, @anonymous)
      assert {:error, %Hippy.HTTPError{status: 401}} = Hippy.send_operation(op, wrong)
      assert op |> send!(@user) |> Message.status() == :successful_ok
      assert is_integer(PrintJob.new(op.printer_uri, pdf()) |> print!(@user))
    end

    test "concurrent requests use their own credentials", %{https: https} do
      op = printer(https, "secure") |> GetPrinterAttributes.new()

      results =
        1..20
        |> Enum.map(fn n -> if rem(n, 2) == 0, do: @user, else: @anonymous end)
        |> Task.async_stream(&{&1, Hippy.send_operation(op, &1)}, max_concurrency: 20)
        |> Enum.map(fn {:ok, result} -> result end)

      for {opts, result} <- results do
        if opts == @user do
          assert {:ok, %Message{code: 0}} = result
        else
          assert {:error, %Hippy.HTTPError{status: 401}} = result
        end
      end
    end

    test "ipps:// printer URI", %{https: https} do
      uri = String.replace(printer(https, "secure"), "https://", "ipps://")

      assert uri |> GetPrinterAttributes.new() |> send!(@user) |> Message.status() ==
               :successful_ok
    end

    test "self-signed certificate is rejected when verification is on", %{https: https} do
      capture_log(fn ->
        assert {:error, %Req.TransportError{reason: {:tls_alert, _}}} =
                 printer(https, "raw") |> GetPrinterAttributes.new() |> Hippy.send_operation()
      end)
    end

    test "a pinned self-signed certificate is accepted (as in the README)", ctx do
      op = printer(ctx.https, "raw") |> GetPrinterAttributes.new()

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

      verify = tls_options(verify_fun: {pinning_verify_fun(pinned), nil})
      assert op |> send!(verify) |> Message.status() == :successful_ok

      capture_log(fn ->
        assert {:error, %Req.TransportError{reason: {:tls_alert, _}}} =
                 Hippy.send_operation(
                   op,
                   tls_options(verify_fun: {pinning_verify_fun(<<"other">>), nil})
                 )
      end)
    end

    test "receive timeout surfaces as a transport error", %{http: http} do
      op = printer(http, "raw") |> PrintJob.new(:crypto.strong_rand_bytes(25 * 1024 * 1024))

      assert {:error, %Req.TransportError{reason: :timeout}} =
               Hippy.send_operation(op, req_options: [receive_timeout: 1])
    end
  end

  # Helpers

  describe "README home printer examples, on an emulated driverless printer" do
    test "the ink gauge shows each supply", %{home: home} do
      {:ok, gauge} = Hippy.ReadmeInk.gauge(home)
      plain = String.replace(gauge, ~r/\e\[[0-9;]*m/, "")

      assert plain =~ ~r/^Toner Waste Tank +█{5}░{15} 25% full$/mu
      assert plain =~ ~r/^Black Toner +█{15}░{5} 75%$/mu
    end

    test "the Mandelbrot page is a valid PDF that fills the page", %{home: home} = ctx do
      lines = Hippy.ReadmeMandelbrot.lines()
      assert length(lines) == 120
      assert Enum.all?(lines, &(String.length(&1) == 150))
      # Light characters only: nothing that needs escaping in a PDF string.
      assert lines |> Enum.join() |> String.match?(~r/^[ .,:;~=+*-]+$/)

      pdf = Hippy.ReadmeMandelbrot.pdf()
      [_, xref] = Regex.run(~r/startxref\n(\d+)\n%%EOF\n$/, pdf)
      xref = String.to_integer(xref)
      assert binary_part(pdf, xref, 5) == "xref\n"

      # Each object's offset in the cross-reference table points at that object.
      offsets = Regex.scan(~r/^(\d{10}) 00000 n $/m, pdf, capture: :all_but_first)

      for {[offset], i} <- Enum.with_index(offsets, 1) do
        header = "#{i} 0 obj\n"
        assert binary_part(pdf, String.to_integer(offset), byte_size(header)) == header
      end

      assert {:ok, res} = Hippy.ReadmeMandelbrot.print(home)
      assert %{"job-id" => job_id} = Message.job(res)

      # The printer received exactly that PDF (ippeveprinter keeps it, named after the job).
      spooled = "/spool/home/#{job_id}-mandelbrot.pdf"
      wait_for_file(ctx.container, spooled)
      assert container_exec(ctx.container, ["cat", spooled]) == pdf
    end
  end

  defp docker(args), do: System.cmd("docker", args, stderr_to_stdout: true)

  defp container_exec(container, cmd) do
    {out, 0} = docker(["exec", container | cmd])
    out
  end

  defp wait_for_file(container, path, attempts \\ 50) do
    case docker(["exec", container, "test", "-s", path]) do
      {_, 0} ->
        :ok

      _missing when attempts > 0 ->
        Process.sleep(100)
        wait_for_file(container, path, attempts - 1)
    end
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
    {:ok, %Message{} = res} = Hippy.send_operation(op, opts)
    res
  end

  defp ipp_error!(op, opts \\ []) do
    {:error, %Hippy.Error{} = error} = Hippy.send_operation(op, opts)
    error
  end

  defp print!(op, opts \\ []) do
    res = send!(op, opts)
    assert Message.status(res) == :successful_ok
    Message.job(res)["job-id"]
  end

  defp job_attributes!(uri, id, opts \\ []) do
    uri |> GetJobAttributes.new(id) |> send!(opts) |> Message.job()
  end

  defp wait_for_job_state(uri, id, states, opts, attempts \\ 100) do
    attributes = job_attributes!(uri, id, opts)

    cond do
      attributes["job-state"] in states ->
        attributes

      attempts > 0 ->
        Process.sleep(100)
        wait_for_job_state(uri, id, states, opts, attempts - 1)

      true ->
        flunk("job #{id} is #{inspect(attributes["job-state"])}, expected #{inspect(states)}")
    end
  end

  defp job_ids(uri, which) do
    GetJobs.new(uri, which_jobs: which)
    |> send!()
    |> Message.jobs()
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

# The README's print_and_wait example, as written there (with a shorter sleep).
defmodule Hippy.ReadmePrinting do
  alias Hippy.Operation.{GetJobAttributes, PrintJob}

  def print_and_wait(printer_uri, document) do
    {:ok, res} = printer_uri |> PrintJob.new(document) |> Hippy.send_operation()

    res
    |> Hippy.Message.job()
    |> Map.fetch!("job-id")
    |> wait_for_job(printer_uri)
  end

  defp wait_for_job(job_id, printer_uri) do
    {:ok, res} = printer_uri |> GetJobAttributes.new(job_id) |> Hippy.send_operation()

    case Hippy.Message.job(res) do
      %{"job-state" => state} when state in [:completed, :canceled, :aborted] ->
        {state, job_id}

      _ ->
        Process.sleep(500)
        wait_for_job(job_id, printer_uri)
    end
  end
end

# The README's MyApp.Fleet example, as written there.
defmodule Hippy.ReadmeFleet do
  alias Hippy.Message
  alias Hippy.Operation.{GetPrinterAttributes, PrintJob}

  @attributes [
    "printer-state",
    "printer-state-reasons",
    "printer-is-accepting-jobs",
    "queued-job-count"
  ]

  def status(printer_uris) do
    printer_uris
    |> Task.async_stream(&{&1, printer_status(&1)}, timeout: :infinity)
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp printer_status(uri) do
    with {:ok, res} <-
           uri
           |> GetPrinterAttributes.new(requested_attributes: @attributes)
           |> Hippy.send_operation(timeout: 5_000) do
      {:ok, Message.printer(res)}
    end
  end

  def print(printer_uris, document) do
    printer_uris
    |> status()
    |> Enum.flat_map(fn
      {uri, {:ok, printer}} -> if Hippy.printer_ready?(printer), do: [{uri, printer}], else: []
      {_uri, {:error, _}} -> []
    end)
    |> Enum.sort_by(fn {_uri, printer} -> printer["queued-job-count"] end)
    |> Enum.reduce_while({:error, :no_printer_available}, fn {uri, _printer}, none ->
      case uri |> PrintJob.new(document) |> Hippy.send_operation() do
        {:ok, res} ->
          {:halt, {:ok, uri, Message.job(res)["job-id"]}}

        {:error, error} ->
          # Move on only if the job definitely wasn't accepted. After a timeout, for example,
          # it may have printed: stop and check, rather than print it twice.
          if Hippy.safe_to_resend?(error),
            do: {:cont, none},
            else: {:halt, {:error, {:unknown, uri, error}}}
      end
    end)
  end
end

# The README's MyApp.Ink and MyApp.Mandelbrot examples, as written there.
defmodule Hippy.ReadmeInk do
  alias Hippy.Operation.GetPrinterAttributes

  @colors %{"black" => :light_black, "cyan" => :cyan, "magenta" => :magenta, "yellow" => :yellow}

  def gauge(uri) do
    with {:ok, res} <-
           uri
           |> GetPrinterAttributes.new(
             requested_attributes: ["printer-supply", "printer-supply-description"]
           )
           |> Hippy.send_operation(timeout: 5_000) do
      printer = Hippy.Message.printer(res)
      names = Map.get(printer, "printer-supply-description", [])

      printer
      |> Map.get("printer-supply", [])
      |> Enum.map(&parse/1)
      |> Enum.with_index(fn supply, i -> bar(supply, Enum.at(names, i)) end)
      |> Enum.join("\n")
      |> then(&{:ok, &1})
    end
  end

  # "type=toner;level=75;..." -> %{"type" => "toner", "level" => "75", ...}
  defp parse(supply) do
    supply
    |> String.split(";", trim: true)
    |> Map.new(&(&1 |> String.split("=", parts: 2) |> List.to_tuple()))
  end

  defp bar(supply, name) do
    label = String.pad_trailing(name || supply["type"] || "supply", 18)

    with {level, ""} when level >= 0 <- Integer.parse(supply["level"] || ""),
         {max, ""} when max > 0 <- Integer.parse(supply["maxcapacity"] || "100") do
      percent = min(div(level * 100, max), 100)
      filled = div(percent, 5)
      color = Map.get(@colors, supply["colorantname"], :white)
      # A waste tank's level is how full it is, not how much is left.
      full = if supply["class"] == "receptacleThatIsFilled", do: " full", else: ""

      bar =
        IO.ANSI.format(
          [color, String.duplicate("█", filled), :reset] ++
            [:faint, String.duplicate("░", 20 - filled), :reset]
        )

      "#{label} #{bar} #{percent}%#{full}"
    else
      _unknown -> "#{label} level unknown"
    end
  end
end

defmodule Hippy.ReadmeMandelbrot do
  alias Hippy.Operation.{GetPrinterAttributes, PrintJob}

  @columns 150
  @rows 120
  # Nothing for the set itself or the outer bands, then lighter to heavier characters.
  @ramp ~c"     .,:;~-=+*"

  def print(uri) do
    with {:ok, res} <-
           uri
           |> GetPrinterAttributes.new(requested_attributes: ["document-format-supported"])
           |> Hippy.send_operation(),
         %{"document-format-supported" => formats} = Hippy.Message.printer(res),
         true <- "application/pdf" in formats || {:error, :pdf_not_supported} do
      uri
      |> PrintJob.new(pdf(), document_format: "application/pdf", job_name: "Mandelbrot")
      |> Hippy.send_operation()
    end
  end

  def lines do
    for row <- 0..(@rows - 1) do
      for col <- 0..(@columns - 1), into: "" do
        # The real axis runs down the page, so the set fills a tall sheet.
        <<char(escape(0.55 - row * 2.6 / @rows, -0.975 + col * 1.95 / @columns))>>
      end
    end
  end

  # How many steps z = z² + c takes to escape, or :inside if it never does.
  defp escape(re, im, zr \\ 0.0, zi \\ 0.0, n \\ 0)
  defp escape(_re, _im, _zr, _zi, 80), do: :inside
  defp escape(_re, _im, zr, zi, n) when zr * zr + zi * zi > 4, do: n

  defp escape(re, im, zr, zi, n),
    do: escape(re, im, zr * zr - zi * zi + re, 2 * zr * zi + im, n + 1)

  defp char(:inside), do: ?\s
  defp char(n), do: Enum.at(@ramp, min(n, length(@ramp) - 1))

  # A one-page PDF: the lines in 6-point Courier, in light grey, on a Letter page.
  def pdf do
    text = lines() |> Enum.map_join("\n", &"(#{&1}) '")
    content = "BT /F1 6 Tf 6 TL 0.55 g 36 762 Td\n#{text}\nET"

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] " <>
        "/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
      "<< /Length #{byte_size(content)} >>\nstream\n#{content}\nendstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>"
    ]

    # The cross-reference table at the end gives each object's byte offset.
    header = "%PDF-1.4\n"

    {objects, xref_offset} =
      objects
      |> Enum.with_index(1)
      |> Enum.map_reduce(byte_size(header), fn {object, i}, offset ->
        object = "#{i} 0 obj\n#{object}\nendobj\n"
        {{offset, object}, offset + byte_size(object)}
      end)

    count = length(objects) + 1

    IO.iodata_to_binary([
      header,
      Enum.map(objects, fn {_offset, object} -> object end),
      "xref\n0 #{count}\n0000000000 65535 f \n",
      Enum.map(objects, fn {offset, _} ->
        String.pad_leading("#{offset}", 10, "0") <> " 00000 n \n"
      end),
      "trailer\n<< /Size #{count} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"
    ])
  end
end
