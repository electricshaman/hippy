defmodule Hippy do
  @moduledoc """
  IPP client API.

  Functions that send a request over the network are named `send_*`. Everything else, such as
  building operations (`Hippy.Operation.PrintJob.new/3`), encoding and decoding, and reading
  responses (`Hippy.Response`), has no side effects.
  """

  @doc """
  Sends an operation struct (such as `Hippy.Operation.PrintJob`) to a printer. See
  `Hippy.Server.send_operation/2` for the options.
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
  Each attribute's syntax and group come from the IANA registry (see `Hippy.AttributeInference`).

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
      `{syntax, name, value}`, as for operations (see `Hippy.Request`).
    * `:charset` and `:language` - default to `"utf-8"` and `"en"`.
    * `:req_options`, `:endpoint` and `:raw`, as for `send_operation/2`.

  Returns the same results as `send_operation/2`, or `{:error, {:unknown_operation, name}}` for
  an operation name Hippy doesn't know (in which case nothing is sent).
  """
  defdelegate send_operation(uri, operation, attributes, opts \\ []), to: Hippy.Server
end
