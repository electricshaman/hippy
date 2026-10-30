defmodule Hippy.Decoder do
  @moduledoc """
  Functions for handling binary decoding of an IPP response.

  Decoding happens in two steps. The response is first parsed exactly as it was sent: one
  `{syntax, name, value}` tuple per value, with values as they appear on the wire. That's what
  `decode/2` returns with `raw: true`. By default, the attributes are then interpreted (see
  `decode/2`).
  """

  @groups [
    :operation_attributes,
    :job_attributes,
    :printer_attributes,
    :unsupported_attributes,
    :subscription_attributes,
    :event_notification_attributes,
    :resource_attributes,
    :document_attributes,
    :system_attributes,
    :unknown_attributes
  ]

  # Groups that can appear more than once (e.g. one per job, or one per printer from
  # CUPS-Get-Printers) are kept as a list of groups.
  @repeated_groups [
    :job_attributes,
    :printer_attributes,
    :subscription_attributes,
    :event_notification_attributes,
    :resource_attributes,
    :document_attributes
  ]

  @doc """
  Decodes an IPP response from its binary into a response struct.

  By default, attributes are interpreted:

    * Additional values of an attribute (sent without a name) are combined into a list.
    * Attributes repeated by name within a group are merged.
    * Values are converted by `Hippy.AttributeTransform` (enums to atoms, URIs to `URI`, dates
      to `DateTime`, and so on), and collections become maps.
    * The status code is an atom, or the integer if Hippy doesn't know it.

  ## Options

    * `:raw` - when `true`, return the response exactly as it was sent: one tuple per value,
      with `nil` as the name of an attribute's additional values, values as they appear on the
      wire (enums and status codes as integers, booleans as 0 or 1, URIs as strings, dates,
      resolutions and ranges as tuples), collections as ordered lists of `{member, value}`, and
      repeated attributes left as they are. Value tags Hippy doesn't know keep their tag number
      as the syntax and their bytes as the value. `Hippy.Encoder.encode/1` accepts all of these,
      and encoding the groups again gives the original bytes. (Groups of different kinds are
      kept in separate fields, so the order between them isn't preserved.)
  """
  def decode(bin, opts \\ []) do
    <<major::8-signed, minor::8-signed, status_code::16-signed, request_id::32-signed,
      rest::binary>> = bin

    {groups, data} = parse_groups(rest, [])

    res = %Hippy.Response{
      version: %Hippy.IPPVersion{major: major, minor: minor},
      status_code: status_code,
      request_id: request_id,
      data: data
    }

    if Keyword.get(opts, :raw, false) do
      put_groups(res, groups, &Function.identity/1, &Enum.concat/1)
    else
      %{res | status_code: decode_status_code(status_code)}
      |> put_groups(groups, &interpret_group/1, &combine_groups/1)
    end
  end

  defp decode_status_code(value) do
    case Hippy.IPP.StatusCode.decode(value) do
      {:ok, status} -> status
      {:error, _} -> value
    end
  end

  defp put_groups(res, groups, each_group, combine) do
    Enum.reduce(@groups, res, fn field, res ->
      groups = for {^field, attributes} <- groups, do: each_group.(attributes)
      Map.put(res, field, if(field in @repeated_groups, do: groups, else: combine.(groups)))
    end)
  end

  # Parsing: the response exactly as it was sent.

  defp parse_groups(<<0x03, data::binary>>, acc), do: {Enum.reverse(acc), data}

  defp parse_groups(<<tag, bin::binary>>, acc) when tag in 0x00..0x0F do
    {attributes, rest} = parse_attributes(bin, [])
    parse_groups(rest, [{group(tag), attributes} | acc])
  end

  defp group(tag) when tag in 0x01..0x0A do
    {:ok, group} = Hippy.IPP.DelimiterTag.decode(tag)
    group
  end

  # Group tags not assigned by IANA.
  defp group(_tag), do: :unknown_attributes

  defp parse_attributes(<<tag, _::binary>> = bin, acc) when tag in 0x00..0x0F do
    {Enum.reverse(acc), bin}
  end

  defp parse_attributes(bin, acc) do
    {attribute, rest} = parse_attribute(bin)
    parse_attributes(rest, [attribute | acc])
  end

  defp parse_attribute(
         <<0x34, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed, _::size(vlen)-binary,
           rest::binary>>
       ) do
    {members, rest} = parse_collection(rest, [])
    {{:collection, name(name), members}, rest}
  end

  defp parse_attribute(
         <<tag, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, rest::binary>>
       ) do
    {syntax, value} = parse_value(tag, value)
    {{syntax, name(name), value}, rest}
  end

  # An attribute without a name is an additional value of the previous one.
  defp name(""), do: nil
  defp name(name), do: name

  @out_of_band [0x10, 0x12, 0x13, 0x15, 0x16, 0x17]
  @strings [0x30, 0x41, 0x42, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49]

  defp parse_value(tag, _value) when tag in @out_of_band do
    # Out-of-band values have no value of their own, so the syntax is used as the value.
    syntax = syntax(tag)
    {syntax, syntax}
  end

  defp parse_value(0x21, <<value::signed-integer-size(32)>>), do: {:integer, value}
  defp parse_value(0x22, <<value::8>>), do: {:boolean, value}
  defp parse_value(0x23, <<value::integer-size(32)>>), do: {:enum, value}
  defp parse_value(0x31, <<_::11-binary>> = value), do: {:datetime, parse_date(value)}

  defp parse_value(0x32, <<xf::32-signed, f::32-signed, unit::8>>),
    do: {:resolution, {xf, f, unit}}

  defp parse_value(0x33, <<lower::32-signed, upper::32-signed>>),
    do: {:range_of_integer, {lower, upper}}

  defp parse_value(
         tag,
         <<llen::16-signed, lang::size(llen)-binary, tlen::16-signed, text::size(tlen)-binary>>
       )
       when tag in [0x35, 0x36] do
    {syntax(tag), {lang, text}}
  end

  defp parse_value(tag, value) when tag in @strings, do: {syntax(tag), value}

  # Value tags Hippy doesn't know (or a value that doesn't fit its tag) keep the tag number as
  # the syntax and the bytes as the value.
  defp parse_value(tag, value), do: {tag, value}

  defp syntax(tag) do
    {:ok, syntax} = Hippy.IPP.ValueTag.decode(tag)
    syntax
  end

  # Collection members, in order, as {member name, value}. A member with several values has a
  # list of values.
  defp parse_collection(
         <<0x37, nlen::16-signed, _::size(nlen)-binary, vlen::16-signed, _::size(vlen)-binary,
           rest::binary>>,
         acc
       ) do
    {Enum.reverse(acc), rest}
  end

  defp parse_collection(
         <<0x4A, nlen::16-signed, _::size(nlen)-binary, vlen::16-signed,
           member::size(vlen)-binary, rest::binary>>,
         acc
       ) do
    {value, rest} = parse_attribute(rest)
    parse_collection(rest, [{member, value} | acc])
  end

  defp parse_collection(bin, [{member, existing} | acc]) do
    # An additional value of the current member.
    {value, rest} = parse_attribute(bin)
    values = if is_list(existing), do: existing ++ [value], else: [existing, value]
    parse_collection(rest, [{member, values} | acc])
  end

  defp parse_date(date_bin) do
    <<y::16-signed, mo::8, d::8, h::8, min::8, s::8, ds::8, off_dir::1-binary, off_h::8,
      off_min::8>> = date_bin

    {y, mo, d, h, min, s, ds, off_dir, off_h, off_min}
  end

  # Interpretation.

  defp interpret_group(attributes) do
    attributes
    |> Enum.reduce([], &add_attribute(&2, &1))
    |> Enum.reverse()
    |> merge_duplicates()
  end

  defp add_attribute([{syntax, name, existing} | acc], {value_syntax, nil, value}) do
    # An attribute without a name is an additional value of the previous attribute (a set).
    {_, _, value} = transform({value_syntax, name, value})

    values = if is_list(existing), do: existing ++ [value], else: [existing, value]
    [{syntax, name, values} | acc]
  end

  defp add_attribute(acc, attribute) do
    [transform(attribute) | acc]
  end

  defp transform({:collection, name, members}) do
    {:collection, name, collection_map(members)}
  end

  defp transform(attribute), do: Hippy.AttributeTransform.handle_attribute(attribute)

  defp collection_map(members) do
    Map.new(members, fn {member, value} -> {member, member_value(value)} end)
  end

  defp member_value(values) when is_list(values), do: Enum.map(values, &member_value/1)

  defp member_value({:collection, name, members}),
    do: {:collection, name, collection_map(members)}

  defp member_value(value), do: value

  defp merge_duplicates(attributes) do
    # Some printers repeat an attribute name within a group, which IPP doesn't allow.
    # Merge the values so none are lost, keeping the position of the first occurrence.
    by_name = Enum.group_by(attributes, &elem(&1, 1))

    attributes
    |> Enum.uniq_by(&elem(&1, 1))
    |> Enum.map(fn {syntax, name, _value} = first ->
      case by_name[name] do
        [_single] ->
          first

        duplicates ->
          case duplicates |> Enum.flat_map(&List.wrap(elem(&1, 2))) |> Enum.uniq() do
            [value] -> {syntax, name, value}
            values -> {syntax, name, values}
          end
      end
    end)
  end

  # Other groups, such as operation attributes, are returned as one flat group. If a response has
  # several, attributes with the same name are combined into a list with every group's values.
  defp combine_groups([]), do: []
  defp combine_groups([group]), do: group

  defp combine_groups(groups) do
    attributes = Enum.concat(groups)
    by_name = Enum.group_by(attributes, &elem(&1, 1))

    attributes
    |> Enum.uniq_by(&elem(&1, 1))
    |> Enum.map(fn {syntax, name, _value} = first ->
      case by_name[name] do
        [_single] -> first
        all -> {syntax, name, Enum.flat_map(all, &List.wrap(elem(&1, 2)))}
      end
    end)
  end
end
