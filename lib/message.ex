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
      `operation_name/1` return them as atoms.
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

  ## Reading attributes

  `job/1`, `jobs/1`, `printer/1`, `printers/1`, `operation_attributes/1`, `unsupported/1`,
  `group/2` and `groups/2` return groups as maps of attribute names to values, with values
  converted for convenience: enums are atoms (see `Hippy.IPP.Enum`), URIs are `URI`s, dates are
  `DateTime`s, booleans are `true`/`false`, collections are maps, and attributes the IANA
  registry defines as sets are always lists.

  ## Building requests

  Operations build their request with `build_request/4`; `Hippy.send_operation/2` sends it.
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

  # Group names used by Hippy before 0.7 (and by attribute inference), accepted in groups:.
  @old_tags %{
    operation_attributes: :operation,
    job_attributes: :job,
    printer_attributes: :printer,
    unsupported_attributes: :unsupported,
    subscription_attributes: :subscription,
    event_notification_attributes: :event_notification,
    resource_attributes: :resource,
    document_attributes: :document,
    system_attributes: :system
  }

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
  Encodes a message into its binary form.

  A message's attributes are `{name, [{syntax, value}, ...]}`. Values can be in their wire form
  (as `Hippy.Message.decode/1` returns them) or one of these, as can the `{syntax, name, value}`
  tuples given to `Hippy.Message.build_request/4`:

    * `:integer` and `:enum` take integers, and `:boolean` takes booleans.
    * `:keyword`, `:uri`, `:mime_media_type`, `:text_without_language`, `:name_without_language`
      and the other string syntaxes take binaries. `:uri` also takes a `URI`.
    * `:text_with_language` and `:name_with_language` take `{language, text}`.
    * `:datetime` takes a `DateTime`, `:range_of_integer` a `Range`, and `:resolution` a
      `Hippy.PrintResolution`.
    * Out-of-band syntaxes (`:no_value`, `:delete_attribute`, `:not_settable`, `:admin_define`,
      `:unknown`, `:unsupported`) ignore the value, e.g. `{:delete_attribute, "job-hold-until", nil}`.
    * `:collection` takes a map of member names to `{syntax, value}` (or `{syntax, nil, value}`).
      A list of those encodes a multi-valued member.

  A list value is encoded as a multi-valued attribute, as is `{{:set1, syntax}, name, values}`.
  Raises `ArgumentError` for a value that can't be encoded.

  The message's `data` (the document) is a binary, or an `Enumerable` of binaries such as
  `File.stream!/2`. For a binary the whole message is returned as a binary. For an enumerable
  it's returned as a stream (the encoded attributes, then the document's chunks as they're
  read), so the document is never all in memory.
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
  def operation_name(%__MODULE__{code: code}) do
    case Hippy.IPP.Operation.decode(code) do
      {:ok, operation} -> operation
      {:error, _} -> code
    end
  end

  @doc """
  Builds a request message for an operation.

  For implementing `Hippy.Operation`: it adds the operation attributes every request starts
  with (`attributes-charset`, `attributes-natural-language` and, for operations with a
  `printer_uri` field, `printer-uri`) from the operation's `charset`, `language` and
  `printer_uri` fields, followed by `attributes`, given as `{syntax, name, value}` tuples (see
  `encode/1`).

  The operation's `attributes` field, a map of names to values, is placed and typed as described
  in "Attributes as maps" in the `Hippy` docs. Its `operation_attributes` and `job_attributes` fields are added
  to those groups, and its `groups` field as further groups. Each attribute replaces one of the
  same name, explicit ones last, so callers can override the defaults.

  ## Options

    * `:job_attributes` - job attributes the operation always sends, as tuples.
    * `:groups` - other groups, as `{tag, tuples}`.
    * `:data` - the document.
  """
  def build_request(operation_id, op, attributes \\ [], opts \\ []) do
    inferred = Hippy.AttributeInference.place(operation_id, Map.get(op, :attributes, %{}))

    operation =
      ([
         {:charset, "attributes-charset", op.charset},
         {:natural_language, "attributes-natural-language", op.language}
       ] ++ printer_uri(op) ++ attributes)
      |> merge(inferred.operation)
      |> merge(Map.get(op, :operation_attributes, []))

    job =
      opts
      |> Keyword.get(:job_attributes, [])
      |> merge(inferred.job)
      |> merge(Map.get(op, :job_attributes, []))

    groups = Keyword.get(opts, :groups, []) ++ inferred.groups ++ Map.get(op, :groups, [])

    %__MODULE__{
      code: operation_id,
      groups:
        [{:operation, from_tuples(operation)}] ++
          if(job == [], do: [], else: [{:job, from_tuples(job)}]) ++
          for({tag, tuples} <- groups, do: {normalize_tag(tag), from_tuples(tuples)}),
      data: Keyword.get(opts, :data, <<>>)
    }
  end

  # http and https map to the ipp and ipps schemes in the printer-uri attribute.
  defp printer_uri(%{printer_uri: uri}),
    do: [{:uri, "printer-uri", String.replace(uri, ~r/^http/, "ipp")}]

  defp printer_uri(_op), do: []

  defp merge(attributes, overrides) do
    Enum.reduce(overrides, attributes, fn
      {_syntax, nil, _value} = additional, acc ->
        acc ++ [additional]

      {_syntax, name, _value} = override, acc ->
        if List.keymember?(acc, name, 1),
          do: List.keyreplace(acc, name, 1, override),
          else: acc ++ [override]
    end)
  end

  defp normalize_tag(tag), do: Map.get(@old_tags, tag, tag)

  # {syntax, name, value} tuples to message attributes. A list value (or {:set1, syntax}) is a
  # set, and a tuple with a nil name is an additional value of the previous attribute. Values are
  # converted to their wire form, so built and decoded messages look the same.
  defp from_tuples(tuples) do
    tuples
    |> Enum.reduce([], fn
      {syntax, nil, value}, [{name, values} | acc] ->
        [{name, values ++ wire_values(syntax, value)} | acc]

      {syntax, name, value}, acc ->
        [{name, wire_values(syntax, value)} | acc]
    end)
    |> Enum.reverse()
  end

  defp wire_values({:set1, syntax}, values), do: wire_values(syntax, values)

  defp wire_values(syntax, values) when is_list(values) and syntax != :collection,
    do: Enum.map(values, &wire_value(syntax, &1))

  defp wire_values(:collection, [first | _] = values) when not is_tuple(first),
    do: Enum.map(values, &wire_value(:collection, &1))

  defp wire_values(syntax, value), do: [wire_value(syntax, value)]

  defp wire_value(syntax, _value) when syntax in @out_of_band, do: {syntax, nil}

  defp wire_value(:boolean, value) when is_boolean(value),
    do: {:boolean, if(value, do: 1, else: 0)}

  defp wire_value(:uri, %URI{} = uri), do: {:uri, URI.to_string(uri)}
  defp wire_value(:range_of_integer, first..last//_), do: {:range_of_integer, {first, last}}

  defp wire_value(:resolution, %Hippy.PrintResolution{xfeed: x, feed: f, unit: unit}),
    do: {:resolution, {x, f, Hippy.IPP.ResolutionUnit.encode!(unit)}}

  defp wire_value(:datetime, %DateTime{} = value) do
    offset = div(value.utc_offset + value.std_offset, 60)
    {deciseconds, _} = value.microsecond

    {:datetime,
     {value.year, value.month, value.day, value.hour, value.minute, value.second,
      div(deciseconds, 100_000), if(offset < 0, do: "-", else: "+"), div(abs(offset), 60),
      rem(abs(offset), 60)}}
  end

  # Collections: a map or ordered list of members, each {syntax, value}, {syntax, nil, value} or
  # a list of them.
  defp wire_value(:collection, members) when is_map(members),
    do: wire_value(:collection, Enum.sort(members))

  defp wire_value(:collection, members) when is_list(members) do
    {:collection,
     for {member, value} <- members do
       {member,
        value
        |> List.wrap()
        |> Enum.flat_map(fn
          {syntax, nil, v} -> wire_values(syntax, v)
          {syntax, v} -> wire_values(syntax, v)
          v -> raise ArgumentError, "invalid value #{inspect(v)} for member #{inspect(member)}"
        end)}
     end}
  end

  defp wire_value(syntax, value), do: {syntax, value}

  @doc """
  Returns the first job in a response as a map, or `nil` if there is none. For responses about
  a single job, such as Print-Job and Get-Job-Attributes.
  """
  def job(message), do: group(message, :job)

  @doc "Returns each job in a response as a map, such as for Get-Jobs."
  def jobs(message), do: groups(message, :job)

  @doc """
  Returns the first printer in a response as a map, or `nil` if there is none. For responses
  about a single printer, such as Get-Printer-Attributes.
  """
  def printer(message), do: group(message, :printer)

  @doc "Returns each printer in a response as a map, such as for CUPS-Get-Printers."
  def printers(message), do: groups(message, :printer)

  @doc "Returns the operation attributes as a map (e.g. `status-message`)."
  def operation_attributes(message), do: group(message, :operation) || %{}

  @doc """
  Returns the attributes the printer didn't support as a map, with the values that were sent.

  A printer can accept a request but ignore or change attributes it doesn't support (status
  `:successful_ok_ignored_or_substituted_attributes`), so check this when the settings matter.
  It's empty when every attribute was applied.
  """
  def unsupported(message), do: group(message, :unsupported) || %{}

  @doc "Returns the first group with a tag as a map, or `nil` if there is none."
  def group(%__MODULE__{groups: groups}, tag) do
    case List.keyfind(groups, tag, 0) do
      {^tag, attributes} -> to_map(attributes)
      nil -> nil
    end
  end

  @doc "Returns every group with a tag as a map, in order."
  def groups(%__MODULE__{groups: groups}, tag),
    do: for({^tag, attributes} <- groups, do: to_map(attributes))

  @doc """
  Returns a group's attributes as a map of names to values, converted for convenience (see
  "Reading attributes" above).
  """
  def to_map(attributes) do
    attributes
    |> to_tuples()
    |> Hippy.Decoder.interpret_group()
    |> Hippy.AttributeGroup.compact_group()
  end

  # Message attributes back to the parser's tuples: one per value, with a nil name for
  # additional values.
  defp to_tuples(attributes) do
    Enum.flat_map(attributes, fn {name, values} ->
      values
      |> Enum.map(&tuple_value/1)
      |> Enum.with_index(fn {syntax, value}, i -> {syntax, if(i == 0, do: name), value} end)
    end)
  end

  defp tuple_value({:collection, members}) do
    {:collection,
     for {member, values} <- members do
       tuples =
         for value <- values do
           {syntax, value} = tuple_value(value)
           {syntax, nil, value}
         end

       {member, if(match?([_], tuples), do: hd(tuples), else: tuples)}
     end}
  end

  defp tuple_value({syntax, nil}) when syntax in @out_of_band, do: {syntax, syntax}
  defp tuple_value(value), do: value

  @doc false
  def tag_number(tag) when is_integer(tag), do: tag

  def tag_number(tag) do
    case Map.fetch(@tags, normalize_tag(tag)) do
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
