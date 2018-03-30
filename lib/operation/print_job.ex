defmodule Hippy.Operation.PrintJob do
  @moduledoc """
  Represents a request to print a document using a printer on the IPP server.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_job_name "Untitled Job"

  @enforce_keys [:printer_uri, :document]

  defstruct printer_uri: nil,
            document: nil,
            charset: @def_charset,
            language: @def_lang,
            job_name: @def_job_name

  def new(printer_uri, document, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      document: document,
      job_name: Keyword.get(opts, :job_name, @def_job_name),
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang)
    }
  end
end

defimpl Hippy.OperationRequest, for: Hippy.Operation.PrintJob do
  def build_request(op) do
    target =
      URI.parse(op.printer_uri)
      |> Map.put(:scheme, "ipp")
      |> to_string()

    %Hippy.Request{
      # Should request_id be a parameter to build_request?
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.print_job(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target},
        {:name_without_language, "job-name", op.job_name}
      ],
      data: op.document
    }
  end
end
