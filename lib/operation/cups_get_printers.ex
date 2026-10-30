defmodule Hippy.Operation.CupsGetPrinters do
  @moduledoc """
  Represents a CUPS-Get-Printers request, which lists the printers and classes on a CUPS server.

  It is sent to the server rather than a printer:

      Hippy.Operation.CupsGetPrinters.new("ipp://localhost:631/",
        requested_attributes: ["printer-name", "printer-state"]
      )
      |> Hippy.send_operation()

  CUPS includes classes in the results; see `:printer_type` below to exclude them, or use
  `Hippy.Operation.CupsGetClasses` for classes only.

  ## Options

    * `:requested_attributes` - defaults to `["all"]`.
    * `:limit` - the maximum number to return.
    * `:first_printer_name` - start the list at this name (for paging with `:limit`).
    * `:printer_location` - only return those with this `printer-location`.
    * `:printer_type` and `:printer_type_mask` - only return those whose `printer-type` bits,
      masked with `:printer_type_mask`, equal `:printer_type`. See `Hippy.IPP.PrinterType` for
      the bits. For example `printer_type: 0, printer_type_mask: 1` excludes classes.
    * `:charset`, `:language` and `:operation_attributes`, as for other operations.

  The response has one group of printer attributes per result; use `Hippy.Response.printers/1`.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_atts ["all"]

  @enforce_keys [:server_uri]

  defstruct server_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{},
            requested_attributes: @def_atts,
            limit: nil,
            first_printer_name: nil,
            printer_location: nil,
            printer_type: nil,
            printer_type_mask: nil

  def new(server_uri, opts \\ []) do
    %__MODULE__{
      server_uri: server_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{}),
      requested_attributes: Keyword.get(opts, :requested_attributes, @def_atts),
      limit: Keyword.get(opts, :limit),
      first_printer_name: Keyword.get(opts, :first_printer_name),
      printer_location: Keyword.get(opts, :printer_location),
      printer_type: Keyword.get(opts, :printer_type),
      printer_type_mask: Keyword.get(opts, :printer_type_mask)
    }
  end

  @doc false
  # The filter attributes shared by CUPS-Get-Printers and CUPS-Get-Classes.
  def filter_attributes(op) do
    [
      {{:set1, :keyword}, "requested-attributes", op.requested_attributes},
      {:integer, "limit", op.limit},
      {:name_without_language, "first-printer-name", op.first_printer_name},
      {:text_without_language, "printer-location", op.printer_location},
      {:enum, "printer-type", op.printer_type},
      {:enum, "printer-type-mask", op.printer_type_mask}
    ]
    |> Enum.reject(fn {_syntax, _name, value} -> is_nil(value) end)
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CupsGetPrinters do
  def build_request(op) do
    Hippy.Request.new(
      Hippy.IPP.Operation.cups_get_printers(),
      op,
      Hippy.Operation.CupsGetPrinters.filter_attributes(op)
    )
  end
end
