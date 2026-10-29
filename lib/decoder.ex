defmodule Hippy.Decoder do
  @moduledoc """
  Functions for handling binary decoding of an IPP response.
  """

  require Logger

  @doc "Decodes an IPP response from its binary into a response struct."
  def decode(bin) do
    {%Hippy.Response{}, bin}
    |> version()
    |> status_code()
    |> request_id()
    |> groups()
    |> data()
  end

  defp version({res, bin}) do
    <<major::8-signed, minor::8-signed, rest::binary>> = bin
    version = %Hippy.IPPVersion{major: major, minor: minor}
    {%{res | version: version}, rest}
  end

  defp status_code({res, bin}) do
    <<status_code::16-signed, rest::binary>> = bin
    status = Hippy.IPP.StatusCode.decode!(status_code)
    {%{res | status_code: status}, rest}
  end

  defp request_id({res, bin}) do
    <<request_id::32-signed, rest::binary>> = bin
    {%{res | request_id: request_id}, rest}
  end

  defp groups({res, bin}) do
    parse_groups(res, [], bin)
  end

  defp parse_groups(res, acc, <<0x01, bin::binary>>) do
    # Operation attributes
    parse_attributes(:operation_attributes, res, acc, bin)
  end

  defp parse_groups(res, acc, <<0x02, bin::binary>>) do
    # Job attributes
    parse_attributes(:job_attributes, res, acc, bin)
  end

  defp parse_groups(res, acc, <<0x03, bin::binary>>) do
    # End of groups
    groups = [
      :job_attributes,
      :operation_attributes,
      :printer_attributes,
      :unsupported_attributes,
      :unknown_attributes
    ]

    {finish_groups(groups, res), acc, bin}
  end

  defp parse_groups(res, acc, <<0x04, bin::binary>>) do
    # Printer attributes
    parse_attributes(:printer_attributes, res, acc, bin)
  end

  defp parse_groups(res, acc, <<0x05, bin::binary>>) do
    # Unsupported attributes
    parse_attributes(:unsupported_attributes, res, acc, bin)
  end

  defp finish_groups(groups, res) do
    Enum.reduce(groups, res, fn group, res ->
      val = Enum.reverse(res[group]) |> merge_duplicates(group)
      Map.put(res, group, val)
    end)
  end

  defp merge_duplicates(groups, :job_attributes) do
    Enum.map(groups, &merge_duplicates(&1, nil))
  end

  defp merge_duplicates(attributes, _group) do
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

  defp parse_attributes(group, res, acc, <<octet, _::binary>> = bin) when octet in 0x00..0x05 do
    Map.put(res, group, add_to_group(group, res, acc))
    |> parse_groups([], bin)
  end

  defp parse_attributes(group, res, acc, <<_tag, _::binary>> = bin) do
    {attribute, rest} = parse_attribute(bin)
    parse_attributes(group, res, add_attribute(acc, attribute), rest)
  end

  defp add_attribute([{syntax, name, existing} | acc], {value_syntax, nil, value}) do
    # An attribute without a name is an additional value of the previous attribute (a set).
    {_, _, value} = Hippy.AttributeTransform.handle_attribute({value_syntax, name, value})

    values = if is_list(existing), do: existing ++ [value], else: [existing, value]
    [{syntax, name, values} | acc]
  end

  defp add_attribute(acc, attribute) do
    [Hippy.AttributeTransform.handle_attribute(attribute) | acc]
  end

  defp add_to_group(:job_attributes = group, res, acc) do
    [Enum.reverse(acc) | res[group]]
  end

  defp add_to_group(group, res, acc) do
    # Both acc and the group are kept in reverse order until finish_groups/2.
    acc ++ res[group]
  end

  defp data({res, _acc, bin}) do
    # Strip off other values since we are done.
    %{res | data: bin}
  end

  defp parse_attribute(<<0x10, 0::32, bin::binary>>) do
    {{:unsupported, nil, :unsupported}, bin}
  end

  defp parse_attribute(<<0x10, len::16-signed, name::size(len)-binary, 0::16, bin::binary>>) do
    {{:unsupported, name, :unsupported}, bin}
  end

  defp parse_attribute(<<0x12, 0::32, bin::binary>>) do
    {{:unknown, nil, :unknown}, bin}
  end

  defp parse_attribute(<<0x12, len::16-signed, name::size(len)-binary, 0::16, bin::binary>>) do
    {{:unknown, name, :unknown}, bin}
  end

  defp parse_attribute(<<0x13, 0::32, bin::binary>>) do
    {{:no_value, nil, :no_value}, bin}
  end

  defp parse_attribute(<<0x13, len::16-signed, name::size(len)-binary, 0::16, bin::binary>>) do
    {{:no_value, name, :no_value}, bin}
  end

  defp parse_attribute(
         <<tag, 0::16, len::16-signed, value::signed-integer-size(len)-unit(8), bin::binary>>
       )
       when tag === 0x20 or tag in 0x24..0x2F do
    {{:integer, nil, value}, bin}
  end

  defp parse_attribute(
         <<tag, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::signed-integer-size(vlen)-unit(8), bin::binary>>
       )
       when tag === 0x20 or tag in 0x24..0x2F do
    {{:integer, name, value}, bin}
  end

  defp parse_attribute(
         <<0x21, 0::16, len::16-signed, value::signed-integer-size(len)-unit(8), bin::binary>>
       ) do
    {{:integer, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x21, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::signed-integer-size(vlen)-unit(8), bin::binary>>
       ) do
    {{:integer, name, value}, bin}
  end

  defp parse_attribute(<<0x22, 0::16, 1::16, value::8, bin::binary>>) do
    {{:boolean, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x22, len::16-signed, name::size(len)-binary, 1::16-signed, value::8, bin::binary>>
       ) do
    {{:boolean, name, value}, bin}
  end

  defp parse_attribute(
         <<0x23, 0::16, len::16-signed, value::integer-size(len)-unit(8), bin::binary>>
       ) do
    {{:enum, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x23, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::integer-size(vlen)-unit(8), bin::binary>>
       ) do
    {{:enum, name, value}, bin}
  end

  defp parse_attribute(<<0x30, 0::16, len::16-signed, value::size(len)-binary, bin::binary>>) do
    {{:octet_string, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x30, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       ) do
    {{:octet_string, name, value}, bin}
  end

  defp parse_attribute(<<0x31, 0::16, 11::16, value::11-binary, bin::binary>>) do
    {{:datetime, nil, parse_date(value)}, bin}
  end

  defp parse_attribute(
         <<0x31, len::16-signed, name::size(len)-binary, 11::16, value::11-binary, bin::binary>>
       ) do
    {{:datetime, name, parse_date(value)}, bin}
  end

  defp parse_attribute(<<0x32, 0::16, 9::16, xf::32-signed, f::32-signed, u::8, bin::binary>>) do
    {{:resolution, nil, {xf, f, u}}, bin}
  end

  defp parse_attribute(
         <<0x32, len::16-signed, name::size(len)-binary, 9::16-signed, xf::32-signed,
           f::32-signed, u::8, bin::binary>>
       ) do
    {{:resolution, name, {xf, f, u}}, bin}
  end

  defp parse_attribute(<<0x33, 0::16, 8::16, l::32-signed, u::32-signed, bin::binary>>) do
    {{:range_of_integer, nil, {l, u}}, bin}
  end

  defp parse_attribute(
         <<0x33, len::16-signed, name::size(len)-binary, 8::16, l::32-signed, u::32-signed,
           bin::binary>>
       ) do
    {{:range_of_integer, name, {l, u}}, bin}
  end

  defp parse_attribute(<<0x34, 0::32, bin::binary>>) do
    # Collection with no name: additional values in a set.
    {value, rest} = parse_collection(%{}, nil, bin)
    {{:collection, nil, value}, rest}
  end

  defp parse_attribute(<<0x34, len::16-signed, name::size(len)-binary, 0::16, bin::binary>>) do
    # Collection with name
    {value, rest} = parse_collection(%{}, nil, bin)
    {{:collection, name, value}, rest}
  end

  defp parse_attribute(
         <<tag, 0::16, _vlen::16-signed, llen::16-signed, lang::size(llen)-binary,
           tlen::16-signed, text::size(tlen)-binary, bin::binary>>
       )
       when tag in [0x35, 0x36] do
    {{with_language_syntax(tag), nil, {lang, text}}, bin}
  end

  defp parse_attribute(
         <<tag, nlen::16-signed, name::size(nlen)-binary, _vlen::16-signed, llen::16-signed,
           lang::size(llen)-binary, tlen::16-signed, text::size(tlen)-binary, bin::binary>>
       )
       when tag in [0x35, 0x36] do
    {{with_language_syntax(tag), name, {lang, text}}, bin}
  end

  defp parse_attribute(<<tag, 0::16, len::16-signed, value::size(len)-binary, bin::binary>>)
       when tag in 0x38..0x3F do
    {{:octet_string, nil, value}, bin}
  end

  defp parse_attribute(
         <<tag, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       )
       when tag in 0x38..0x3F do
    {{:octet_string, name, value}, bin}
  end

  defp parse_attribute(<<tag, 0::16, len::16-signed, value::size(len)-binary, bin::binary>>)
       when tag in [0x40, 0x43] or tag in 0x4B..0x5F do
    {{:charset, nil, value}, bin}
  end

  defp parse_attribute(
         <<tag, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       )
       when tag in [0x40, 0x43] or tag in 0x4B..0x5F do
    {{:charset, name, value}, bin}
  end

  defp parse_attribute(<<0x41, 0::16, vlen::16-signed, value::size(vlen)-binary, bin::binary>>) do
    {{:text_without_language, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x41, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       ) do
    {{:text_without_language, name, value}, bin}
  end

  defp parse_attribute(<<0x42, 0::16, vlen::16-signed, value::size(vlen)-binary, bin::binary>>) do
    {{:name_without_language, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x42, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       ) do
    {{:name_without_language, name, value}, bin}
  end

  defp parse_attribute(<<0x44, 0::16, len::16-signed, value::size(len)-binary, bin::binary>>) do
    {{:keyword, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x44, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       ) do
    {{:keyword, name, value}, bin}
  end

  defp parse_attribute(<<0x45, 0::16, len::16-signed, value::size(len)-binary, bin::binary>>) do
    {{:uri, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x45, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       ) do
    {{:uri, name, value}, bin}
  end

  defp parse_attribute(<<0x46, 0::16, len::16-signed, value::size(len)-binary, bin::binary>>) do
    {{:uri_scheme, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x46, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       ) do
    {{:uri_scheme, name, value}, bin}
  end

  defp parse_attribute(<<0x47, 0::16, len::16-signed, value::size(len)-binary, bin::binary>>) do
    {{:charset, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x47, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       ) do
    {{:charset, name, value}, bin}
  end

  defp parse_attribute(<<0x48, 0::16, len::16-signed, value::size(len)-binary, bin::binary>>) do
    {{:natural_language, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x48, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       ) do
    {{:natural_language, name, value}, bin}
  end

  defp parse_attribute(<<0x49, 0::16, len::16-signed, value::size(len)-binary, bin::binary>>) do
    {{:mime_media_type, nil, value}, bin}
  end

  defp parse_attribute(
         <<0x49, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       ) do
    {{:mime_media_type, name, value}, bin}
  end

  defp with_language_syntax(0x35), do: :text_with_language
  defp with_language_syntax(0x36), do: :name_with_language

  defp parse_collection(acc, _stack, <<0x37, 0::32, bin::binary>>) do
    # End of collection
    {acc, bin}
  end

  defp parse_collection(
         acc,
         _member_name,
         <<0x4A, 0::16, len::16-signed, name::size(len)-binary, bin::binary>>
       ) do
    # Member attribute
    {value, rest} = parse_attribute(bin)

    Map.put(acc, name, value)
    |> parse_collection(name, rest)
  end

  defp parse_collection(acc, member_name, <<_octet, 0::16, _::binary>> = bin) do
    {value, rest} = parse_attribute(bin)

    Map.put(acc, member_name, member_value(acc[member_name], value))
    |> parse_collection(member_name, rest)
  end

  defp member_value(existing, new) do
    cond do
      is_nil(existing) ->
        # Nothing exists yet, set single value.
        new

      is_list(existing) ->
        # Append to list.
        existing ++ [new]

      true ->
        # Single value exists, create new list.
        [existing, new]
    end
  end

  defp parse_date(date_bin) do
    <<y::16-signed, mo::8, d::8, h::8, min::8, s::8, ds::8, off_dir::1-binary, off_h::8,
      off_min::8>> = date_bin

    {y, mo, d, h, min, s, ds, off_dir, off_h, off_min}
  end
end
