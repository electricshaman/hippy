defmodule Hippy.Encoder do
  @moduledoc """
  Functions for handling binary encoding of an IPP request.
  """

  alias Hippy.Request
  alias Hippy.IPP.{DelimiterTag, ResolutionUnit, ValueTag}

  @string_syntaxes [
    :octet_string,
    :text_without_language,
    :name_without_language,
    :keyword,
    :uri,
    :uri_scheme,
    :charset,
    :natural_language,
    :mime_media_type
  ]

  @out_of_band_syntaxes [
    :unsupported,
    :unknown,
    :no_value,
    :not_settable,
    :delete_attribute,
    :admin_define
  ]

  @doc """
  Encodes an IPP request into its binary form.

  Attributes are `{syntax, name, value}` tuples, in the same form `Hippy.Decoder` returns them:

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
  """
  def encode(%Request{} = req) do
    operation_attributes_bin =
      for attribute <- req.operation_attributes, into: request_header(req) do
        encode_attribute(attribute)
      end

    job_attributes_bin =
      case req.job_attributes do
        [] ->
          ""

        attributes ->
          for attribute <- attributes, into: <<DelimiterTag.job_attributes()::8-signed>> do
            encode_attribute(attribute)
          end
      end

    <<operation_attributes_bin::binary, job_attributes_bin::binary,
      DelimiterTag.end_of_attributes()::8-signed, req.data::binary>>
  end

  defp encode_attribute({{:set1, syntax}, name, values}) when is_list(values) do
    encode_attribute({syntax, name, values})
  end

  defp encode_attribute({syntax, name, [first | rest]}) when is_binary(name) do
    # Additional values of a multi-valued attribute have an empty name.
    for value <- rest, into: encode_attribute({syntax, name, first}) do
      encode_attribute({syntax, "", value})
    end
  end

  defp encode_attribute({syntax, name, value}) when is_binary(name) do
    <<value_tag(syntax)::8, byte_size(name)::16, name::binary,
      encode_value(syntax, name, value)::binary>>
  end

  defp encode_attribute(attribute) do
    raise ArgumentError, "invalid attribute #{inspect(attribute)}"
  end

  defp encode_value(syntax, _name, _value) when syntax in @out_of_band_syntaxes do
    <<0::16>>
  end

  defp encode_value(syntax, _name, value)
       when syntax in [:integer, :enum] and is_integer(value) do
    <<4::16, value::32-signed>>
  end

  defp encode_value(:boolean, _name, value) when is_boolean(value) do
    <<1::16, if(value, do: 1, else: 0)::8>>
  end

  defp encode_value(:uri, name, %URI{} = value) do
    encode_value(:uri, name, URI.to_string(value))
  end

  defp encode_value(syntax, _name, value)
       when (syntax in @string_syntaxes or is_integer(syntax)) and is_binary(value) do
    <<byte_size(value)::16, value::binary>>
  end

  defp encode_value(syntax, _name, {language, text})
       when syntax in [:text_with_language, :name_with_language] and is_binary(language) and
              is_binary(text) do
    value = <<byte_size(language)::16, language::binary, byte_size(text)::16, text::binary>>
    <<byte_size(value)::16, value::binary>>
  end

  defp encode_value(:datetime, _name, %DateTime{} = value) do
    offset = div(value.utc_offset + value.std_offset, 60)
    sign = if offset < 0, do: "-", else: "+"
    {deciseconds, _} = value.microsecond
    deciseconds = div(deciseconds, 100_000)

    <<11::16, value.year::16, value.month::8, value.day::8, value.hour::8, value.minute::8,
      value.second::8, deciseconds::8, sign::binary, div(abs(offset), 60)::8,
      rem(abs(offset), 60)::8>>
  end

  defp encode_value(:range_of_integer, _name, first..last//_) do
    <<8::16, first::32-signed, last::32-signed>>
  end

  defp encode_value(:resolution, _name, %Hippy.PrintResolution{} = value) do
    <<9::16, value.xfeed::32-signed, value.feed::32-signed,
      ResolutionUnit.encode!(value.unit)::8>>
  end

  defp encode_value(:collection, name, members) when is_map(members) do
    members_bin =
      for {member, value} <- members, into: <<>> do
        <<ValueTag.member_attr_name()::8, 0::16, byte_size(member)::16, member::binary,
          encode_member(name, member, value)::binary>>
      end

    <<0::16, members_bin::binary, ValueTag.end_collection()::8, 0::16, 0::16>>
  end

  defp encode_value(syntax, name, value) do
    raise ArgumentError,
          "cannot encode #{inspect(value)} as #{inspect(syntax)} for attribute #{inspect(name)}"
  end

  defp encode_member(name, member, values) when is_list(values) do
    for value <- values, into: <<>>, do: encode_member(name, member, value)
  end

  defp encode_member(_name, _member, {syntax, nil, value}),
    do: encode_attribute({syntax, "", value})

  defp encode_member(_name, _member, {syntax, value}), do: encode_attribute({syntax, "", value})

  defp encode_member(name, member, value) do
    raise ArgumentError,
          "invalid value #{inspect(value)} for member #{inspect(member)} of #{inspect(name)}"
  end

  defp request_header(%Request{request_id: nil}) do
    raise ArgumentError, "request_id is required (Hippy.Server assigns one when sending)"
  end

  defp request_header(req) do
    <<req.version.major::8-signed, req.version.minor::8-signed, req.operation_id::16-signed,
      req.request_id::32-signed, DelimiterTag.operation_attributes()::8-signed>>
  end

  defp value_tag(:collection), do: ValueTag.beg_collection()
  defp value_tag(tag) when is_integer(tag), do: tag

  defp value_tag(syntax) do
    case ValueTag.encode(syntax) do
      {:ok, tag} -> tag
      {:error, _} -> raise ArgumentError, "unknown attribute syntax #{inspect(syntax)}"
    end
  end
end
