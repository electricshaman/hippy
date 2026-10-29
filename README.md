# Hippy

Hippy is an [Internet Printing Protocol](https://en.wikipedia.org/wiki/Internet_Printing_Protocol)  (IPP) client implementation in Elixir for performing distributed printing over HTTP.  In addition to printing documents, IPP also supports a number of other operations such as retrieving print job status, pausing jobs, resuming jobs, etc.

[CUPS](https://en.wikipedia.org/wiki/CUPS) provides a standard IPP server out of the box, though some higher-end networked printers are also capable of providing their own server.  That said, testing at this early stage has been 100% against CUPS, which is likely more tolerant of any outstanding abuses of the protocol in Hippy alpha versions. ;)

## Obligatory Warning
This is currently very alpha-stage software and will be evolving quickly.  Please only consider it for production use at your own risk.

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
  use Hippy.Protocol.Enum, %{idle: 0x01, busy: 0x02}
end

config :hippy, enums: %{
  "x-vendor-state" => MyApp.VendorState,
  "input-orientation-requested" => Hippy.Protocol.Orientation
}
```

## Usage Examples

### Print a PDF document
```elixir
doc = File.read!("tps_report.pdf") 
printer_uri = "http://localhost:631/printers/HP_Color_LaserJet"

Hippy.Operation.PrintJob.new(printer_uri, doc,
  job_name: "TPS Report",
  document_format: "application/pdf",
  orientation: Hippy.Protocol.Orientation.portrait()
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

### Convert the response to maps for easier access by key

`Hippy.Response` has functions that return attributes as maps of names to values:

```elixir
{:ok, res} = Hippy.Operation.PrintJob.new(printer_uri, doc) |> Hippy.send_operation()

Hippy.Response.job(res)
%{
  "job-id" => 47,
  "job-state" => :pending,
  "job-state-message" => "",
  "job-state-reasons" => "none",
  "job-uri" => %URI{scheme: "ipp", host: "localhost", port: 631, path: "/jobs/47", ...}
}

Hippy.Response.job(res)["job-id"]
47
```

- `Hippy.Response.job/1`: the job, for responses about one job, such as Print-Job and Get-Job-Attributes.
- `Hippy.Response.jobs/1`: a map per job, for Get-Jobs.
- `Hippy.Response.printer/1`: printer attributes, for Get-Printer-Attributes.
- `Hippy.Response.operation/1` and `Hippy.Response.unsupported/1`: operation attributes (such as `status-message`) and attributes the printer didn't support.

Attributes with several values are lists. `Hippy.AttributeGroup.to_map/1` converts any list of attribute tuples the same way.

## Development

Run the unit tests with `mix test`.

Integration tests run Hippy against a real CUPS server in a throwaway Docker container (see `test/integration/cups/`). They are excluded by default and need a running Docker daemon:

```
mix test --only cups
```

## Copyright and License

Copyright (c) 2018-2026 Jeff Smith

Hippy source code is licensed under the [MIT License].

[//]: #
[MIT License]: <https://github.com/electricshaman/hippy/blob/master/LICENSE>
