defmodule Hippy.Encoder do
  @moduledoc """
  Functions for handling binary encoding of an IPP request.
  """

  alias Hippy.Request
  alias Hippy.Protocol.{DelimiterTag, ValueTag}

  @doc "Encodes an IPP request into its binary form."
  def encode(%Request{} = req) do
    bin =
      for attribute <- req.operation_attributes, into: request_header(req) do
        # TODO: Deal with invalid tag error in the middle of loop.
        encode_attribute(attribute)
      end

    bin =
      unless Enum.empty?(req.job_attributes) do
        <<bin::binary, DelimiterTag.job_attributes()::8-signed>>
      else
        bin
      end

    bin =
      for attribute <- req.job_attributes, into: bin do
        # TODO: Deal with invalid tag error in the middle of loop.
        encode_attribute(attribute)
      end

    bin =
      unless Enum.empty?(req.printer_attributes) do
        <<bin::binary, DelimiterTag.printer_attributes()::8-signed>>
      else
        bin
      end

    bin =
      for attribute <- req.printer_attributes, into: bin do
        # TODO: Deal with invalid tag error in the middle of loop.
        encode_attribute(attribute)
      end

    <<bin::binary, DelimiterTag.end_of_attributes()::8-signed, req.data::binary>>
  end

  defp encode_attribute({tag, name, value})
       when tag in [
              :charset,
              :uri,
              :natural_language,
              :keyword,
              :name_without_language,
  :text_without_language,
              :mime_media_type
            ] do
    <<value_tag(tag)::8-signed, byte_size(name)::16-signed, name::binary,
      byte_size(value)::16-signed, value::binary>>
  end

  defp encode_attribute({{:set1, tag}, name, value})
       when tag in [
              :charset,
              :uri,
              :natural_language,
              :keyword,
              :name_without_language,
              :mime_media_type
            ] and
              is_list(value) do
    [head_value | tail] = value

    bin =
      <<value_tag(tag)::8-signed, byte_size(name)::16-signed, name::binary,
        byte_size(head_value)::16-signed, head_value::binary>>

    for addl_value <- tail, into: bin do
      <<value_tag(tag)::8-signed, 0::16-signed, byte_size(addl_value)::16-signed,
        addl_value::binary>>
    end
  end

  defp encode_attribute({tag, name, value}) when tag in [:boolean] do
    <<value_tag(tag)::8-signed, byte_size(name)::16-signed, name::binary, 1::16-signed,
      bool_to_int(value)::8-signed>>
  end

  defp encode_attribute({tag, name, value}) when tag in [:integer, :enum] do
    <<value_tag(tag)::8-signed, byte_size(name)::16-signed, name::binary, 4::16-signed,
      value::size(4)-unit(8)-signed>>
  end

  defp encode_attribute({{:set1, tag}, name, value})
       when tag in [:integer, :enum] and is_list(value) do
    [head_value | tail] = value

    bin =
      <<value_tag(tag)::8-signed, byte_size(name)::16-signed, name::binary, 4::16-signed,
        head_value::size(4)-unit(8)-signed>>

    for addl_value <- tail, into: bin do
      <<value_tag(tag)::8-signed, 0::16-signed, 4::16-signed, addl_value::size(4)-unit(8)-signed>>
    end
  end

  defp encode_attribute({tag, name, value}) do
    {:error, {:invalid_tag, tag, name, value}}
  end

  defp request_header(req) do
    <<req.version.major::8-signed, req.version.minor::8-signed, req.operation_id::16-signed,
      req.request_id::32-signed, DelimiterTag.operation_attributes()::8-signed>>
  end

  defp value_tag(tag) when is_atom(tag), do: ValueTag.encode!(tag)
  defp value_tag(tag), do: tag
  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
end
