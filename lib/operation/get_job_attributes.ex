defmodule Hippy.Operation.GetJobAttributes do
  @moduledoc """
  Represents a request to get job attributes for an existing job for a printer on the IPP server.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_atts ["all"]

  @enforce_keys [:printer_uri, :job_id]

  defstruct printer_uri: nil,
            job_id: nil,
            charset: @def_charset,
            language: @def_lang,
            requested_attributes: @def_atts

  def new(printer_uri, job_id, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      job_id: job_id,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      requested_attributes: Keyword.get(opts, :requested_attributes, @def_atts)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.GetJobAttributes do
  def build_request(op) do
    Hippy.Request.new(Hippy.Protocol.Operation.get_job_attributes(), op, [
      {:integer, "job-id", op.job_id},
      {{:set1, :keyword}, "requested-attributes", op.requested_attributes}
    ])
  end
end
