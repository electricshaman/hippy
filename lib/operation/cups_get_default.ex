defmodule Hippy.Operation.CupsGetDefault do
  @moduledoc """
  Represents a CUPS-Get-Default request, which returns the default printer on a CUPS server.

  It is sent to the server rather than a printer, e.g. `CupsGetDefault.new("ipp://localhost:631/")`.
  Use `Hippy.Response.printer/1` on the response. When no default is set, CUPS returns
  `:client_error_not_found`.

  Takes `:requested_attributes` (defaults to `["all"]`), `:charset`, `:language` and
  `:operation_attributes`, as for other operations.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_atts ["all"]

  @enforce_keys [:server_uri]

  defstruct server_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            requested_attributes: @def_atts

  def new(server_uri, opts \\ []) do
    %__MODULE__{
      server_uri: server_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      requested_attributes: Keyword.get(opts, :requested_attributes, @def_atts)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CupsGetDefault do
  def build_request(op) do
    Hippy.Request.new(Hippy.IPP.Operation.cups_get_default(), op, [
      {{:set1, :keyword}, "requested-attributes", op.requested_attributes}
    ])
  end
end
