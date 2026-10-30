# Downloads the IANA IPP registry and extracts:
#
#   * the enum values, status codes and tags into test/fixtures/ipp_registry.json, which
#     test/ipp_registry_test.exs checks the Hippy.IPP modules against, and
#   * the attribute definitions into lib/ipp/attributes.eterm, which Hippy.IPP.Attributes
#     compiles in.
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

# Attribute definitions.

# Names can end in a status, e.g. "compression(obsolete)". "(extension)" marks a row that extends
# an attribute defined elsewhere, not a status of the attribute.
clean_name = fn name ->
  case Regex.run(~r/^(.+?)\s*\((deprecated|obsolete|extension)\)$/, name) do
    [_, name, "extension"] -> {name, nil}
    [_, name, status] -> {name, String.to_atom(status)}
    nil -> {name, nil}
  end
end

types = %{
  "integer" => :integer,
  "boolean" => :boolean,
  "enum" => :enum,
  "octetstring" => :octet_string,
  "datetime" => :datetime,
  "resolution" => :resolution,
  "rangeofinteger" => :range_of_integer,
  "collection" => :collection,
  "text" => :text,
  "name" => :name,
  "keyword" => :keyword,
  "uri" => :uri,
  "urischeme" => :uri_scheme,
  "charset" => :charset,
  "naturallanguage" => :natural_language,
  "mimemediatype" => :mime_media_type,
  "no-value" => :no_value,
  "unknown" => :unknown
}

limit = fn
  nil -> nil
  "MAX" -> :max
  "MIN" -> :min
  value -> String.to_integer(value)
end

# The registry's syntax strings vary ("1setOf (type2 keyword | name(MAX))", "integer(1:MAX)",
# "integer:0:MAX", "text(MAX) | 'no-value'"), so pick out the type names and their limits.
parse_syntax = fn syntax ->
  parsed =
    Regex.scan(
      ~r/(no-value|unknown|[a-zA-Z]+)\s*(?:[(:]\s*(-?\d+|MIN|MAX)\s*(?::\s*(-?\d+|MIN|MAX))?\s*\)?)?/,
      syntax
    )
    |> Enum.flat_map(fn match ->
      case {Map.fetch(types, String.downcase(Enum.at(match, 1))), Enum.drop(match, 2)} do
        {:error, _} -> []
        {{:ok, type}, []} -> [{type, nil}]
        {{:ok, type}, [max]} -> [{type, limit.(max)}]
        {{:ok, type}, [min, max]} -> [{type, {limit.(min), limit.(max)}}]
      end
    end)
    |> Enum.uniq()

  %{types: parsed, set: String.contains?(syntax, "1setOf")}
end

merge_definition = fn
  nil, new -> new
  old, new -> %{old | types: Enum.uniq(old.types ++ new.types), set: old.set or new.set}
end

# "<Any "media-col" member attribute>" means the same members as media-col.
like = fn member ->
  case Regex.run(~r/^<Any "([a-z0-9-]+)" member attribute>$/, member) do
    [_, name] -> name
    nil -> nil
  end
end

# An attribute is only deprecated or obsolete if every row for it says so.
merge_status = fn
  :unset, new -> new
  same, same -> same
  _old, _new -> nil
end

put_definition = fn attributes, path, definition, group ->
  update_in(attributes, Enum.map(path, &Access.key(&1, nil)), fn existing ->
    existing = existing || %{types: [], set: false, members: %{}, groups: [], status: :unset}
    merged = merge_definition.(existing, definition)
    groups = if group, do: Enum.uniq(merged.groups ++ [group]), else: merged.groups
    status = if Map.has_key?(definition, :status), do: merge_status.(existing.status, definition.status), else: existing.status
    %{merged | groups: groups, status: status}
  end)
end

group_atom = fn group -> group |> String.downcase() |> String.replace(" ", "_") |> String.to_atom() end

{attributes, likes} =
  for record <- records.("ipp-registrations-2"), reduce: {%{}, []} do
    {attributes, likes} ->
      {name, status} = clean_name.(text.(record, "name"))
      group = group_atom.(text.(record, "collection"))
      definition = Map.put(parse_syntax.(text.(record, "syntax")), :status, status)

      {member, member_status} = clean_name.(text.(record, "member_attribute"))
      {sub, sub_status} = clean_name.(text.(record, "sub-member_attribute"))

      cond do
        member == "" ->
          {put_definition.(attributes, [name], definition, group), likes}

        base = like.(member) ->
          # "(extension)" rows can say a collection has any of its own members, which adds
          # nothing.
          likes = if base == name, do: likes, else: [{[name], base} | likes]
          {put_definition.(attributes, [name], %{types: [], set: false}, group), likes}

        sub == "" ->
          attributes = put_definition.(attributes, [name], %{types: [], set: false}, group)
          definition = %{definition | status: member_status}
          {put_definition.(attributes, [name, :members, member], definition, nil), likes}

        base = like.(sub) ->
          {attributes, [{[name, :members, member], base} | likes]}

        true ->
          definition = %{definition | status: sub_status}
          path = [name, :members, member, :members, sub]
          {put_definition.(attributes, path, definition, nil), likes}
      end
  end

# Record "same members as media-col" as a reference rather than copying the members.
# Hippy.IPP.Attributes follows it when looking an attribute up.
attributes =
  Enum.reduce(likes, attributes, fn {path, base}, attributes ->
    update_in(attributes, Enum.map(path, &Access.key(&1, nil)), fn
      nil -> %{types: [{:collection, nil}], set: false, members: %{}, status: :unset, like: base}
      existing -> Map.put(existing, :like, base)
    end)
  end)

# Members don't belong to groups of their own, and attributes only created by a member row have
# no status of their own. Fields with their default value are left out to keep the file small.
compact = fn compact, definition, member? ->
  definition
  |> Map.update!(:status, &if(&1 == :unset, do: nil, else: &1))
  |> Map.update!(:members, fn members ->
    Map.new(members, fn {name, member} -> {name, compact.(compact, member, true)} end)
  end)
  |> then(&if(member?, do: Map.delete(&1, :groups), else: &1))
  |> Map.reject(fn field -> field in [{:set, false}, {:status, nil}, {:members, %{}}] end)
end

eterm = Path.expand("../lib/ipp/attributes.eterm", __DIR__)

File.write!(eterm, [
  "%% Generated by scripts/update_ipp_registry.exs from the IANA IPP registry. Do not edit.\n",
  "%% One attribute per line. Fields with their default value (set false, status nil, no\n",
  "%% members) are left out, and like is a collection with the same members as another.\n",
  :io_lib.format(~c"~tp.~n", [{:updated, updated}]),
  for {name, definition} <- Enum.sort(attributes) do
    :io_lib.format(~c"~1000000tp.~n", [{name, compact.(compact, definition, false)}])
  end
])

IO.puts("Wrote #{eterm}: #{map_size(attributes)} attributes")

path = Path.expand("../test/fixtures/ipp_registry.json", __DIR__)
File.mkdir_p!(Path.dirname(path))
File.write!(path, Jason.encode_to_iodata!(registry, pretty: true))

IO.puts(
  "Wrote #{path} (registry updated #{updated}): #{map_size(enums)} enum attributes, " <>
    "#{map_size(aliases)} aliases"
)
