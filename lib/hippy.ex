defmodule Hippy do
  @moduledoc """
  An IPP client: send operations to printers and CUPS servers, and read their responses.

  Functions that send requests over the network are named `send_*`, or `stream_events/2` for a
  stream that sends them as it runs. Everything else has no side effects: building operations
  (`Hippy.Operation.PrintJob.new/3` and the other `Hippy.Operation` modules), reading responses
  and encoding messages (`Hippy.Message`), and the helpers `printer_ready?/1` and
  `safe_to_resend?/1`.

      {:ok, res} =
        "ipp://localhost:631/printers/office"
        |> Hippy.Operation.GetPrinterAttributes.new()
        |> Hippy.send_operation()

      Hippy.Message.printer(res)["printer-state"]
      #=> :idle

  ## Errors

  Sending returns `{:ok, %Hippy.Message{}}`, or `{:error, error}` where `error` is an exception
  once the request has been sent:

    * `Hippy.Error` when the printer returns an IPP error (a client-error or server-error
      status, such as `:client_error_not_found`). It keeps the whole response.
    * `Hippy.HTTPError` when it answers with an HTTP error instead, e.g. 401 Unauthorized.
    * Req's exceptions, such as `Req.TransportError`, when it can't be reached or times out.

  So `Exception.message/1` describes any of them, and `safe_to_resend?/1` says whether the
  request definitely wasn't accepted. Errors found before anything is sent are tuples, such as
  `{:unknown_operation, name}`.

  `{:ok, response}` can still mean the printer ignored or changed some attributes it doesn't
  support (status `:successful_ok_ignored_or_substituted_attributes`).
  `Hippy.Message.unsupported/1` lists them.

  ## Attributes as maps

  Operations' `attributes:` option, and `send_operation/4`, take attributes as a map of names to
  plain values. Each attribute's syntax and group are worked out from the IANA registry
  (`Hippy.IPP.Attributes`):

      Hippy.Operation.PrintJob.new(uri, doc,
        attributes: %{
          "copies" => 2,
          "sides" => "two-sided-long-edge",
          "orientation-requested" => :landscape,
          "media-col" => %{"media-size" => %{"x-dimension" => 21000, "y-dimension" => 29700}}
        }
      )

  The syntax comes from the attribute's registered types and the value:

    * Integers, booleans, `DateTime`, `Range`, `URI` and `Hippy.PrintResolution` values map to
      the matching type. For an enum attribute, an integer or an atom such as `:landscape` (see
      `Hippy.IPP.Enum`).
    * Strings: for attributes that can be a keyword or a name (such as `media`), a string spelt
      like a keyword (lowercase letters, digits, `-`, `_` and `.`) is sent as a keyword, and
      anything else as a name. Otherwise the attribute's string type (`text`, `uri`,
      `mimeMediaType`, ...) is used. `{language, text}` is text or name with a language.
    * Maps are collections, with each member's syntax taken from its own definition.
    * Lists are sets, and each value's syntax is worked out separately.
    * `{syntax, value}` gives the syntax explicitly, e.g. `{:name_without_language, "plain"}`.

  Attributes go in the group their operation is mainly about (job template attributes for
  Print-Job and Validate-Job, printer attributes for CUPS-Add-Modify-Printer and
  Set-Printer-Attributes, subscription attributes for Create-Printer-Subscriptions, ...), if
  they're registered there, and otherwise in the operation attributes or another group they're
  registered in.

  Attributes the registry doesn't know (vendor and CUPS attributes such as `device-uri`) need
  their syntax, as `{syntax, value}`, and go in the operation's main group, or the operation
  attributes for operations without one. To put one elsewhere, use an operation's
  `operation_attributes:`, `job_attributes:` or `groups:` options, which take
  `{syntax, name, value}` tuples (see `Hippy.Message.encode/1` for the syntaxes). A value that
  doesn't fit an attribute's types raises `ArgumentError`.
  """

  @doc """
  Sends an operation (such as a `Hippy.Operation.PrintJob`) and decodes the response.

  The request is sent to the operation's `printer_uri`, or `server_uri` for operations addressed
  to the server such as `Hippy.Operation.CupsGetPrinters` (`ipp` and `ipps` are sent over `http`
  and `https`). See the module docs for what it returns.

  ## Options

    * `:timeout` - how long to wait, in milliseconds, both to connect and for the response.
      Req's defaults apply otherwise (15 seconds for the response).
    * `:req_options` - options for `Req` (authentication, TLS, etc.) for this request, merged
      over `config :hippy, req_options: [...]`. For example
      `req_options: [auth: {:basic, "user:pass"}]`.
    * `:endpoint` - the URL to send the request to, instead of the one derived from
      `printer_uri`.
    * `:ipp_version` - the IPP version to send, as `{major, minor}`. Defaults to
      `config :hippy, ipp_version: ...`, or `{1, 1}`; the config is only a default, so requests
      to different servers can each give their own. A printer that doesn't support the version
      answers with `:server_error_version_not_supported`. Some older servers only accept
      `{1, 0}`, and some operations need `{2, 0}` or later.
  """
  defdelegate send_operation(op, opts \\ []), to: Hippy.Server

  @doc """
  Sends any IPP operation, by name or id, to a printer or server, with attributes given as a map.

      Hippy.send_operation("ipp://localhost:631/printers/p", :validate_job, %{
        "document-format" => "application/pdf",
        "copies" => 2
      })

      Hippy.send_operation("ipp://localhost:631/", :cups_get_printers, %{"limit" => 10})

  `operation` is a name from `Hippy.IPP.Operation` (e.g. `:print_job`) or an operation id.
  Each attribute's syntax and group come from the IANA registry (see "Attributes as maps" in
  the module docs).

  What the request is about is worked out from the URI and the operation:

    * a job URI (`.../jobs/12`) is sent as `job-uri`,
    * CUPS's server-wide operations (CUPS-Get-Printers, CUPS-Get-Classes, CUPS-Get-Default,
      CUPS-Get-Devices, CUPS-Get-PPDs) are sent with no target attribute,
    * anything else is sent with `printer-uri`.

  A `"printer-uri"` or `"job-uri"` in `attributes` replaces the one that would be sent, e.g. for
  CUPS-Add-Modify-Printer, which is sent to `/admin/` about a printer.

  ## Options

    * `:document` - the document data, for Print-Job and Send-Document: a binary, or an
      `Enumerable` of binaries, sent as it's read (see `Hippy.Operation.PrintJob` for streaming
      a file).
    * `:target` - `:printer`, `:job` or `:server`, instead of working it out.
    * `:operation_attributes`, `:job_attributes` and `:groups` - attributes given explicitly as
      `{syntax, name, value}`, as for operations (see `Hippy.Message.build_request/4`).
    * `:charset` and `:language` - default to `"utf-8"` and `"en"`.
    * `:timeout`, `:req_options`, `:endpoint` and `:ipp_version`, as for `send_operation/2`.

  Returns the same results as `send_operation/2`, or `{:error, {:unknown_operation, name}}` for
  an operation name Hippy doesn't know (in which case nothing is sent).
  """
  defdelegate send_operation(uri, operation, attributes, opts \\ []), to: Hippy.Server

  @doc """
  Sends a request message you've built yourself (see `Hippy.Message.build_request/4`) to an
  endpoint URL, and decodes the response.

  A `request_id` is assigned if the message doesn't have one. Takes the same `:timeout` and
  `:req_options` options as `send_operation/2`, and returns the same results. The message is sent
  with its own `version`, unless the `:ipp_version` option is given;
  `config :hippy, ipp_version: ...` doesn't apply.
  """
  defdelegate send_message(message, endpoint, opts \\ []), to: Hippy.Server

  @doc """
  Returns a lazy `Stream` of a printer's events: its state changing, and its jobs being created,
  changing state and finishing. Nothing is sent until the stream is run.

      "ipp://192.168.1.50/ipp/print"
      |> Hippy.stream_events()
      |> Enum.each(&IO.inspect/1)

      %{
        "notify-subscribed-event" => "printer-state-changed",
        "printer-state" => :stopped,
        "printer-state-reasons" => ["media-empty-error"],
        "printer-is-accepting-jobs" => true
      }

      %{
        "notify-subscribed-event" => "job-state-changed",
        "notify-job-id" => 47,
        "job-state" => :completed,
        "job-state-reasons" => ["job-completed-successfully"],
        "job-name" => "Invoice"
      }

  It starts with the printer's current state and each active job's, then reports changes. There
  are two kinds of event, with these keys:

    * `"printer-state-changed"`: `"printer-state"`, `"printer-state-reasons"` and
      `"printer-is-accepting-jobs"`.
    * `"job-state-changed"`: `"notify-job-id"`, `"job-state"`, `"job-state-reasons"` and
      `"job-name"`. A job being created or finishing is a change of `"job-state"`. Printers can
      forget a finished job's details: CUPS drops `"job-name"` soon after a job completes.

  The stream runs until it's stopped, so run it in its own process, such as a supervised `Task`
  that sends each event to a LiveView or GenServer.

  ## How it works

  Every `:interval`, the stream reads the printer's state and its active jobs, and reports what
  changed, so events always describe the current state. It also lists completed jobs, so a job
  that starts and finishes between two checks is still reported once, with its final state, though
  any states in between are missed. It works the same with any printer: CUPS, office printers
  and printers at home.

  It doesn't use IPP notifications (see `Hippy.Operation.CreatePrinterSubscriptions`): with CUPS,
  a printer subscription isn't told about jobs being held, released or canceled, and its printer
  events can carry `printer-state-reasons` from before the change.

  ## Errors

  A check that fails is retried after waiting longer each time. If it fails `:retries` times in a
  row, or the printer can't be reached when the stream starts, the stream raises the error (a
  `Hippy.Error`, `Hippy.HTTPError` or Req's exception), so the process running it stops and its
  supervisor can restart it.

  ## Options

    * `:events` - the kinds of event to report, `"printer-state-changed"` and/or
      `"job-state-changed"`. Defaults to both. Leaving out job events saves the requests that
      list jobs.
    * `:interval` - how often to check, in milliseconds. Defaults to `2_000`.
    * `:retries` - how many failed checks in a row to retry. Defaults to `3`.
    * `:timeout`, `:req_options` and `:ipp_version`, as for `send_operation/2`.
  """
  def stream_events(printer_uri, opts \\ []), do: Hippy.EventStream.stream(printer_uri, opts)

  @doc """
  Returns whether a printer can take a job now, given its attributes as returned by
  `Hippy.Message.printer/1` or `Hippy.Message.printers/1`.

  It's ready when it's accepting jobs (`printer-is-accepting-jobs`), isn't stopped
  (`printer-state`), and none of its `printer-state-reasons` stops it printing:

    * reasons ending in `-error`, such as `media-jam-error`, stop it;
    * `-warning` and `-report` reasons, such as `toner-low-report`, don't;
    * a reason without a suffix, such as `media-empty`, is an error only while the printer is
      stopped (RFC 8011, section 5.4.12), so it doesn't count separately;
    * reasons starting with `offline`, which CUPS reports (as `offline-report`) when it can't
      reach a printer, also stop it, though RFC 8011 doesn't define them.

  The map must include those three attributes; ask for them with `requested_attributes:`.

      iex> Hippy.printer_ready?(%{
      ...>   "printer-state" => :idle,
      ...>   "printer-state-reasons" => ["toner-low-report"],
      ...>   "printer-is-accepting-jobs" => true
      ...> })
      true
  """
  def printer_ready?(
        %{"printer-state" => state, "printer-is-accepting-jobs" => accepting} = printer
      ) do
    reasons = printer |> Map.get("printer-state-reasons", ["none"]) |> List.wrap()

    accepting == true and state != :stopped and not Enum.any?(reasons, &blocking_reason?/1)
  end

  def printer_ready?(printer) do
    raise ArgumentError,
          "printer_ready?/1 needs printer-state, printer-state-reasons and " <>
            "printer-is-accepting-jobs, got: " <> inspect(Map.keys(printer))
  end

  defp blocking_reason?(reason) when is_binary(reason),
    do: String.ends_with?(reason, "-error") or String.starts_with?(reason, "offline")

  defp blocking_reason?(_reason), do: false

  @http_refused 400..499
  @not_delivered [:econnrefused, :nxdomain, :ehostunreach, :enetunreach]

  @doc """
  Returns whether a request that failed definitely wasn't accepted, so sending it again (for
  example to another printer) can't print it twice.

  Takes any error `send_operation/2`, `send_operation/4` or `send_message/3` returns, including
  HTTP problems:

  | Error | Safe to resend? |
  |---|---|
  | `Hippy.Error` (the printer answered with an IPP error, e.g. not accepting jobs) | yes |
  | `Hippy.HTTPError` with a 4xx status (e.g. 401, 403, 404, 426) | yes |
  | `Hippy.HTTPError` with a 5xx status (a server or proxy error, which can happen after the job was accepted) | no |
  | `Req.TransportError` for a connection that was never made (refused, host not found, unreachable, TLS handshake failed) | yes |
  | `Req.TransportError` for a timeout or a closed connection, which may have been received | no |
  | errors from before anything is sent, such as `{:unknown_operation, name}` | yes |
  | anything else | no |

  When it returns `false`, the job may have printed: check (e.g. with Get-Jobs) before sending it
  again.
  """
  def safe_to_resend?(%Hippy.Error{}), do: true
  def safe_to_resend?(%Hippy.HTTPError{status: status}), do: status in @http_refused
  def safe_to_resend?(%Req.TransportError{reason: reason}) when reason in @not_delivered, do: true
  def safe_to_resend?(%Req.TransportError{reason: {:tls_alert, _}}), do: true
  def safe_to_resend?(:printer_uri_required), do: true
  def safe_to_resend?({:unknown_operation, _}), do: true
  def safe_to_resend?({:unsupported_uri_scheme, _}), do: true
  def safe_to_resend?(_error), do: false
end
