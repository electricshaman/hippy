# Hippy

Hippy is an [Internet Printing Protocol](https://en.wikipedia.org/wiki/Internet_Printing_Protocol)  (IPP) client implementation in Elixir for performing distributed printing over HTTP.  In addition to printing documents, IPP also supports a number of other operations such as retrieving print job status, pausing jobs, resuming jobs, etc.

[CUPS](https://en.wikipedia.org/wiki/CUPS) provides a standard IPP server out of the box, though some higher-end networked printers are also capable of providing their own server.  That said, testing at this early stage has been 100% against CUPS, which is likely more tolerant of any outstanding abuses of the protocol in Hippy alpha versions. ;)

## Obligatory Warning
This is currently very alpha-stage software and will be evolving quickly.  Please only consider it for production use at your own risk.

## Installation

Add `hippy` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hippy, "~> 0.6.0"}
  ]
end
```

## What you can do with it

Hippy talks to any IPP printer directly, or to a CUPS server in front of them. Combined with Elixir's concurrency, that makes it easy to look after a whole fleet.

### Check a fleet of printers at once

Ask every printer for its state at the same time. Each request gives up after five seconds, so one unplugged printer doesn't hold up the rest:

```elixir
defmodule MyApp.Fleet do
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
end
```

Then report the ones that need attention. Any error once a request is sent is an exception, so `Exception.message/1` describes it:

```elixir
fleet = [
  "ipps://front-desk.local/ipp/print",
  "ipps://warehouse.local/ipp/print",
  "ipps://loading-dock.local/ipp/print"
]

fleet
|> MyApp.Fleet.status()
|> Enum.each(fn
  {_uri, {:ok, %{"printer-state" => :idle, "printer-state-reasons" => ["none"],
                 "printer-is-accepting-jobs" => true}}} ->
    :ok

  {uri, {:ok, printer}} ->
    IO.puts("#{uri}: #{printer["printer-state"]} " <>
      "(#{Enum.join(printer["printer-state-reasons"], ", ")})")

  {uri, {:error, error}} ->
    IO.puts("#{uri}: #{Exception.message(error)}")
end)

# ipps://front-desk.local/ipp/print: stopped (media-empty-error)
# ipps://warehouse.local/ipp/print: idle (toner-low-report)
# ipps://loading-dock.local/ipp/print: connection refused
```

### Send each job to the least busy printer

Add a `print/2` to `MyApp.Fleet` that picks the ready printer with the shortest queue (`Hippy.printer_ready?/1` checks it's accepting jobs and has no errors such as a paper jam), and moves on to the next one if that printer refuses the job. `Hippy.safe_to_resend?/1` decides that for any error, including HTTP problems: it doesn't move on after a timeout, because the printer may have accepted the job anyway, and trying another would print it twice.

```elixir
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
```

```elixir
MyApp.Fleet.print(fleet, label_pdf)
# {:ok, "ipps://warehouse.local/ipp/print", 1042}
```

### Print a document and wait for it to finish

```elixir
defmodule MyApp.Printing do
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
        Process.sleep(1_000)
        wait_for_job(job_id, printer_uri)
    end
  end
end

document = File.read!("invoice.pdf")
MyApp.Printing.print_and_wait("ipps://front-desk.local/ipp/print", document)
# {:completed, 47}
```

These examples are run against a real CUPS server in Hippy's integration tests. Behind a CUPS server, `Hippy.Operation.CupsGetPrinters` lists its printers (see below).

## Configuration

Hippy uses [Req](https://hex.pm/packages/req) for HTTP and requires Elixir 1.15 or later. Extra Req options (authentication, TLS settings, timeouts, etc.) can be passed per request, or for every request through application config. Options given per request are merged over the configured ones:

```elixir
config :hippy, req_options: [receive_timeout: 30_000]
```

```elixir
Hippy.send_operation(op, req_options: [auth: {:basic, "user:pass"}])
```

Enum attributes are decoded to atoms for common attributes such as `job-state` and `orientation-requested`, and left as integers otherwise. To decode other enum attributes (e.g. vendor extensions), define an enum and register it by attribute name. Registered enums take precedence over the built-in ones, and `xxx-default` and `xxx-supported` use the enum registered for `xxx`:

```elixir
defmodule MyApp.VendorState do
  use Hippy.IPP.Enum, %{idle: 0x01, busy: 0x02}
end

config :hippy, enums: %{
  "x-vendor-state" => MyApp.VendorState,
  "input-orientation-requested" => Hippy.IPP.Orientation
}
```

### Errors

An IPP error (a client-error or server-error status) is returned as `{:error, %Hippy.Error{}}`, with the status, the server's status message and the whole response:

```elixir
{:error, %Hippy.Error{status: :client_error_document_format_not_supported} = error} =
  Hippy.Operation.PrintJob.new(printer_uri, doc, document_format: "application/x-nope")
  |> Hippy.send_operation()

Hippy.Message.unsupported(error.response)
%{"document-format" => "application/x-nope"}
```

HTTP errors (such as 401 Unauthorized) are `{:error, %Hippy.HTTPError{status: 401}}`, and a printer that can't be reached or times out gives Req's exceptions, such as `{:error, %Req.TransportError{reason: :timeout}}`. Every error once a request is sent is an exception, so `Exception.message/1` describes it.

**`{:ok, response}` doesn't mean every setting was applied.** A printer can accept a job but ignore or change attributes it doesn't support, for example printing one-sided when asked for `two-sided-long-edge`. It then returns `:successful_ok_ignored_or_substituted_attributes`, which is still `{:ok, response}`, and lists the attributes in the response's unsupported group. When the settings matter, check it:

```elixir
{:ok, res} = Hippy.send_operation(op)

case Hippy.Message.unsupported(res) do
  empty when map_size(empty) == 0 -> :printed_as_asked
  ignored -> {:printed_without, ignored}   # e.g. %{"sides" => "two-sided-long-edge"}
end
```

## Authentication, TLS and timeouts

### Authentication

Printers and CUPS servers that require authentication return an HTTP error instead of an IPP response, as `{:error, %Hippy.HTTPError{status: 401}}`. Pass credentials with `req_options: [auth: {:basic, "user:pass"}]`, over HTTPS (an `https://` or `ipps://` printer URI).

With its default policy, CUPS lets anyone print and query, but job management such as Cancel-Job needs authentication when the request comes from another machine:

| Request | Result |
|---|---|
| Cancel-Job over plain HTTP | `{:error, %Hippy.HTTPError{status: 426}}` (Upgrade Required: use HTTPS) |
| Cancel-Job over HTTPS without credentials | `{:error, %Hippy.HTTPError{status: 401}}` |
| Cancel-Job for another user's job | `{:error, %Hippy.HTTPError{status: 403}}` |
| Cancel-Job for your own job, authenticated | `{:ok, %Hippy.Message{}}`, with `Hippy.Message.status/1` `:successful_ok` |

### Self-signed certificates

Certificates are verified by default. CUPS and many printers use a self-signed certificate, which fails verification with `{:error, %Req.TransportError{reason: {:tls_alert, {:bad_certificate, _}}}}`. Erlang doesn't accept a self-signed server certificate as trusted through `cacertfile` or `cacerts`, so either:

- give the server a certificate signed by a CA you trust, and pass the CA with `connect_options: [transport_opts: [cacertfile: "ca.pem"]]`, or
- pin the server's own certificate (for CUPS, `/etc/cups/ssl/<hostname>.crt`):

```elixir
[{:Certificate, pinned, _}] = "cups.crt" |> File.read!() |> :public_key.pem_decode()

verify_fun = fn
  cert, {:bad_cert, :selfsigned_peer}, state ->
    if :public_key.pkix_encode(:OTPCertificate, cert, :otp) == pinned,
      do: {:valid, state},
      else: {:fail, :selfsigned_peer}

  _cert, {:bad_cert, _} = reason, _state -> {:fail, reason}
  _cert, {:extension, _}, state -> {:unknown, state}
  _cert, _valid, state -> {:valid, state}
end

Hippy.send_operation(op,
  req_options: [connect_options: [transport_opts: [verify_fun: {verify_fun, nil}]]]
)
```

`transport_opts: [verify: :verify_none]` turns verification off entirely. Only use it for testing, since it lets anyone on the network impersonate the printer and read the documents you send.

### Timeouts and retries

Req waits 15 seconds for a response by default. Sending a large document to a slow printer can take longer, so raise it with `timeout: 60_000`, which sets both the connect and the response timeout.

A timeout returns `{:error, %Req.TransportError{reason: :timeout}}`, but **the printer may still have accepted the job**. Hippy never retries a request, so a Print-Job is never submitted twice by accident. Don't blindly resend after a timeout either: check whether the job exists first, e.g. with `Hippy.Operation.GetJobs.new(uri, which_jobs: :not_completed)` and a unique `job_name`. `Hippy.safe_to_resend?/1` tells you which errors are safe to resend, for any error `send_operation` returns: IPP and HTTP 4xx errors, refused connections and failed TLS handshakes are; timeouts, closed connections and HTTP 5xx errors aren't.

## Usage Examples

### Print a PDF document

```elixir
printer_uri = "http://localhost:631/printers/HP_Color_LaserJet"

{:ok, res} =
  "tps_report.pdf"
  |> File.read!()
  |> then(&Hippy.Operation.PrintJob.new(printer_uri, &1, job_name: "TPS Report"))
  |> Hippy.send_operation()

Hippy.Message.job(res)
%{
  "job-id" => 47,
  "job-state" => :pending,
  "job-state-message" => "",
  "job-state-reasons" => ["none"],
  "job-uri" => %URI{scheme: "ipp", host: "localhost", port: 631, path: "/jobs/47", ...}
}
```

### Stream a large document

A document can also be an `Enumerable` of binaries, which is sent as it's read (with chunked transfer encoding) instead of being loaded into memory:

```elixir
# Elixir 1.16 and later. On 1.15, File.stream!("big.pdf", [], 64_000).
"big.pdf"
|> File.stream!(64_000)
|> then(&Hippy.Operation.PrintJob.new(printer_uri, &1, document_format: "application/pdf"))
|> Hippy.send_operation()
```

Some embedded printers may not accept chunked requests; for those, read the file into a binary first.

### Send other attributes

Every operation accepts `attributes:`, a map of attribute names to values. Hippy looks each one up in the [IANA IPP registry](https://www.iana.org/assignments/ipp-registrations/) to work out its syntax and which group it goes in, so `copies` and `sides` go in the job attributes and `job-name` in the operation attributes:

```elixir
Hippy.Operation.PrintJob.new(printer_uri, doc,
  attributes: %{
    "job-name" => "TPS Report",
    "document-format" => "application/pdf",
    "copies" => 2,
    "sides" => "two-sided-long-edge",
    "orientation-requested" => :landscape,
    "media-col" => %{"media-size" => %{"x-dimension" => 21000, "y-dimension" => 29700}},
    # Subscription attributes go in their own group: get notified when the job completes.
    "notify-pull-method" => "ippget",
    "notify-events" => ["job-completed"]
  }
)
|> Hippy.send_operation()
```

Maps are collections and lists are sets. For attributes that can be a keyword or a name (such as `media`), a value spelt like a keyword is sent as one, and anything else as a name. `{syntax, value}` gives the syntax explicitly, and is needed for attributes the registry doesn't know, which go in the operation's main group (job attributes for Print-Job). See "Attributes as maps" in the `Hippy` docs.

To control the syntax and group yourself, every operation also accepts `operation_attributes:`, and Print-Job `job_attributes:`, as `{syntax, name, value}` tuples. Other attribute groups go in `groups:`, as `{tag, tuples}`. These replace an attribute of the same name from `attributes:` or Hippy's defaults. See `Hippy.Message.encode/1` for the supported syntaxes.

```elixir
Hippy.Operation.PrintJob.new(printer_uri, doc,
  job_attributes: [{:integer, "copies", 2}, {:keyword, "x-acme-finish", "matte"}],
  groups: [
    {:subscription,
     [{:keyword, "notify-pull-method", "ippget"}, {:keyword, "notify-events", "job-completed"}]}
  ]
)
```

### Send any operation

`Hippy.send_operation/4` sends any IPP or CUPS operation by name (see `Hippy.IPP.Operation`), with attributes as a map. A job URI is sent as the job the operation is about, and CUPS's server-wide operations go to the server:

```elixir
Hippy.send_operation(printer_uri, :validate_job, %{"document-format" => "application/pdf", "copies" => 2})

Hippy.send_operation("ipp://localhost:631/jobs/47", :hold_job, %{}, req_options: [auth: {:basic, "user:pass"}])

Hippy.send_operation("ipp://localhost:631/", :cups_get_printers, %{"limit" => 10})

# Administration is sent to /admin/, about a printer.
Hippy.send_operation("ipps://localhost:631/printers/front_desk", :cups_add_modify_printer,
  %{
    "printer-uri" => "ipp://localhost/printers/front_desk",
    "device-uri" => {:uri, "socket://10.0.0.5"},
    "printer-info" => "Front desk"
  },
  endpoint: "https://localhost:631/admin/",
  req_options: [auth: {:basic, "admin:pass"}]
)
```

### Get recently completed jobs

```elixir
{:ok, res} =
  "http://localhost:631/printers/HP_Color_LaserJet"
  |> Hippy.Operation.GetJobs.new()
  |> Hippy.send_operation()

Hippy.Message.jobs(res)
[
  %{"job-id" => 47, "job-name" => "TPS Report", "job-state" => :completed, ...},
  %{"job-id" => 46, "job-name" => "Untitled Job", "job-state" => :completed, ...}
]
```

### List the printers on a CUPS server

CUPS-Get-Printers is sent to the server rather than a printer. CUPS includes classes in the results; `printer_type: 0, printer_type_mask: 1` leaves them out, and `Hippy.Operation.CupsGetClasses` returns only classes. `Hippy.Operation.CupsGetDefault` returns the default printer.

```elixir
{:ok, res} =
  "ipp://localhost:631/"
  |> Hippy.Operation.CupsGetPrinters.new(requested_attributes: ["printer-name", "printer-state"])
  |> Hippy.send_operation()

Hippy.Message.printers(res)
[
  %{"printer-name" => "HP_Color_LaserJet", "printer-state" => :idle},
  %{"printer-name" => "Label_Printer", "printer-state" => :stopped}
]
```

## Reading responses

A response is a `Hippy.Message`, holding the message exactly as the printer sent it. Read its attributes as maps of names to values:

- `Hippy.Message.job/1`: the job, for responses about one job, such as Print-Job and Get-Job-Attributes.
- `Hippy.Message.jobs/1`: a map per job, for Get-Jobs.
- `Hippy.Message.printer/1`: the printer, for Get-Printer-Attributes.
- `Hippy.Message.printers/1`: a map per printer, for CUPS-Get-Printers.
- `Hippy.Message.operation_attributes/1` and `Hippy.Message.unsupported/1`: operation attributes (such as `status-message`) and attributes the printer didn't support.
- `Hippy.Message.group/2` and `Hippy.Message.groups/2`: any group, by tag.
- `Hippy.Message.status/1`: the status, e.g. `:successful_ok`.

In maps, values are converted for convenience: enums are atoms, URIs are `URI`s, dates are `DateTime`s, booleans are `true`/`false` and collections are maps. Attributes and collection members the IANA registry defines as sets, such as `job-state-reasons`, are always lists, even with one value.

The message itself is the wire: groups in the order they were sent, each attribute as `{name, [{syntax, value}, ...]}` with values exactly as sent, so nothing is lost or reinterpreted, and encoding it again gives the same bytes:

```elixir
%Hippy.Message{
  version: {1, 1},
  code: 0x0000,
  request_id: 1,
  groups: [
    {:operation, [{"attributes-charset", [charset: "utf-8"]}, ...]},
    {:job, [{"job-id", [integer: 47]}, {"job-state", [enum: 3]}, {"job-state-reasons", [keyword: "none"]}, ...]}
  ],
  data: ""
}

bin |> Hippy.Message.decode() |> Hippy.Message.encode() == bin
true
```

## Development

Run the unit tests with `mix test`.

Integration tests run Hippy against a real CUPS server in a throwaway Docker container (see `test/integration/cups/`). They are excluded by default and need a running Docker daemon:

```
mix test --only cups
```

`Hippy.IPP.Attributes` is generated from the [IANA IPP registry](https://www.iana.org/assignments/ipp-registrations/) into `lib/ipp/attributes.eterm`, and the enum values in `Hippy.IPP` are checked against a copy of it in `test/fixtures/ipp_registry.json`. To pick up new registrations, regenerate both and run the tests to see what's missing:

```
mix run scripts/update_ipp_registry.exs
mix test test/ipp_registry_test.exs
```

## Copyright and License

Copyright (c) 2018-2026 Jeff Smith

Hippy source code is licensed under the [MIT License].

[//]: #
[MIT License]: <https://github.com/electricshaman/hippy/blob/master/LICENSE>
