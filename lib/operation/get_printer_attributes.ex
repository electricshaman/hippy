defmodule Hippy.Operation.GetPrinterAttributes do
  @moduledoc """
  Represents a request to get the values of the attributes of a printer.

  `:requested_attributes` limits the response to the attributes (or groups of attributes, such
  as `"printer-description"`) listed, e.g. `requested_attributes: ["printer-state"]`. Printers
  return all of them by default.

  Extra attributes can be sent with the `:operation_attributes` option, as `{syntax, name, value}`
  tuples (see `Hippy.Message.encode/1`). Each replaces an attribute of the same name that Hippy
  would otherwise send.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{},
            requested_attributes: nil

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{}),
      requested_attributes: Keyword.get(opts, :requested_attributes)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.GetPrinterAttributes do
  def build_request(op) do
    requested =
      if op.requested_attributes,
        do: [{{:set1, :keyword}, "requested-attributes", op.requested_attributes}],
        else: []

    Hippy.IPP.Operation.get_printer_attributes()
    |> Hippy.Message.build_request(op, requested)
  end
end
