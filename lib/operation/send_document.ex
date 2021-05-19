defmodule Hippy.Operation.SendDocument do
  @moduledoc """
  Represents a request to cancel a print job from the time it's created up to the time
  it's completed, canceled, or aborted.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_username "hippy"
  @def_mime_media_type "application/octet-stream"

  @enforce_keys [:printer_uri, :job_id, :document]

  defstruct printer_uri: nil,
            job_id: nil,
            document: nil,
            charset: @def_charset,
            language: @def_lang,
            username: @def_username,
            document_name: nil,
            mime_type: @def_mime_media_type,
            last_document: true

  def new(printer_uri, job_id, document, opts \\ []) do
    default_name = generate_name()

    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      job_id: job_id,
      document: document,
      document_name: Keyword.get(opts, :document_name, "doc-" <> default_name),
      username: Keyword.get(opts, :username, @def_username),
      mime_type: Keyword.get(opts, :mime_type, @def_mime_media_type),
      last_document: Keyword.get(opts, :last_document, true)
    }
  end

  defp generate_name, do: DateTime.to_iso8601(DateTime.utc_now(), :basic)
end

defimpl Hippy.Operation, for: Hippy.Operation.SendDocument do
  def build_request(op) do
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    #    Hexate.encode(op.document) |> IO.puts()

    %Hippy.Request{
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.cancel_job(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target},
        {:integer, "job-id", op.job_id},
        {:name_without_language, "document-name", op.document_name},
        {:name_without_language, "requesting-user-name", op.username},
        {:mime_media_type, "document-format", op.mime_type},
        {:boolean, "last-document", op.last_document}
      ],
      data: op.document
    }
  end
end
