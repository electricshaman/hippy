defmodule Hippy.ValueTag do
  use Hippy.Enum, %{
    integer: 0x21,
    boolean: 0x22,
    enum: 0x23,
    octet_string: 0x30,
    datetime: 0x31,
    resolution: 0x32,
    range_of_integer: 0x33,
    beg_collection: 0x34,
    text_with_language: 0x35,
    name_with_language: 0x36,
    end_collection: 0x37,
    text_without_language: 0x41,
    name_without_language: 0x42,
    keyword: 0x44,
    uri: 0x45,
    uri_scheme: 0x46,
    charset: 0x47,
    natural_language: 0x48,
    mime_media_type: 0x49,
    member_attr_name: 0x4A
  }
end
