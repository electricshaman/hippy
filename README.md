# Hippy

Hippy is an [Internet Printing Protocol](https://en.wikipedia.org/wiki/Internet_Printing_Protocol)  (IPP) client implementation in Elixir for performing distributed printing over HTTP.  In addition to printing documents, IPP also supports a number of other operations such as retrieving print job status, pausing jobs, resuming jobs, etc.

[CUPS](https://en.wikipedia.org/wiki/CUPS) provides a standard IPP server out of the box, though some higher-end networked printers are also capable of providing their own server.  That said, testing at this early stage has been 100% against CUPS, which is likely more tolerant of any outstanding abuses of the protocol in Hippy alpha versions. ;)

## Obligatory Warning
This is currently very alpha-stage software and will be evolving quickly.  Please only consider it for production use at your own risk.

## Usage Examples

### Print a PDF document
```elixir
doc = File.read!("tps_report.pdf") 
printer_uri = "http://localhost:631/printers/HP_Color_LaserJet"

Hippy.Operation.PrintJob.new(printer_uri, doc, job_name: "TPS Report")
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

### Convert the response to a map for easier access by key

Note: this helper currently doesn't support nested attribute groups such as when returning multiple jobs through the `Get-Jobs` IPP operation.  If given a list of attribute groups, it will return the group at the head of the list.  If you wish to access other groups in the list, you can use `AttributeGroup.to_map/2` to provide an index for the nested group at the target index.

```elixir
response = %Hippy.Response{
  data: "",
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
  printer_attributes: [],
  request_id: 1,
  status_code: :successful_ok,
  unknown_attributes: [],
  version: %Hippy.IPPVersion{major: 1, minor: 1}
}

Hippy.AttributeGroup.to_map(response.job_attributes)
%{
  "job-id" => 47,
  "job-state" => :pending,
  "job-state-message" => "",
  "job-state-reasons" => "none",
  "job-uri" => "ipp://localhost:631/jobs/47"
}
```

## Copyright and License

Copyright (c) 2018 Jeff Smith

Hippy source code is licensed under the [MIT License].

[//]: #
[MIT License]: <https://github.com/electricshaman/hippy/blob/master/LICENSE>
