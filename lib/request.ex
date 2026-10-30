defmodule Hippy.Request do
  @moduledoc """
  An IPP request, built from an operation by `Hippy.Operation.build_request/1`.

  `request_id` is assigned by `Hippy.Server` when the request is sent, unless it's already set.
  """

  defstruct version: Hippy.IPPVersion.new(1, 1),
            operation_id: nil,
            request_id: nil,
            operation_attributes: [],
            job_attributes: [],
            data: <<>>

  @doc """
  Builds a request for an operation on a printer.

  Adds the operation attributes every request starts with (`attributes-charset`,
  `attributes-natural-language` and `printer-uri`) from the operation's `charset`, `language`
  and `printer_uri` fields, followed by `attributes`. Operations addressed to the server rather
  than a printer (with no `printer_uri` field) get no `printer-uri` attribute. Other request fields, such as
  `job_attributes` and `data`, can be given in `fields`.

  Attributes in the operation's `operation_attributes` and `job_attributes` fields, if it has
  them, are added to the matching group. Each replaces an attribute of the same name, so callers
  can override the defaults.
  """
  def new(operation_id, op, attributes \\ [], fields \\ []) do
    operation_attributes =
      ([
         {:charset, "attributes-charset", op.charset},
         {:natural_language, "attributes-natural-language", op.language}
       ] ++ printer_uri(op) ++ attributes)
      |> merge(Map.get(op, :operation_attributes, []))

    job_attributes =
      fields
      |> Keyword.get(:job_attributes, [])
      |> merge(Map.get(op, :job_attributes, []))

    struct!(
      %__MODULE__{
        operation_id: operation_id,
        operation_attributes: operation_attributes,
        job_attributes: job_attributes
      },
      Keyword.delete(fields, :job_attributes)
    )
  end

  # http and https map to the ipp and ipps schemes in the printer-uri attribute.
  defp printer_uri(%{printer_uri: uri}),
    do: [{:uri, "printer-uri", String.replace(uri, ~r/^http/, "ipp")}]

  defp printer_uri(_op), do: []

  defp merge(attributes, overrides) do
    Enum.reduce(overrides, attributes, fn {_syntax, name, _value} = override, acc ->
      if List.keymember?(acc, name, 1) do
        List.keyreplace(acc, name, 1, override)
      else
        acc ++ [override]
      end
    end)
  end
end
