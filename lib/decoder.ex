defmodule Hippy.Decoder do
  @moduledoc """
  Decodes IPP messages. See `Hippy.Message.decode/1`.
  """

  @doc "Decodes an IPP message from its binary form. Same as `Hippy.Message.decode/1`."
  def decode(bin), do: Hippy.Message.decode(bin)

  @doc false
  # The message exactly as sent: header fields, groups as {tag number, attribute tuples} with
  # nil names for additional values, and the data. Used by Hippy.Message.
  def parse(bin) do
    <<major::8-signed, minor::8-signed, code::16-signed, request_id::32-signed, rest::binary>> =
      bin

    {groups, data} = parse_groups(rest, [])
    %{version: {major, minor}, code: code, request_id: request_id, groups: groups, data: data}
  end

  # Parsing: the response exactly as it was sent.

  defp parse_groups(<<0x03, data::binary>>, acc), do: {Enum.reverse(acc), data}

  defp parse_groups(<<tag, bin::binary>>, acc) when tag in 0x00..0x0F do
    {attributes, rest} = parse_attributes(bin, [])
    parse_groups(rest, [{tag, attributes} | acc])
  end

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

  # Interpretation, for Hippy.Message's maps.

  @doc false
  # Combines additional values into lists, converts values (Hippy.AttributeTransform) and
  # collections, and merges attributes repeated within a group.
  def interpret_group(attributes) do
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
end
