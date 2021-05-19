defmodule Hippy.Operation.CupsGetPrinters do
  @moduledoc """
  Represents a request to get printers for a printer on the IPP server.
  """

  import Bitwise

  @def_charset "utf-8"
  @def_lang "en"

#  @printer_and_class_mask 0x00000002 ||| 0x00000001
  @printer_and_class_mask  0x00000001

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            limit: nil,
            printer_type_mask: nil

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      limit: Keyword.get(opts, :limit, 1000),
      printer_type_mask: Keyword.get(opts, :printer_type_mask, @printer_and_class_mask)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CupsGetPrinters do
  def build_request(op) do
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    %Hippy.Request{
      # Should request_id be a parameter to build_request?
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.cups_get_printers(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target},
        {:integer, "limit", op.limit},
        {:enum, "printer-type-mask", op.printer_type_mask}
      ],
      data: <<>>
    }
  end
end
