defmodule Hippy.Operation.ValidateJob do
  @moduledoc """
  Asks a printer whether it would accept a print job, without sending a document or printing
  anything.

  It takes the same options as `Hippy.Operation.PrintJob` (apart from the document) and sends the
  same attributes, so if Validate-Job succeeds, the same Print-Job should be accepted. A printer
  that wouldn't accept it returns an IPP error, such as
  `:client_error_document_format_not_supported`, and `Hippy.Message.unsupported/1` on the error's
  response lists the attributes it doesn't support:

      uri
      |> ValidateJob.new(
        document_format: "application/pdf",
        attributes: %{"sides" => "two-sided-long-edge"}
      )
      |> Hippy.send_operation()
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_job_name "Untitled Job"
  @def_orientation Hippy.IPP.Orientation.portrait()

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{},
            job_attributes: [],
            job_name: @def_job_name,
            document_format: nil,
            orientation: @def_orientation

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      job_name: Keyword.get(opts, :job_name, @def_job_name),
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{}),
      job_attributes: Keyword.get(opts, :job_attributes, []),
      document_format: Keyword.get(opts, :document_format),
      orientation: Keyword.get(opts, :orientation, @def_orientation)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.ValidateJob do
  def build_request(op) do
    Hippy.IPP.Operation.validate_job()
    |> Hippy.Message.build_request(
      op,
      [{:name_without_language, "job-name", op.job_name}] ++ document_format(op),
      job_attributes: [{:enum, "orientation-requested", op.orientation}]
    )
  end

  defp document_format(%{document_format: nil}), do: []
  defp document_format(op), do: [{:mime_media_type, "document-format", op.document_format}]
end
