defmodule Hippy.Operation.SendDocument do
  @moduledoc """
  Adds a document to a job created with `Hippy.Operation.CreateJob`.

  The document is a binary, or an `Enumerable` of binaries sent as it's read, as for
  `Hippy.Operation.PrintJob`.

  ## Options

    * `:last_document` - whether this is the job's last document, after which it prints.
      Defaults to `true`.
    * `:document_format` - the MIME media type of the document, e.g. `"application/pdf"`. When
      not given, the printer decides.
    * `:document_name` - a name for the document.
    * `:charset` and `:language` - default to `"utf-8"` and `"en"`.
    * `:attributes` and `:operation_attributes` - extra attributes, as for the other operations.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri, :job_id, :document]

  defstruct printer_uri: nil,
            job_id: nil,
            document: nil,
            last_document: true,
            document_format: nil,
            document_name: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{}

  def new(printer_uri, job_id, document, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      job_id: job_id,
      document: document,
      last_document: Keyword.get(opts, :last_document, true),
      document_format: Keyword.get(opts, :document_format),
      document_name: Keyword.get(opts, :document_name),
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{})
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.SendDocument do
  def build_request(op) do
    Hippy.IPP.Operation.send_document()
    |> Hippy.Message.build_request(
      op,
      [{:integer, "job-id", op.job_id}, {:boolean, "last-document", op.last_document}] ++
        optional(:mime_media_type, "document-format", op.document_format) ++
        optional(:name_without_language, "document-name", op.document_name),
      data: op.document
    )
  end

  defp optional(_syntax, _name, nil), do: []
  defp optional(syntax, name, value), do: [{syntax, name, value}]
end
