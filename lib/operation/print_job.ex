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
            job_name: @def_job_name,
            job_attributes: %{}

  def new(printer_uri, document, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      document: document,
      job_name: Keyword.get(opts, :job_name, @def_job_name),
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      job_attributes: Keyword.get(opts, :job_attributes, %{})
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.PrintJob do
  def build_request(op) do
    IO.inspect(op)
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    Hexate.encode(op.document) |> IO.puts()

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
      job_attributes: process_job_attributes(op.job_attributes),
      data: op.document
    }
  end

  def process_job_attributes(attrs) do
    Enum.map(attrs, fn {k, v} ->
      case {k, v} do
        {k, v} when is_integer(v) -> {:integer, k, v}
        {k, v} -> {:keyword, k, v}
      end
    end)
  end
end
