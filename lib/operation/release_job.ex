defmodule Hippy.Operation.ReleaseJob do
  @moduledoc """
  Releases a job held with `Hippy.Operation.HoldJob` (or created with `job-hold-until`), so it
  can print.

  With CUPS's default policy, only the job's owner (or an administrator) can do this, so send it
  authenticated, over HTTPS (see "Authentication" in the README).

  Extra attributes can be given with `attributes:` (a map, see "Attributes as maps" in `Hippy`),
  or as `{syntax, name, value}` tuples with `operation_attributes:` (see `Hippy.Message.encode/1`).
  Each replaces an attribute of the same name that Hippy would otherwise send.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri, :job_id]

  defstruct printer_uri: nil,
            job_id: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{}

  def new(printer_uri, job_id, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      job_id: job_id,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{})
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.ReleaseJob do
  def build_request(op) do
    Hippy.IPP.Operation.release_job()
    |> Hippy.Message.build_request(op, [{:integer, "job-id", op.job_id}])
  end
end
