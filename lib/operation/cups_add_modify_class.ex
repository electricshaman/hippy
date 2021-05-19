defmodule Hippy.Operation.CupsAddModifyClass do
  @moduledoc """
  Represents a request to add a new printer class or modifies and existing printer class on the system.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            member_uris: [],
            accepting_jobs: false

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      member_uris: Keyword.get(opts, :member_uris, []),
      accepting_jobs: Keyword.get(opts, :accepting_jobs, false)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CupsAddModifyClass do
  def build_request(op) do
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    %Hippy.Request{
      # Should request_id be a parameter to build_request?
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.cups_add_modify_class(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target}
      ],
#      printer_attributes: [
#        {:boolean, "printer-is-accepting-jobs", op.accepting_jobs},
#        {{:set1, :uri}, "member-uris", op.member_uris}
#      ],
      data: <<>>
    }
  end
end
