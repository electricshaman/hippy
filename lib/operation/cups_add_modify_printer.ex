defmodule Hippy.Operation.CupsAddModifyPrinter do
  @moduledoc """
  Represents a request to add a new printer or modifies and existing printer on the system.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            device_uri: nil,
            ppd_name: nil,
            accepting_jobs: false

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      device_uri: Keyword.get(opts, :device_uri, ""),
      ppd_name: Keyword.get(opts, :ppd_name, ""),
      accepting_jobs: Keyword.get(opts, :accepting_jobs, false)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CupsAddModifyPrinter do
  def build_request(op) do
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    %Hippy.Request{
      # Should request_id be a parameter to build_request?
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.cups_add_modify_printer(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target}
      ],
      printer_attributes: [
        {:boolean, "printer-is-accepting-jobs", op.accepting_jobs},
        {:uri, "device-uri", op.device_uri},
        {:name_without_language, "ppd-name", op.ppd_name}
      ],
      data: <<>>
    }
  end
end
