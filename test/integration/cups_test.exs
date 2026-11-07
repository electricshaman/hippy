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

      res = send!(GetPrinterAttributes.new(printer(http, "raw")))
      assert res.code == 0
      {:printer, printer} = List.keyfind(res.groups, :printer, 0)
      assert {"printer-state", [enum: 3]} in printer
    end

    test "accepts an ipp:// printer URI", %{http: http} do
      uri = String.replace(printer(http, "raw"), "http://", "ipp://")
      assert Message.status(send!(GetPrinterAttributes.new(uri))) == :successful_ok
    end

    test "missing queue returns not found", %{http: http} do
      error = ipp_error!(GetPrinterAttributes.new(printer(http, "missing")))
      assert error.status == :client_error_not_found
      assert error.message =~ "does not exist"
    end

    test "handles concurrent requests", %{http: http} do
      statuses =
        1..25
        |> Task.async_stream(
          fn _ -> Message.status(send!(GetPrinterAttributes.new(printer(http, "raw")))) end,
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
        send!(
          CupsGetPrinters.new("#{http}/", requested_attributes: ["printer-name", "printer-state"])
        )

      states = Map.new(Message.printers(res), &{&1["printer-name"], &1["printer-state"]})

      assert Message.status(res) == :successful_ok
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
               Message.printers(res)
    end

    test "CUPS-Get-Default returns the default printer", %{http: http} do
      res = send!(CupsGetDefault.new("#{http}/", requested_attributes: ["printer-name"]))
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
               Hippy.Server.send_request(req, admin, @anonymous)

      assert {:ok, %Message{code: 0}} = Hippy.Server.send_request(req, admin, @admin)

      attrs = Message.printer(send!(GetPrinterAttributes.new(printer(ctx.http, name))))
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
               Hippy.Server.send_request(req, "#{ctx.https}/admin/", @admin)

      attrs = Message.printer(send!(GetPrinterAttributes.new(printer(ctx.http, name))))
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

      {:ok, res} = Hippy.Server.send_request(req, uri)
      assert Message.status(res) == :successful_ok

      ids = res |> Message.groups(:subscription) |> Enum.map(& &1["notify-subscription-id"])

      assert length(ids) == 2 and Enum.all?(ids, &is_integer/1)

      # Each subscription got its own group's events.
      list =
        Hippy.IPP.Operation.get_subscriptions()
        |> Message.build_request(Map.put(@base, :printer_uri, uri), [
          {{:set1, :keyword}, "requested-attributes", ["notify-subscription-id", "notify-events"]}
        ])

      {:ok, res} = Hippy.Server.send_request(list, uri)

      events =
        res
        |> Message.groups(:subscription)
        |> Map.new(&{&1["notify-subscription-id"], &1["notify-events"]})

      assert events[Enum.at(ids, 0)] == ["printer-state-changed"]
      assert events[Enum.at(ids, 1)] == ["job-completed"]
    end

    test "Print-Job with a subscription group subscribes to the job", %{http: http} do
      op =
        PrintJob.new(printer(http, "raw"), pdf(),
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
        Hippy.send_operation(
          printer(https, "held_cancel"),
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
        Message.printer(send!(GetPrinterAttributes.new(printer(ctx.http, name))))[
          "printer-state"
        ]
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

      assert Message.printer(send!(GetPrinterAttributes.new(printer(ctx.http, name))))[
               "printer-info"
             ] ==
               "Made by Hippy.send_operation"

      {:ok, %Message{code: 0}} =
        Hippy.send_operation(queue, :pause_printer, %{}, @admin)

      assert printer_state.() == :stopped

      {:ok, %Message{code: 0}} =
        Hippy.send_operation(queue, :resume_printer, %{}, @admin)

      assert printer_state.() == :idle

      {:ok, %Message{code: 0}} =
        Hippy.send_operation(queue, :cups_delete_printer, %{"printer-uri" => printer_uri}, admin)

      assert ipp_error!(GetPrinterAttributes.new(printer(ctx.http, name))).status ==
               :client_error_not_found
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
        ipp_error!(
          PrintJob.new(printer(http, "raw"), pdf(), document_format: "application/x-nope")
        )

      assert error.status == :client_error_document_format_not_supported
      res = error.response

      assert Message.unsupported(res) == %{"document-format" => "application/x-nope"}
    end

    test "plain text is auto-typed and converted by CUPS", %{http: http} do
      uri = printer(http, "filtered")
      id = print!(PrintJob.new(uri, "Hello from Hippy\n", job_name: "Hippy text"))
      assert wait_for_state(uri, id) == :completed
    end

    test "streamed documents arrive whole", %{http: http} do
      uri = printer(http, "raw")
      chunks = Stream.repeatedly(fn -> :crypto.strong_rand_bytes(64_000) end) |> Stream.take(400)

      id = print!(PrintJob.new(uri, chunks))
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

      id = print!(PrintJob.new(uri, File.stream!(path), document_format: "application/pdf"))
      assert wait_for_state(uri, id) == :completed
      assert container_exec(ctx.container, ["head", "-c", "4", "/spool/filtered.ps"]) == "%!PS"
    end

    test "large documents", %{http: http} do
      uri = printer(http, "raw")
      id = print!(PrintJob.new(uri, :crypto.strong_rand_bytes(25 * 1024 * 1024)))
      assert wait_for_state(uri, id) == :completed
    end

    test "queue rejecting jobs returns not accepting jobs", %{http: http} do
      error = ipp_error!(PrintJob.new(printer(http, "rejecting"), pdf()))
      assert error.status == :server_error_not_accepting_jobs
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
      error = ipp_error!(GetJobAttributes.new(printer(http, "raw"), 99_999))
      assert error.status == :client_error_not_found
    end
  end

  describe "Cancel-Job with the default CUPS policy" do
    test "anonymous cancel over plain HTTP requires an upgrade to TLS", %{http: http} do
      uri = printer(http, "held_cancel")
      id = print!(PrintJob.new(uri, pdf()))

      assert {:error, %Hippy.HTTPError{status: 426}} =
               Hippy.send_operation(CancelJob.new(uri, id))
    end

    test "anonymous cancel over HTTPS requires authentication", ctx do
      id = print!(PrintJob.new(printer(ctx.http, "held_cancel"), pdf()))
      op = CancelJob.new(printer(ctx.https, "held_cancel"), id)

      assert {:error, %Hippy.HTTPError{status: 401}} = Hippy.send_operation(op, @anonymous)
    end

    test "authenticated user can cancel only their own jobs", ctx do
      anonymous_id = print!(PrintJob.new(printer(ctx.http, "held_cancel"), pdf()))
      uri = printer(ctx.https, "held_cancel")

      assert {:error, %Hippy.HTTPError{status: 403}} =
               Hippy.send_operation(CancelJob.new(uri, anonymous_id), @user)

      id = print!(PrintJob.new(uri, pdf(), job_name: "Mine"), @user)
      assert job_attributes!(uri, id, @user)["job-originating-user-name"] == "hippy"

      assert Message.status(send!(CancelJob.new(uri, id), @user)) == :successful_ok
      assert job_attributes!(uri, id, @user)["job-state"] == :canceled
      assert ipp_error!(CancelJob.new(uri, id), @user).status == :client_error_not_possible
    end
  end

  describe "authentication and transport" do
    test "Basic auth over HTTPS", %{https: https} do
      op = GetPrinterAttributes.new(printer(https, "secure"))
      wrong = [req_options: @tls ++ [auth: {:basic, "hippy:wrong"}]]

      assert {:error, %Hippy.HTTPError{status: 401}} = Hippy.send_operation(op, @anonymous)
      assert {:error, %Hippy.HTTPError{status: 401}} = Hippy.send_operation(op, wrong)
      assert Message.status(send!(op, @user)) == :successful_ok
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
          assert {:ok, %Message{code: 0}} = result
        else
          assert {:error, %Hippy.HTTPError{status: 401}} = result
        end
      end
    end

    test "ipps:// printer URI", %{https: https} do
      uri = String.replace(printer(https, "secure"), "https://", "ipps://")

      assert Message.status(send!(GetPrinterAttributes.new(uri), @user)) == :successful_ok
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

      assert Message.status(send!(op, tls_options(verify_fun: {pinning_verify_fun(pinned), nil}))) ==
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
    Message.job(send!(GetJobAttributes.new(uri, id), opts))
  end

  defp job_ids(uri, which) do
    send!(GetJobs.new(uri, which_jobs: which))
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
      {uri, {:ok, %{"printer-state" => state, "printer-is-accepting-jobs" => true} = printer}}
      when state != :stopped ->
        [{uri, printer["queued-job-count"]}]

      _unavailable ->
        []
    end)
    |> Enum.sort_by(fn {_uri, queued} -> queued end)
    |> Enum.reduce_while({:error, :no_printer_available}, fn {uri, _queued}, none ->
      case uri |> PrintJob.new(document) |> Hippy.send_operation() do
        {:ok, res} ->
          {:halt, {:ok, uri, Message.job(res)["job-id"]}}

        # The printer refused the job, or couldn't be reached, so nothing was printed.
        {:error, %error{}} when error in [Hippy.Error, Hippy.HTTPError] ->
          {:cont, none}

        {:error, %Req.TransportError{reason: :econnrefused}} ->
          {:cont, none}

        # Anything else, such as a timeout, may have printed: check before trying again.
        {:error, error} ->
          {:halt, {:error, {:unknown, uri, error}}}
      end
    end)
  end
end
