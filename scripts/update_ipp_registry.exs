# Downloads the IANA IPP registry and extracts the values Hippy defines into
# test/fixtures/ipp_registry.json, which test/ipp_registry_test.exs checks the Hippy.IPP modules
# against.
#
#     mix run scripts/update_ipp_registry.exs [path/to/ipp-registrations.xml]

Mix.ensure_application!(:xmerl)

url = "https://www.iana.org/assignments/ipp-registrations/ipp-registrations.xml"

xml =
  case System.argv() do
    [path] -> File.read!(path)
    [] -> Req.get!(url, decode_body: false).body
  end

# xmerl rejects the <?xml-stylesheet?> and <?xml-model?> processing instructions, which are only
# for browsers.
{doc, _} =
  Regex.replace(~r/<\?xml-[a-z]+ [^?]*\?>/, xml, "")
  |> :binary.bin_to_list()
  |> :xmerl_scan.string(quiet: true)

text = fn node, tag ->
  :xmerl_xpath.string(~c"./#{tag}//text()", node)
  |> Enum.map_join(fn {:xmlText, _, _, _, value, _} -> to_string(value) end)
  |> String.trim()
end

records = fn registry_id ->
  :xmerl_xpath.string(~c"//registry[@id='#{registry_id}']/record", doc)
end

# Values look like "0x0003", "7" or "0x0003(deprecated)". Ranges and placeholders are skipped.
parse_value = fn value ->
  case Regex.run(~r/^(0x[0-9A-Fa-f]+|\d+)\s*(?:\((deprecated|obsolete)\))?$/, value) do
    [_, number | status] ->
      {number |> String.replace_prefix("0x", "") |> String.to_integer(if number =~ "0x", do: 16, else: 10),
       List.first(status)}

    nil ->
      nil
  end
end

named_values = fn registry_id ->
  for record <- records.(registry_id),
      {number, _status} <- [parse_value.(text.(record, "value"))],
      name = text.(record, "name"),
      name != "" and not String.starts_with?(name, ["Reserved", "Unassigned"]),
      into: %{} do
    {Integer.to_string(number), name}
  end
end

{enums, aliases} =
  for record <- records.("ipp-registrations-6"), reduce: {%{}, %{}} do
    {enums, aliases} ->
      attribute = text.(record, "attribute")
      value = text.(record, "value")
      name = text.(record, "name")
      assigned? = name != "" and not String.starts_with?(name, ["Reserved", "Unassigned"])

      case {parse_value.(value), Regex.run(~r/"([a-z0-9-]+)"/, value)} do
        {{number, status}, _} when assigned? ->
          entry = %{"name" => name, "status" => status}
          {put_in(enums, [Access.key(attribute, %{}), Integer.to_string(number)], entry), aliases}

        {nil, [_, base]} ->
          {enums, Map.put(aliases, attribute, base)}

        _ ->
          {enums, aliases}
      end
  end

updated = :xmerl_xpath.string(~c"/registry/updated/text()", doc) |> hd() |> elem(4) |> to_string()

registry = %{
  "source" => url,
  "updated" => updated,
  "enums" => enums,
  "enum_aliases" => aliases,
  "status_codes" => named_values.("ipp-registrations-11"),
  "delimiter_tags" => named_values.("ipp-registrations-7"),
  "value_tags" =>
    Map.merge(named_values.("ipp-registrations-9"), named_values.("ipp-registrations-8"))
}

path = Path.expand("../test/fixtures/ipp_registry.json", __DIR__)
File.mkdir_p!(Path.dirname(path))
File.write!(path, Jason.encode_to_iodata!(registry, pretty: true))

IO.puts(
  "Wrote #{path} (registry updated #{updated}): #{map_size(enums)} enum attributes, " <>
    "#{map_size(aliases)} aliases"
)
