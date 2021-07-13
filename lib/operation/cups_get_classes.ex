defmodule Hippy.Operation.CupsGetClasses do
  @moduledoc """
  Represents a request to get print classes on the IPP server.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @requested_attributes ["printer-name", "printer-uri-supported", "member-names"]

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            requested_attributes: @requested_attributes,
            printer_info: nil

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      requested_attributes: Keyword.get(opts, :requested_attributes, @requested_attributes),
#    printer_info: Keyword.get(opts, :printer_info, "")
      printer_info: "powerball"
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CupsGetClasses do
  def build_request(op) do
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    %Hippy.Request{
      # Should request_id be a parameter to build_request?
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.cups_get_classes(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target},
        {:text_without_language, "printer-info", op.printer_info}
      ],
      data: <<>>
    }
  end
end
