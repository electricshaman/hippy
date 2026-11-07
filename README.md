# Hippy

Hippy is an [Internet Printing Protocol](https://en.wikipedia.org/wiki/Internet_Printing_Protocol) (IPP) client for Elixir. IPP is how computers talk to printers over the network: almost every network printer made in the last decade speaks it, and so does [CUPS](https://en.wikipedia.org/wiki/CUPS), the print server on macOS and Linux. With Hippy you can print documents, follow jobs, ask printers how they're doing, and manage queues, whether that's one printer on your Wi-Fi or a fleet of them.

Hippy is pre-1.0, so its API can still change between minor versions (see the [changelog](CHANGELOG.md)). It's tested against a real CUPS server and an emulated driverless printer.

## Installation

Add `hippy` to your dependencies in `mix.exs`. It needs Elixir 1.15 or later.

```elixir
def deps do
  [
    {:hippy, "~> 0.7.0"}
  ]
end
```

## Quick start

First you need your printer's URI. Driverless printers usually answer at `ipp://<printer-address>/ipp/print`. Find the address in the printer's network settings, or run `dns-sd -B _ipp._tcp` on a Mac or `avahi-browse -rt _ipp._tcp` on Linux. A printer shared by CUPS is at `ipp://<cups-host>:631/printers/<queue-name>`.

Ask the printer about itself, print a PDF, then check on the job:

```elixir
alias Hippy.Operation.{GetJobAttributes, GetPrinterAttributes, PrintJob}

printer = "ipp://192.168.1.50/ipp/print"

{:ok, res} = printer |> GetPrinterAttributes.new() |> Hippy.send_operation()

res |> Hippy.Message.printer() |> Map.take(["printer-make-and-model", "printer-state"])
#=> %{"printer-make-and-model" => "Example LaserJet 400", "printer-state" => :idle}

{:ok, res} =
  "invoice.pdf"
  |> File.read!()
  |> then(&PrintJob.new(printer, &1, document_format: "application/pdf", job_name: "Invoice"))
  |> Hippy.send_operation()

job_id = res |> Hippy.Message.job() |> Map.fetch!("job-id")

{:ok, res} = printer |> GetJobAttributes.new(job_id) |> Hippy.send_operation()
Hippy.Message.job(res)["job-state"]
#=> :processing
```

Ask again later and it will be `:completed`. "Print a document and wait for it to finish" below does that for you.

## How it fits together

Every call above has the same three steps: **build** an operation, **send** it, **read** the response.

| | |
|---|---|
| **Build** | `Hippy.Operation.PrintJob.new/3`, `GetPrinterAttributes.new/2`, `GetJobs.new/2`, … are plain data, with no side effects. |
| **Send** | `Hippy.send_operation/2` sends an operation. Functions named `send_*` are the only ones that touch the network. |
| **Read** | `Hippy.Message.job/1`, `printer/1`, `jobs/1`, `status/1`, … turn the response into maps with string keys. |

When something goes wrong you get `{:error, exception}`: `Hippy.Error` if the printer refused, `Hippy.HTTPError` for an HTTP problem, or one of Req's exceptions if it couldn't be reached. Two helpers decide what to do next: `Hippy.printer_ready?/1` says whether a printer can take a job, and `Hippy.safe_to_resend?/1` whether a failed request can be sent again without printing twice.

The operations Hippy has modules for cover the common tasks. `Hippy.send_operation/4` sends any of the 118 IPP and CUPS operations in `Hippy.IPP.Operation` by name.

## Things to build

These examples are run against a CUPS server and an emulated driverless printer in Hippy's integration tests, so they work as written.

### Draw your ink levels in the terminal

Printers report each cartridge's level and colour in `printer-supply`, as strings like `"type=toner;level=75;maxcapacity=100;colorantname=black;"`. Turn them into bars in the ink's own colour:

```elixir
defmodule MyApp.Ink do
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
```

```elixir
{:ok, gauge} = MyApp.Ink.gauge("ipp://192.168.1.50/ipp/print")
IO.puts(gauge)
```

```
Black Toner        ███████████████░░░░░ 75%
Toner Waste Tank   █████░░░░░░░░░░░░░░░ 25% full
```

### Print a full-page Mandelbrot set, using hardly any ink

Hippy sends whatever bytes you give it, so you can write the PDF yourself. This one is a single page of ASCII art: the Mandelbrot set in 6-point Courier, 150 characters by 120 lines. To save ink it's light grey, and only the bands around the edge of the set are drawn, in the lightest characters. Most of the page stays blank.

```elixir
defmodule MyApp.Mandelbrot do
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
```

```elixir
MyApp.Mandelbrot.print("ipp://192.168.1.50/ipp/print")
```

Here's the whole page in miniature, every third line and every other character (`MyApp.Mandelbrot.lines()` returns it all):

```
               .......,,,,,,,,................,,,,,,,,.......
           .,,~::,,,:;~+**-~=**~~::,,,,,,::~~**=~-**+~;:,,,::~,,.
         .,********--****         **~;;~**         ****--********,.
       ...,::~**                     **                     **~::,...
     ....,,,:~-***                                        ***-~:,,,....
   .....,,:;****                                            ****;:,,.....
 .....,,::;~+*                                                *+~;::,,.....
,,,:--*-~--=*                                                  *=--~-*--:,,
*~;~-**     *                                                  *     **-~;~
+***                                                                    ***
~~-***                                                                ***-~
:::~****** **                                                  ** ******~::
..,,;*~;~~-=*                                                  *=-~~;~*;,,.
.....,,:::;-*                                                  *-;:::,,....
  ....,,,::;-=**                                            **=-;::,,,....
    ...,,,:;-**                                              **-;:,,,...
      ...,:~**** ***                                    *** ****~:,...
        ..,-=~*~~~=*                                    *=~~~*~=-,..
          ..,,,,::;=**+* **                      ** *+**=;::,,,,..
           ...,,,,,::;;;--=+********    ********+=--;;;::,,,,,...
            .....,,,,::;;~~-=**              **=-~~;;::,,,,.....
             ......,,,::;~-**                  **-~;::,,,......
              ......,,::;-**                    **-;::,,......
               ......,:-=**                      **=-:,......
                .....,:;~-=**                  **=-~;:,.....
                 ....,::;=**                    **=;::,....
                  ..,,:;~*******            *******~;:,,..
                    ,;-=*-;;~~******    ******~~;;-*=-;,
                     .,,,,,::::~~+**    **+~~::::,,,,,.
                      .......,:;+*++****++*+;:,.......
                        .......,::;~=**=~;::,.......
                          ......,,::~==~::,,......
                             ....,,,;--;,,,....
                               ..,,,;--;,,,..
                                  .::--::.
                                   ,:--:,
                                   .,;;,.
                                   ..::..
                                    .,,.
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

### Check a fleet of printers at once

With more than one printer, Elixir's concurrency makes it easy to look after them all. Ask every printer for its state at the same time. Each request gives up after five seconds, so one unplugged printer doesn't hold up the rest:

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

## Everyday tasks

### Print with settings

Every operation takes `attributes:`, a map of attribute names to values. Hippy looks each one up in the [IANA IPP registry](https://www.iana.org/assignments/ipp-registrations/) to work out its type and where it goes in the request, so you don't need to know that `copies` is a job attribute and `job-name` an operation attribute:

```elixir
printer
|> PrintJob.new(document,
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

Maps are collections and lists are sets. For attributes that can be a keyword or a name (such as `media`), a value spelt like a keyword is sent as one, and anything else as a name. Attributes the registry doesn't know, such as vendor extensions, need their type: `"x-acme-finish" => {:keyword, "matte"}`. See "Attributes as maps" in the `Hippy` docs for the rules.

**A printer can accept a job without applying every setting.** If it doesn't support two-sided printing, for example, it may print one-sided and still succeed, with the status `:successful_ok_ignored_or_substituted_attributes`. When the settings matter, check what it ignored:

```elixir
{:ok, res} = Hippy.send_operation(op)

case Hippy.Message.unsupported(res) do
  empty when map_size(empty) == 0 -> :printed_as_asked
  ignored -> {:printed_without, ignored}   # e.g. %{"sides" => "two-sided-long-edge"}
end
```

### Stream a large document

A document can be an `Enumerable` of binaries, which is sent as it's read (with chunked transfer encoding) instead of being loaded into memory:

```elixir
# Elixir 1.16 and later. On 1.15, File.stream!("big.pdf", [], 64_000).
"big.pdf"
|> File.stream!(64_000)
|> then(&PrintJob.new(printer, &1, document_format: "application/pdf"))
|> Hippy.send_operation()
```

Some embedded printers don't accept chunked requests. For those, read the file into a binary first.

### List jobs

```elixir
{:ok, res} = printer |> Hippy.Operation.GetJobs.new() |> Hippy.send_operation()

Hippy.Message.jobs(res)
#=> [
#=>   %{"job-id" => 47, "job-name" => "TPS Report", "job-state" => :completed, ...},
#=>   %{"job-id" => 46, "job-name" => "Untitled Job", "job-state" => :completed, ...}
#=> ]
```

By default you get completed jobs. `which_jobs: :not_completed` gives the ones still pending or printing.

### Check, hold and pause

Ask whether a printer would accept a job before sending it, without printing anything. It takes the same options as `PrintJob`, and a printer that wouldn't accept it returns an IPP error saying why:

```elixir
printer
|> Hippy.Operation.ValidateJob.new(
  document_format: "application/pdf",
  attributes: %{"sides" => "two-sided-long-edge"}
)
|> Hippy.send_operation()
```

`HoldJob` keeps a job in the queue until `ReleaseJob`, and `PausePrinter` stops a printer until `ResumePrinter`. `CreateJob` and `SendDocument` build one job from several documents. CUPS only lets a job's owner hold, release or add documents to it, and administrators pause printers (see [Authentication](#authentication)).

### List the printers on a CUPS server

CUPS-Get-Printers is sent to the server rather than a printer. CUPS includes classes in the results; `printer_type: 0, printer_type_mask: 1` leaves them out, and `Hippy.Operation.CupsGetClasses` returns only classes. `Hippy.Operation.CupsGetDefault` returns the default printer.

```elixir
{:ok, res} =
  "ipp://localhost:631/"
  |> Hippy.Operation.CupsGetPrinters.new(requested_attributes: ["printer-name", "printer-state"])
  |> Hippy.send_operation()

Hippy.Message.printers(res)
#=> [
#=>   %{"printer-name" => "HP_Color_LaserJet", "printer-state" => :idle},
#=>   %{"printer-name" => "Label_Printer", "printer-state" => :stopped}
#=> ]
```

### Send any other operation

`Hippy.send_operation/4` sends any IPP or CUPS operation by name (see `Hippy.IPP.Operation`), with attributes as a map. A job URI is sent as the job the operation is about, and CUPS's server-wide operations go to the server:

```elixir
Hippy.send_operation(printer, :validate_job, %{"document-format" => "application/pdf", "copies" => 2})

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

For complete control over a request, every operation also takes `operation_attributes:`, `job_attributes:` and `groups:`, with each attribute's syntax given explicitly as `{syntax, name, value}`. These replace an attribute of the same name from `attributes:` or Hippy's defaults (see `Hippy.Message.encode/1` for the syntaxes):

```elixir
PrintJob.new(printer, document,
  job_attributes: [{:integer, "copies", 2}, {:keyword, "x-acme-finish", "matte"}],
  groups: [
    {:subscription,
     [{:keyword, "notify-pull-method", "ippget"}, {:keyword, "notify-events", "job-completed"}]}
  ]
)
```

Or build a `%Hippy.Message{}` yourself (see `Hippy.Message.build_request/4`) and send it with `Hippy.send_message/3`.

## When things go wrong

Sending returns `{:ok, %Hippy.Message{}}` or `{:error, exception}`, so `Exception.message/1` describes any error:

| Error | When |
|---|---|
| `%Hippy.Error{status: ..., message: ..., response: ...}` | The printer answered with an IPP error, such as `:client_error_not_found` or `:server_error_not_accepting_jobs`. The whole response is kept. |
| `%Hippy.HTTPError{status: ...}` | The server answered with an HTTP error instead, such as 401 Unauthorized. |
| `%Req.TransportError{reason: ...}` | It couldn't be reached (`:econnrefused`), or didn't answer in time (`:timeout`). |

```elixir
{:error, %Hippy.Error{status: :client_error_document_format_not_supported} = error} =
  printer
  |> PrintJob.new(document, document_format: "application/x-nope")
  |> Hippy.send_operation()

Hippy.Message.unsupported(error.response)
#=> %{"document-format" => "application/x-nope"}
```

### Timeouts, and never printing twice

Req waits 15 seconds for a response by default. Sending a large document to a slow printer can take longer, so raise it with `timeout: 60_000`, which sets both the connect and the response timeout.

A timeout returns `{:error, %Req.TransportError{reason: :timeout}}`, but **the printer may still have accepted the job**. Hippy never retries a request, so a job is never submitted twice by accident. Before you resend one yourself, ask `Hippy.safe_to_resend?/1`:

| Safe to resend | Not safe: the job may have printed |
|---|---|
| IPP errors (`Hippy.Error`) | Timeouts |
| HTTP 4xx errors | Closed connections |
| Refused connections, unknown hosts | HTTP 5xx errors |
| Failed TLS handshakes | |

When it isn't safe, check whether the job exists first, e.g. with `GetJobs.new(printer, which_jobs: :not_completed)` and a unique `job_name`. That's why the fleet example above stops, rather than trying the next printer, after an error that isn't safe to resend.

## Connecting

Hippy uses [Req](https://hex.pm/packages/req) for HTTP. Pass Req options for one request with `req_options:`, or for every request in your config. Options given per request are merged over the configured ones:

```elixir
config :hippy, req_options: [receive_timeout: 30_000]
```

```elixir
Hippy.send_operation(op, req_options: [auth: {:basic, "user:pass"}])
```

### Authentication

Printers and CUPS servers that require authentication answer with an HTTP error, `{:error, %Hippy.HTTPError{status: 401}}`. Pass credentials with `req_options: [auth: {:basic, "user:pass"}]`, over HTTPS (an `https://` or `ipps://` printer URI).

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

## Reading responses

A response is a `Hippy.Message`. Read its attributes as maps of names to values:

- `Hippy.Message.job/1`: the job, for responses about one job, such as Print-Job and Get-Job-Attributes.
- `Hippy.Message.jobs/1`: a map per job, for Get-Jobs.
- `Hippy.Message.printer/1`: the printer, for Get-Printer-Attributes.
- `Hippy.Message.printers/1`: a map per printer, for CUPS-Get-Printers.
- `Hippy.Message.operation_attributes/1` and `Hippy.Message.unsupported/1`: operation attributes (such as `status-message`) and attributes the printer didn't support.
- `Hippy.Message.group/2` and `Hippy.Message.groups/2`: any group, by tag.
- `Hippy.Message.status/1`: the status, e.g. `:successful_ok`.

In maps, values are converted for convenience: enums are atoms, URIs are `URI`s, dates are `DateTime`s, booleans are `true`/`false` and collections are maps. Attributes and collection members the IANA registry defines as sets, such as `job-state-reasons`, are always lists, even with one value.

Underneath, the message is exactly what was sent over the wire: groups in order, each attribute as `{name, [{syntax, value}, ...]}` with values as sent. Nothing is lost or reinterpreted, and encoding it again gives the same bytes:

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
#=> true
```

### Vendor enums

Enum attributes are decoded to atoms for common attributes such as `job-state` and `orientation-requested`, and left as integers otherwise. To decode others, such as vendor extensions, define an enum and register it by attribute name. Registered enums take precedence over the built-in ones, and `xxx-default` and `xxx-supported` use the enum registered for `xxx`:

```elixir
defmodule MyApp.VendorState do
  use Hippy.IPP.Enum, %{idle: 0x01, busy: 0x02}
end

config :hippy, enums: %{
  "x-vendor-state" => MyApp.VendorState,
  "input-orientation-requested" => Hippy.IPP.Orientation
}
```

## Development

Run the unit tests with `mix test`.

Integration tests run Hippy against a real CUPS server and `ippeveprinter`, CUPS's emulated driverless printer, in a throwaway Docker container (see `test/integration/cups/`). They are excluded by default and need a running Docker daemon:

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
