defmodule Hippy.Operation.GetJobs do
  @moduledoc """
  Represents a request to get print jobs for a printer on the IPP server.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_jobs :completed
  @def_atts ["all"]
  @def_username "hippy"

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            which_jobs: @def_jobs,
            requested_attributes: @def_atts,
            username: @def_username,
            my_jobs: false

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      which_jobs: Keyword.get(opts, :which_jobs, @def_jobs),
      requested_attributes: Keyword.get(opts, :requested_attributes, @def_atts),
      username: Keyword.get(opts, :username, @def_username),
      my_jobs: Keyword.get(opts, :my_jobs, false)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.GetJobs do
  def build_request(op) do
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    %Hippy.Request{
      # Should request_id be a parameter to build_request?
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.get_jobs(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target},
        {:keyword, "which-jobs", to_string(op.which_jobs)},
        {{:set1, :keyword}, "requested-attributes", op.requested_attributes},
        {:name_without_language, "requesting-user-name", op.username},
        {:boolean, "my-jobs", op.my_jobs}
      ],
      data: <<>>
    }
  end
end
