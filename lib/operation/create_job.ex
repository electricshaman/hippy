defmodule Hippy.Operation.CreateJob do
  @moduledoc """
  Represents a request to create a print job
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_username "hippy"
  @def_mime_media_type "application/octet-stream"

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            job_name: nil,
            username: @def_username,
            charset: @def_charset,
            language: @def_lang,
            job_attributes: %{},
            document_name: nil,
            mime_type: @def_mime_media_type

  def new(printer_uri, opts \\ []) do
    default_name = generate_name()

    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      job_name: Keyword.get(opts, :job_name, "job-" <> default_name),
      username: Keyword.get(opts, :username, @def_username),
      job_attributes: Keyword.get(opts, :job_attributes, %{}),
      document_name: Keyword.get(opts, :document_name, "doc-" <> default_name),
      mime_type: Keyword.get(opts, :mime_type, @def_mime_media_type)
    }
  end

  defp generate_name, do: DateTime.to_iso8601(DateTime.utc_now(), :basic)
end

defimpl Hippy.Operation, for: Hippy.Operation.CreateJob do
  def build_request(op) do
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    %Hippy.Request{
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.create_job(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target},
        {:name_without_language, "requesting-user-name", op.username},
        {:name_without_language, "job-name", op.job_name},
        {:name_without_language, "document-name", op.document_name},
        {:mime_media_type, "document-format", op.mime_type}
      ],
      job_attributes: process_job_attributes(op.job_attributes),
      data: <<>>
    }
  end

  defp process_job_attributes(attrs) do
    Enum.map(attrs, fn {k, v} ->
      case {k, v} do
        {k, v} when is_integer(v) -> {:integer, k, v}
        {k, v} -> {:keyword, k, v}
      end
    end)
  end
end
