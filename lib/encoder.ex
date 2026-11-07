defmodule Hippy.Encoder do
  @moduledoc """
  Functions for handling binary encoding of an IPP request.
  """

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
  Encodes an IPP message (`Hippy.Message`) into its binary form.

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
  def encode(%Hippy.Message{request_id: nil}) do
    raise ArgumentError, "request_id is required (Hippy.Server assigns one when sending)"
  end

  def encode(%Hippy.Message{data: data} = message) when not is_binary(data) do
    if Enumerable.impl_for(data) == nil do
      raise ArgumentError,
            "data must be a binary or an Enumerable of binaries, got: #{inspect(data)}"
    end

    Stream.concat([encode(%{message | data: <<>>})], data)
  end

  def encode(%Hippy.Message{version: {major, minor}} = message) do
    groups = for group <- message.groups, into: <<>>, do: encode_message_group(group)

    <<major::8-signed, minor::8-signed, message.code::16-signed, message.request_id::32-signed,
      groups::binary, DelimiterTag.end_of_attributes()::8-signed, message.data::binary>>
  end

  defp encode_message_group({tag, attributes}) when is_list(attributes) do
    for attribute <- attributes, into: <<Hippy.Message.tag_number(tag)::8>> do
      encode_message_attribute(attribute)
    end
  end

  defp encode_message_group(group) do
    raise ArgumentError, "invalid attribute group #{inspect(group)}, expected {tag, attributes}"
  end

  # A message attribute, {name, [{syntax, value}, ...]}: the first value carries the name, and the
  # others are additional values with an empty name.
  defp encode_message_attribute({name, [{syntax, value} | rest]}) do
    for {syntax, value} <- rest,
        into: encode_attribute({syntax, name || "", message_value(syntax, value)}) do
      encode_attribute({syntax, "", message_value(syntax, value)})
    end
  end

  defp encode_message_attribute(attribute) do
    raise ArgumentError, "invalid attribute #{inspect(attribute)}"
  end

  # Collection members are {member, [{syntax, value}, ...]}, in order.
  defp message_value(:collection, members) when is_list(members) do
    for {member, values} <- members do
      {member, Enum.map(values, fn {syntax, value} -> {syntax, message_value(syntax, value)} end)}
    end
  end

  defp message_value(_syntax, value), do: value

  defp encode_attribute({{:set1, syntax}, name, values}) when is_list(values) do
    encode_attribute({syntax, name, values})
  end

  # An additional value of the previous attribute (a tuple with a nil name).
  defp encode_attribute({syntax, nil, value}), do: encode_attribute({syntax, "", value})

  # A collection given as an ordered list of {member, value}, as in a Hippy.Message.
  defp encode_attribute({:collection, name, [{member, _} | _] = members})
       when is_binary(name) and is_binary(member) do
    <<value_tag(:collection)::8, byte_size(name)::16, name::binary,
      encode_value(:collection, name, members)::binary>>
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

  defp encode_value(:boolean, _name, value) when value in [0, 1], do: <<1::16, value::8>>

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

  # Dates, resolutions and ranges in their wire form, as in a Hippy.Message.
  defp encode_value(:datetime, _name, {y, mo, d, h, min, s, ds, dir, off_h, off_min})
       when dir in ["+", "-"] do
    <<11::16, y::16, mo::8, d::8, h::8, min::8, s::8, ds::8, dir::binary, off_h::8, off_min::8>>
  end

  defp encode_value(:resolution, _name, {xfeed, feed, unit}) when is_integer(unit) do
    <<9::16, xfeed::32-signed, feed::32-signed, unit::8>>
  end

  defp encode_value(:range_of_integer, _name, {lower, upper}) do
    <<8::16, lower::32-signed, upper::32-signed>>
  end

  defp encode_value(:range_of_integer, _name, first..last//_) do
    <<8::16, first::32-signed, last::32-signed>>
  end

  defp encode_value(:resolution, _name, %Hippy.PrintResolution{} = value) do
    <<9::16, value.xfeed::32-signed, value.feed::32-signed,
      ResolutionUnit.encode!(value.unit)::8>>
  end

  defp encode_value(:collection, name, members) when is_map(members) or is_list(members) do
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

  defp value_tag(:collection), do: ValueTag.beg_collection()
  defp value_tag(tag) when is_integer(tag), do: tag

  defp value_tag(syntax) do
    case ValueTag.encode(syntax) do
      {:ok, tag} -> tag
      {:error, _} -> raise ArgumentError, "unknown attribute syntax #{inspect(syntax)}"
    end
  end
end
