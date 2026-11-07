defmodule Hippy.Message do
  @moduledoc """
  An IPP message, exactly as it's sent: a request or a response.

      %Hippy.Message{
        version: {1, 1},
        code: 0x0000,
        request_id: 1,
        groups: [
          {:operation, [{"attributes-charset", [charset: "utf-8"]}]},
          {:printer, [
            {"printer-state", [enum: 3]},
            {"media-supported", [keyword: "iso_a4_210x297mm", name_without_language: "Custom"]}
          ]}
        ],
        data: <<>>
      }

    * `:code` is the operation id in a request and the status code in a response. `status/1` and
      `operation/1` return them as atoms.
    * `:groups` is an ordered list of `{tag, attributes}`. A tag can repeat (one `:job` or
      `:printer` group per job or printer). Tags are `:operation`, `:job`, `:printer`,
      `:unsupported`, `:subscription`, `:event_notification`, `:resource`, `:document` and
      `:system`, or the tag number for tags IANA hasn't assigned.
    * Each attribute is `{name, values}`, and each value carries its own syntax, so a set can mix
      syntaxes. Values are as on the wire: enums and booleans are integers, URIs are strings, and
      dates, resolutions and ranges are tuples. Out-of-band values (such as `:no_value`) have the
      value `nil`, and value tags Hippy doesn't know keep their tag number and bytes. A collection
      is `{:collection, [{member, values}]}`, in order.
    * `:data` is the document: a binary, or when sending, an `Enumerable` of binaries.

  `encode(decode(binary)) == binary` for any message.
  """

  defstruct version: {1, 1}, code: nil, request_id: nil, groups: [], data: <<>>

  @tags %{
    operation: 0x01,
    job: 0x02,
    printer: 0x04,
    unsupported: 0x05,
    subscription: 0x06,
    event_notification: 0x07,
    resource: 0x08,
    document: 0x09,
    system: 0x0A
  }
  @tag_names Map.new(@tags, fn {name, number} -> {number, name} end)

  @out_of_band [
    :unsupported,
    :unknown,
    :no_value,
    :not_settable,
    :delete_attribute,
    :admin_define
  ]

  @doc "Decodes a message from its binary form."
  def decode(bin) do
    parsed = Hippy.Decoder.parse(bin)

    %__MODULE__{
      version: parsed.version,
      code: parsed.code,
      request_id: parsed.request_id,
      groups:
        for({tag, attributes} <- parsed.groups, do: {tag_name(tag), attributes(attributes)}),
      data: parsed.data
    }
  end

  @doc """
  Encodes a message into its binary form, or a stream when `data` is an `Enumerable` (see
  `Hippy.Encoder.encode/1`).
  """
  def encode(%__MODULE__{} = message), do: Hippy.Encoder.encode(message)

  @doc "Returns a response's status as an atom, or the integer if Hippy doesn't know it."
  def status(%__MODULE__{code: code}) do
    case Hippy.IPP.StatusCode.decode(code) do
      {:ok, status} -> status
      {:error, _} -> code
    end
  end

  @doc "Returns a request's operation as an atom, or the integer if Hippy doesn't know it."
  def operation(%__MODULE__{code: code}) do
    case Hippy.IPP.Operation.decode(code) do
      {:ok, operation} -> operation
      {:error, _} -> code
    end
  end

  @doc false
  def tag_number(tag) when is_integer(tag), do: tag

  def tag_number(tag) do
    case Map.fetch(@tags, tag) do
      {:ok, number} -> number
      :error -> raise ArgumentError, "unknown attribute group #{inspect(tag)}"
    end
  end

  defp tag_name(number), do: Map.get(@tag_names, number, number)

  # Attribute tuples from the parser have a nil name for each additional value of the previous
  # attribute.
  defp attributes(tuples) do
    tuples
    |> Enum.reduce([], fn
      {syntax, nil, value}, [{name, values} | acc] ->
        [{name, [value(syntax, value) | values]} | acc]

      {syntax, name, value}, acc ->
        [{name, [value(syntax, value)]} | acc]
    end)
    |> Enum.reduce([], fn {name, values}, acc -> [{name, Enum.reverse(values)} | acc] end)
  end

  defp value(:collection, members) do
    {:collection,
     for {member, values} <- members do
       {member,
        values |> List.wrap() |> Enum.map(fn {syntax, _, value} -> value(syntax, value) end)}
     end}
  end

  defp value(syntax, _value) when syntax in @out_of_band, do: {syntax, nil}
  defp value(syntax, value), do: {syntax, value}
end
