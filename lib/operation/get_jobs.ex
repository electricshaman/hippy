defmodule Hippy.Operation.GetJobs do
  @moduledoc """
  Represents a request to get print jobs for a printer on the IPP server.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_jobs :completed
  @def_atts ["all"]

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
    Hippy.Request.new(Hippy.Protocol.Operation.get_jobs(), op, [
      {:keyword, "which-jobs", op.which_jobs |> to_string() |> String.replace("_", "-")},
      {{:set1, :keyword}, "requested-attributes", op.requested_attributes}
    ])
  end
end
