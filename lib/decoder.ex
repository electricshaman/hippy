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
    att_keys = [:job_attributes, :operation_attributes, :printer_attributes, :unknown_attributes]

    res =
      Enum.reduce(att_keys, res, fn key, res ->
        Map.put(res, key, Enum.reverse(res[key]) |> collapse_sets(key))
      end)

    # res = %{
    #  res
    #  | job_attributes: Enum.reverse(res.job_attributes),
    #    operation_attributes: Enum.reverse(res.operation_attributes),
    #  printer_attributes: Enum.reverse(res.printer_attributes) |> collapse_sets(:printer_attributes),
    #    unknown_attributes: Enum.reverse(res.unknown_attributes)
    # }

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

  defp collapse_sets(attributes, :printer_attributes) do
    groups = Enum.group_by(hd(attributes), fn {syntax, name, value} -> {syntax, name} end)

    Enum.map(groups, fn {{syntax, name}, values} ->
      if length(values) > 1 do
        # Set
        values = Enum.map(values, fn {syntax, name, value} -> value end)
        {syntax, name, values}
      else
        # Single attribute
        {syntax, name, value} = hd(values)
        {syntax, name, value}
      end
    end)
  end

  defp collapse_sets(attributes, :operation_attributes) do
    hd(attributes)
  end

  defp collapse_sets(attributes, other) do
    attributes
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x10, name_len::16-signed, name::size(name_len)-binary, 0::16-signed, bin::binary>>
       ) do
    # Out of band: unsupported
    parse_attributes(group, res, [{:unsupported, name, :unsupported} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x12, name_len::16-signed, name::size(name_len)-binary, 0::16-signed, bin::binary>>
       ) do
    # Out of band: unknown
    parse_attributes(group, res, [{:unknown, name, :unknown} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x13, name_len::16-signed, name::size(name_len)-binary, 0::16-signed, bin::binary>>
       ) do
    # Out of band: no-value
    parse_attributes(group, res, [{:no_value, name, :no_value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x22, name_len::16-signed, name::size(name_len)-binary, 1::16-signed, value::8,
           bin::binary>>
       ) do
    # Boolean
    parse_attributes(group, res, [{:boolean, name, to_boolean(value)} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x31, name_len::16-signed, name::size(name_len)-binary, 11::16-signed,
           value::11-binary, bin::binary>>
       ) do
    # Datetime
    <<y::16-signed, mo::8, d::8, h::8, min::8, s::8, ds::8, off_dir::1-binary, off_h::8,
      off_min::8>> = value

    date = "#{zpad2(y)}-#{zpad2(mo)}-#{zpad2(d)}"
    time = "T#{zpad2(h)}:#{zpad2(min)}:#{zpad2(s)}.#{ds}"
    offset = "#{off_dir}#{zpad2(off_h)}#{zpad2(off_min)}"

    value =
      case DateTime.from_iso8601("#{date}#{time}#{offset}") do
        {:ok, dt, _offset} -> dt
        error -> error
      end

    parse_attributes(group, res, [{:datetime, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x47, name_len::16-signed, name::size(name_len)-binary, value_len::16-signed,
           value::size(value_len)-binary, bin::binary>>
       ) do
    # Charset
    parse_attributes(group, res, [{:charset, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x48, name_len::16-signed, name::size(name_len)-binary, value_len::16-signed,
           value::size(value_len)-binary, bin::binary>>
       ) do
    # Natural Language
    parse_attributes(group, res, [{:natural_language, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x49, 0x0000::16, value_len::16-signed, value::size(value_len)-binary, bin::binary>>
       ) do
    # MIME Media Type: additional_value
    name = find_name_of_set(acc)
    parse_attributes(group, res, [{:mime_media_type, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x49, name_len::16-signed, name::size(name_len)-binary, value_len::16-signed,
           value::size(value_len)-binary, bin::binary>>
       ) do
    # MIME Media Type
    parse_attributes(group, res, [{:mime_media_type, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x21, 0x0000::16, value_len::16-signed, value::signed-integer-size(value_len)-unit(8),
           bin::binary>>
       ) do
    # Integer: additional_value
    name = find_name_of_set(acc)
    parse_attributes(group, res, [{:integer, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x21, name_len::16-signed, name::size(name_len)-binary, value_len::16-signed,
           value::signed-integer-size(value_len)-unit(8), bin::binary>>
       ) do
    # Integer
    parse_attributes(group, res, [{:integer, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x45, name_len::16-signed, name::size(name_len)-binary, value_len::16-signed,
           value::size(value_len)-binary, bin::binary>>
       ) do
    # URI
    parse_attributes(group, res, [{:uri, name, URI.parse(value)} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x23, 0x0000::16, value_len::16-signed, value::integer-size(value_len)-unit(8),
           bin::binary>>
       ) do
    # Enum: additional_value
    name = find_name_of_set(acc)
    value = Hippy.Protocol.Enum.decode!(name, value)
    parse_attributes(group, res, [{:enum, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x23, name_len::16-signed, name::size(name_len)-binary, value_len::16-signed,
           value::integer-size(value_len)-unit(8), bin::binary>>
       ) do
    # Enum
    value = Hippy.Protocol.Enum.decode!(name, value)
    parse_attributes(group, res, [{:enum, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x32, name_len::16-signed, name::size(name_len)-binary, 9::16-signed, xfeed::32-signed,
           feed::32-signed, unit::8, bin::binary>>
       ) do
    # Resolution
    unit = Hippy.Protocol.ResolutionUnit.decode!(unit)

    parse_attributes(
      group,
      res,
      [{:resolution, name, Hippy.PrintResolution.new(xfeed, feed, unit)} | acc],
      bin
    )
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x33, name_len::16-signed, name::size(name_len)-binary, 8::16-signed, lower::32-signed,
           upper::32-signed, bin::binary>>
       ) do
    # rangeOfInteger
    parse_attributes(group, res, [{:range_of_integer, name, Range.new(lower, upper)} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x44, 0x0000::16, value_len::16-signed, value::size(value_len)-binary, bin::binary>>
       ) do
    # Keyword: additional_value
    name = find_name_of_set(acc)
    parse_attributes(group, res, [{:keyword, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x44, name_len::16-signed, name::size(name_len)-binary, value_len::16-signed,
           value::size(value_len)-binary, bin::binary>>
       ) do
    # Keyword
    parse_attributes(group, res, [{:keyword, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x41, name_len::16-signed, name::size(name_len)-binary, value_len::16-signed,
           value::size(value_len)-binary, bin::binary>>
       ) do
    # Text Without Language
    parse_attributes(group, res, [{:text_without_language, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x42, 0x0000::16, value_len::16-signed, value::size(value_len)-binary, bin::binary>>
       ) do
    # Name without language: additional_value
    name = find_name_of_set(acc)
    parse_attributes(group, res, [{:name_without_language, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x42, name_len::16-signed, name::size(name_len)-binary, value_len::16-signed,
           value::size(value_len)-binary, bin::binary>>
       ) do
    # Name without language
    parse_attributes(group, res, [{:name_without_language, name, value} | acc], bin)
  end

  defp parse_attributes(group, res, acc, <<octet::8-signed, bin::binary>>)
       when octet in 0x00..0x05 do
    put_group(group, res, acc)
    |> parse_groups([], <<octet::8-signed, bin::binary>>)
  end

  defp parse_attributes(group, res, acc, <<_octet::8-signed, bin::binary>>) do
    parse_attributes(group, res, acc, bin)
  end

  defp put_group(group, res, acc) do
    atts = [Enum.reverse(acc) | res[group]]
    Map.put(res, group, atts)
  end

  defp data({res, _acc, bin}) do
    # Strip off other values since we are done.
    %{res | data: bin}
  end

  defp to_boolean(0), do: false
  defp to_boolean(1), do: true

  defp zpad2(value), do: to_string(value) |> String.pad_leading(2, "0")

  defp find_name_of_set(acc) do
    # Logger.debug("acc: #{inspect(acc)}")
    # Walk the accumulator to find first previous attribute with a name.
    Enum.find_value(acc, fn {_syntax, name, _value} -> name != nil and name end)
  end
end
