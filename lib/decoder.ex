defmodule Hippy.Decoder do
  @moduledoc """
  Functions for handling binary decoding of an IPP response.
  """

  alias Hippy.{Response, JobState}

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
    status = Hippy.StatusCode.decode!(status_code)
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
    res = %{
      res
      | job_attributes: Enum.reverse(res.job_attributes),
        operation_attributes: Enum.reverse(res.operation_attributes),
        printer_attributes: Enum.reverse(res.printer_attributes),
        unknown_attributes: Enum.reverse(res.unknown_attributes)
    }

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
    parse_attributes(group, res, [{:uri, name, value} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x23, name_len::16-signed, name::size(name_len)-binary, value_len::16-signed,
           value::integer-size(value_len)-unit(8), bin::binary>>
       ) do
    # Enum
    parse_attributes(group, res, [{:enum, name, JobState.decode!(value)} | acc], bin)
  end

  defp parse_attributes(
         group,
         res,
         acc,
         <<0x44, 0x0000::16, value_len::16-signed, value::size(value_len)-binary, bin::binary>>
       ) do
    # Keyword: additional_value
    parse_attributes(group, res, [{:keyword, nil, value} | acc], bin)
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
end
