defmodule Hippy.Operation.GetPrinterAttributes do
  @moduledoc """
  Represents a request to get the values of the attributes of a printer.
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

defimpl Hippy.Operation, for: Hippy.Operation.GetPrinterAttributes do
  def build_request(op) do
    Hippy.Request.new(Hippy.Protocol.Operation.get_printer_attributes(), op)
  end
end
