defmodule Hippy.Decoder do
  @moduledoc """
  Functions for handling binary decoding of an IPP response.
  """

  alias Hippy.Response
  alias Hippy.Protocol.StatusCode

  require Logger

  @doc "Decodes an IPP response from its binary into a response struct."
  def decode(bin) do
    {%Response{}, bin}
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
    status = StatusCode.decode!(status_code)
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
    group_keys = [
      :job_attributes,
      :operation_attributes,
      :printer_attributes,
      :unknown_attributes
    ]

    res =
      Enum.reduce(group_keys, res, fn key, res ->
        val = Enum.reverse(res[key]) |> collapse_sets(key)
        Map.put(res, key, val)
      end)

    {res, acc, bin}
  end

  defp parse_groups(res, acc, <<0x04, bin::binary>>) do
    # Printer attributes
    parse_attributes(:printer_attributes, res, acc, bin)
  end

  defp parse_groups(res, acc, <<0x05, bin::binary>>) do
    # Unsupported attributes
    parse_attributes(:unsupported_attributes, res, acc, bin)
  end

  defp parse_attributes(group, res, acc, <<octet, _::binary>> = bin) when octet in 0x00..0x05 do
    Map.put(res, group, res[group] ++ acc)
    |> parse_groups([], bin)
  end

  defp parse_attributes(group, res, acc, <<_tag, _::binary>> = bin) do
    {{syntax, name, value}, rest} = parse_attribute(bin)
    result = {syntax, attribute_name(name, acc), value}
    parse_attributes(group, res, [result | acc], rest)
  end

  defp collapse_sets(attributes, :printer_attributes) do
    groups =
      Enum.with_index(attributes)
      |> Enum.group_by(fn {{s, n, _v}, _i} -> {s, n} end)

    Enum.map(groups, fn {{syntax, name}, values} ->
      if length(values) > 1 do
        # Set
        # Use the lowest index for the whole set.
        {_, index} = Enum.min_by(values, fn {_, index} -> index end)
        # Project values to their own list.
        values = Enum.map(values, fn {{_s, _n, v}, _i} -> v end)
        {{syntax, name, values}, index}
      else
        # Single attribute
        hd(values)
      end
    end)
    |> Enum.sort_by(fn {_, i} -> i end)
    |> Enum.map(fn {{s, n, v}, _i} -> {s, n, v} end)
  end

  defp collapse_sets(attributes, _other) do
    attributes
  end

  defp data({res, _acc, bin}) do
    # Strip off other values since we are done.
    %{res | data: bin}
  end

  defp to_boolean(0), do: false
  defp to_boolean(1), do: true

  defp zpad2(value), do: to_string(value) |> String.pad_leading(2, "0")

  defp attribute_name(nil, acc), do: find_set_name(acc)
  defp attribute_name(name, _acc), do: name

  defp find_set_name(acc) do
    # Walk the accumulator to find first previous attribute with a name.
    Enum.find_value(acc, fn {_syntax, name, _value} -> name != nil and name end)
  end

  defp format_date(date_bin) do
    <<y::16-signed, mo::8, d::8, h::8, min::8, s::8, ds::8, off_dir::1-binary, off_h::8,
      off_min::8>> = date_bin

    date = "#{zpad2(y)}-#{zpad2(mo)}-#{zpad2(d)}"
    time = "T#{zpad2(h)}:#{zpad2(min)}:#{zpad2(s)}.#{ds}"
    offset = "#{off_dir}#{zpad2(off_h)}#{zpad2(off_min)}"

    case DateTime.from_iso8601("#{date}#{time}#{offset}") do
      {:ok, dt, _offset} -> dt
      error -> error
    end
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
    {{:boolean, nil, to_boolean(value)}, bin}
  end

  defp parse_attribute(
         <<0x22, len::16-signed, name::size(len)-binary, 1::16-signed, value::8, bin::binary>>
       ) do
    {{:boolean, name, to_boolean(value)}, bin}
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

  defp parse_attribute(<<0x31, 0::16, 11::16-signed, value::11-binary, bin::binary>>) do
    {{:datetime, nil, format_date(value)}, bin}
  end

  defp parse_attribute(
         <<0x31, len::16-signed, name::size(len)-binary, 11::16, value::11-binary, bin::binary>>
       ) do
    {{:datetime, name, format_date(value)}, bin}
  end

  defp parse_attribute(
         <<0x32, 0::16, 9::16, xfeed::32-signed, feed::32-signed, unit::8, bin::binary>>
       ) do
    unit = Hippy.Protocol.ResolutionUnit.decode!(unit)
    {{:resolution, nil, Hippy.PrintResolution.new(xfeed, feed, unit)}, bin}
  end

  defp parse_attribute(
         <<0x32, len::16-signed, name::size(len)-binary, 9::16-signed, xf::32-signed,
           f::32-signed, u::8, bin::binary>>
       ) do
    unit = Hippy.Protocol.ResolutionUnit.decode!(u)
    {{:resolution, name, Hippy.PrintResolution.new(xf, f, unit)}, bin}
  end

  defp parse_attribute(
         <<0x33, 0::16, 8::16-signed, lower::32-signed, upper::32-signed, bin::binary>>
       ) do
    {{:range_of_integer, nil, Range.new(lower, upper)}, bin}
  end

  defp parse_attribute(
         <<0x33, len::16-signed, name::size(len)-binary, 8::16-signed, l::32-signed, u::32-signed,
           bin::binary>>
       ) do
    {{:range_of_integer, name, Range.new(l, u)}, bin}
  end

  defp parse_attribute(<<0x34, 0::32, bin::binary>>) do
    # Collection with no name: additional values in a set.
    {value, rest} = parse_collection(%{}, nil, bin)
    {{:collection, nil, value}, rest}
  end

  defp parse_attribute(
         <<0x34, len::16-signed, name::size(len)-binary, 0::16-signed, bin::binary>>
       ) do
    # Collection with name
    {value, rest} = parse_collection(%{}, nil, bin)
    {{:collection, name, value}, rest}
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
    {{:uri, nil, URI.parse(value)}, bin}
  end

  defp parse_attribute(
         <<0x45, nlen::16-signed, name::size(nlen)-binary, vlen::16-signed,
           value::size(vlen)-binary, bin::binary>>
       ) do
    {{:uri, name, URI.parse(value)}, bin}
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
    {value, bin} = parse_attribute(bin)
    acc = Map.put(acc, name, value)
    parse_collection(acc, name, bin)
  end

  defp parse_collection(acc, member_name, <<_octet, 0::16, _::binary>> = bin) do
    {value, bin} = parse_attribute(bin)

    current = acc[member_name]

    # TODO: Refactor.
    value =
      if is_nil(current) do
        value
      else
        if is_list(current) do
          Enum.reverse([value | current])
        else
          Enum.reverse([value | [current]])
        end
      end

    acc = Map.put(acc, member_name, value)
    parse_collection(acc, member_name, bin)
  end
end
