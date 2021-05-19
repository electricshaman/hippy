defmodule Hippy.Operation.CupsGetPPDs do
  @moduledoc """
  Represents a request returns all of the locally available PPD files on the system.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CupsGetPPDs do
  def build_request(op) do
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    %Hippy.Request{
      # Should request_id be a parameter to build_request?
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.cups_get_ppds(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target}
      ],
      data: <<>>
    }
  end
end
