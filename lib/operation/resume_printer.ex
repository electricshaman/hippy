defmodule Hippy.Operation.ResumePrinter do
  @moduledoc """
  Resumes a printer paused with `Hippy.Operation.PausePrinter`.

  CUPS only lets administrators do this (see "Authentication" in the README).

  Extra attributes can be given with `attributes:` (a map, see "Attributes as maps" in `Hippy`),
  or as `{syntax, name, value}` tuples with `operation_attributes:` (see `Hippy.Message.encode/1`).
  Each replaces an attribute of the same name that Hippy would otherwise send.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{}

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{})
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.ResumePrinter do
  def build_request(op) do
    Hippy.IPP.Operation.resume_printer()
    |> Hippy.Message.build_request(op)
  end
end
