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
    {:hippy, "~> 0.5.0"}
  ]
end
```

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

## Authentication, TLS and timeouts

### Authentication

Printers and CUPS servers that require authentication return an HTTP error instead of an IPP response, as `{:error, {:http_error, status, body}}`. Pass credentials with `req_options: [auth: {:basic, "user:pass"}]`, over HTTPS (an `https://` or `ipps://` printer URI).

With its default policy, CUPS lets anyone print and query, but job management such as Cancel-Job needs authentication when the request comes from another machine:

| Request | Result |
|---|---|
| Cancel-Job over plain HTTP | `{:error, {:http_error, 426, _}}` (Upgrade Required: use HTTPS) |
| Cancel-Job over HTTPS without credentials | `{:error, {:http_error, 401, _}}` |
| Cancel-Job for another user's job | `{:error, {:http_error, 403, _}}` |
| Cancel-Job for your own job, authenticated | `{:ok, %Hippy.Response{status_code: :successful_ok}}` |

### Self-signed certificates

Certificates are verified by default. CUPS and many printers use a self-signed certificate, which fails verification with `{:error, %Req.TransportError{reason: {:tls_alert, {:bad_certificate, _}}}}`. Erlang doesn't accept a self-signed server certificate as trusted through `cacertfile` or `cacerts`, so either:

- give the server a certificate signed by a CA you trust, and pass the CA with `connect_options: [transport_opts: [cacertfile: "ca.pem"]]`, or
- pin the server's own certificate (for CUPS, `/etc/cups/ssl/<hostname>.crt`):

```elixir
[{:Certificate, pinned, _}] = :public_key.pem_decode(File.read!("cups.crt"))

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

Req waits 15 seconds for a response by default. Sending a large document to a slow printer can take longer, so raise it with `req_options: [receive_timeout: 60_000]`.

A timeout returns `{:error, %Req.TransportError{reason: :timeout}}`, but **the printer may still have accepted the job**. Hippy never retries a request, so a Print-Job is never submitted twice by accident. Don't blindly resend after a timeout either: check whether the job exists first, e.g. with `Hippy.Operation.GetJobs.new(uri, which_jobs: :not_completed)` and a unique `job_name`.

## Usage Examples

### Print a PDF document
```elixir
doc = File.read!("tps_report.pdf") 
printer_uri = "http://localhost:631/printers/HP_Color_LaserJet"

Hippy.Operation.PrintJob.new(printer_uri, doc,
  job_name: "TPS Report",
  document_format: "application/pdf",
  orientation: Hippy.IPP.Orientation.portrait()
)
|> Hippy.send_operation()

{:ok,
 %Hippy.Response{
   job_attributes: [
     [
       {:uri, "job-uri", "ipp://localhost:631/jobs/47"},
       {:integer, "job-id", 47},
       {:enum, "job-state", :pending},
       {:text_without_language, "job-state-message", ""},
       {:keyword, "job-state-reasons", "none"}
     ]
   ],
   operation_attributes: [
     [
       {:charset, "attributes-charset", "utf-8"}, 
       {:natural_language, "attributes-natural-language", "en"}
     ]
   ],
   request_id: 1,
   status_code: :successful_ok,
   version: %Hippy.IPPVersion{major: 1, minor: 1}
 }}
```
### Send other attributes

Every operation accepts `operation_attributes:`, and Print-Job also accepts `job_attributes:`, for attributes Hippy doesn't have an option for. They're `{syntax, name, value}` tuples, in the same form responses are decoded to, and replace an attribute of the same name that Hippy would otherwise send. See `Hippy.Encoder.encode/1` for the supported syntaxes.

```elixir
a4 = %{"x-dimension" => {:integer, 21000}, "y-dimension" => {:integer, 29700}}

Hippy.Operation.PrintJob.new(printer_uri, doc,
  document_format: "application/pdf",
  job_attributes: [
    {:integer, "copies", 2},
    {:keyword, "sides", "two-sided-long-edge"},
    {:collection, "media-col", %{"media-size" => {:collection, a4}}}
  ]
)
|> Hippy.send_operation()
```

Other attribute groups go in `groups:`, as `{tag, attributes}`. For example, to be notified when the job completes:

```elixir
Hippy.Operation.PrintJob.new(printer_uri, doc,
  groups: [
    {:subscription_attributes,
     [{:keyword, "notify-pull-method", "ippget"}, {:keyword, "notify-events", "job-completed"}]}
  ]
)
```

### Get recently completed jobs
```elixir
Hippy.Operation.GetJobs.new("http://localhost:631/printers/HP_Color_LaserJet")
|> Hippy.send_operation()

{:ok,
 %Hippy.Response{
   job_attributes: [
     [
       {:name_without_language, "job-name", "TPS Report"},
       {:name_without_language, "job-originating-user-name", "anonymous"},
       {:integer, "job-id", 47},
       {:enum, "job-state", :completed},
       {:keyword, "job-state-reasons", "processing-to-stop-point"},
       {:integer, "job-media-sheets-completed", 8}
     ],
     [
       {:name_without_language, "job-name", "Untitled Job"},
       {:name_without_language, "job-originating-user-name", "anonymous"},
       {:integer, "job-id", 46},
       {:enum, "job-state", :completed},
       {:keyword, "job-state-reasons", "processing-to-stop-point"},
       {:integer, "job-media-sheets-completed", 2}
     ],
     # ...
   ],
   operation_attributes: [
     [
       {:charset, "attributes-charset", "utf-8"},
       {:natural_language, "attributes-natural-language", "en"},
       {:integer, "limit", 500}
     ]
   ],
   request_id: 1,
   status_code: :successful_ok,
   version: %Hippy.IPPVersion{major: 1, minor: 1}
 }}
```

### List the printers on a CUPS server

CUPS-Get-Printers is sent to the server rather than a printer. CUPS includes classes in the results; `printer_type: 0, printer_type_mask: 1` leaves them out, and `Hippy.Operation.CupsGetClasses` returns only classes. `Hippy.Operation.CupsGetDefault` returns the default printer.

```elixir
{:ok, res} =
  Hippy.Operation.CupsGetPrinters.new("ipp://localhost:631/",
    requested_attributes: ["printer-name", "printer-state"]
  )
  |> Hippy.send_operation()

Hippy.Response.printers(res)
[
  %{"printer-name" => "HP_Color_LaserJet", "printer-state" => :idle},
  %{"printer-name" => "Label_Printer", "printer-state" => :stopped}
]
```

### Convert the response to maps for easier access by key

`Hippy.Response` has functions that return attributes as maps of names to values:

```elixir
{:ok, res} = Hippy.Operation.PrintJob.new(printer_uri, doc) |> Hippy.send_operation()

Hippy.Response.job(res)
%{
  "job-id" => 47,
  "job-state" => :pending,
  "job-state-message" => "",
  "job-state-reasons" => ["none"],
  "job-uri" => %URI{scheme: "ipp", host: "localhost", port: 631, path: "/jobs/47", ...}
}

Hippy.Response.job(res)["job-id"]
47
```

- `Hippy.Response.job/1`: the job, for responses about one job, such as Print-Job and Get-Job-Attributes.
- `Hippy.Response.jobs/1`: a map per job, for Get-Jobs.
- `Hippy.Response.printer/1`: the printer, for Get-Printer-Attributes.
- `Hippy.Response.printers/1`: a map per printer, for CUPS-Get-Printers.
- `Hippy.Response.operation/1` and `Hippy.Response.unsupported/1`: operation attributes (such as `status-message`) and attributes the printer didn't support.

Attributes and collection members the IANA registry defines as sets, such as `job-state-reasons`, are always lists, even with one value. Other attributes are a single value, or a list if a printer sends several anyway. `Hippy.AttributeGroup.to_map/1` converts any list of attribute tuples the same way.

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
