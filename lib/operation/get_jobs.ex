defmodule Hippy.Operation.GetJobs do
  @moduledoc """
  Represents a request to get print jobs for a printer on the IPP server.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_jobs :completed
  @def_atts [
    "job-id",
    "job-state",
    "job-state-reasons",
    "job-name",
    "job-originating-user-name",
    "job-media-sheets-completed"
  ]

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            which_jobs: @def_jobs,
            requested_attributes: @def_atts

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      which_jobs: Keyword.get(opts, :which_jobs, @def_jobs),
      requested_attributes: Keyword.get(opts, :requested_attributes, @def_atts)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.GetJobs do
  def build_request(op) do
    target =
      URI.parse(op.printer_uri)
      |> Map.put(:scheme, "ipp")
      |> to_string()

    %Hippy.Request{
      # Should request_id be a parameter to build_request?
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.get_jobs(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target},
        {:keyword, "which-jobs", to_string(op.which_jobs)},
        {{:set1, :keyword}, "requested-attributes", op.requested_attributes}
      ],
      data: <<>>
    }
  end
end
