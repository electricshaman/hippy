defmodule Hippy.AttributeInference do
  @moduledoc """
  Works out each attribute's syntax and group from the IANA registry (`Hippy.IPP.Attributes`),
  so attributes can be given as plain names and values:

      PrintJob.new(uri, doc,
        attributes: %{
          "copies" => 2,
          "sides" => "two-sided-long-edge",
          "orientation-requested" => :landscape,
          "media-col" => %{"media-size" => %{"x-dimension" => 21000, "y-dimension" => 29700}}
        }
      )

  ## Syntax

  The syntax comes from the attribute's registered types and the value:

    * Integers, booleans, `DateTime`, `Range`, `URI` and `Hippy.PrintResolution` values map to
      the matching type. For an enum attribute, an integer or an atom such as `:landscape` (see
      `Hippy.IPP.Enum`).
    * Strings: for attributes that can be a keyword or a name (such as `media`), a string spelt
      like a keyword (lowercase letters, digits, `-`, `_` and `.`) is sent as a keyword, and
      anything else as a name. Otherwise the attribute's string type (`text`, `uri`,
      `mimeMediaType`, ...) is used. `{language, text}` is text or name with a language.
    * Maps are collections, with each member's syntax taken from its own definition.
    * Lists are sets, and each value's syntax is worked out separately.
    * `{syntax, value}` gives the syntax explicitly, e.g. `{:name_without_language, "plain"}`.

  ## Group

  Attributes go in the group their operation is mainly about (job template attributes for
  Print-Job and Validate-Job, printer attributes for CUPS-Add-Modify-Printer and
  Set-Printer-Attributes, subscription attributes for Create-Printer-Subscriptions, ...), if
  they're registered there, and otherwise in the operation attributes or another group they're
  registered in.

  Attributes the registry doesn't know (vendor and CUPS attributes such as `device-uri`) need
  their syntax, as `{syntax, value}`, and go in the operation's main group, or the operation
  attributes for operations without one. To put one elsewhere, use an operation's
  `operation_attributes:`, `job_attributes:` or `groups:` options. A value that doesn't fit an
  attribute's types raises `ArgumentError`.
  """

  alias Hippy.IPP.Attributes

  # The registry group an operation's own attributes belong to.
  @operation_groups %{
    print_job: :job_template,
    print_uri: :job_template,
    validate_job: :job_template,
    create_job: :job_template,
    set_job_attributes: :job_template,
    set_printer_attributes: :printer_description,
    cups_add_modify_printer: :printer_description,
    cups_add_modify_class: :printer_description,
    create_printer: :printer_description,
    create_printer_subscription: :subscription_template,
    create_job_subscription: :subscription_template,
    create_resource_subscriptions: :subscription_template,
    create_system_subscriptions: :subscription_template,
    send_document: :document_template,
    send_uri: :document_template,
    set_document_attributes: :document_template,
    set_system_attributes: :system_description,
    set_resource_attributes: :resource_description
  }

  @fallback_groups [
    :operation,
    :job_template,
    :subscription_template,
    :printer_description,
    :document_template,
    :job_description,
    :document_description,
    :system_description,
    :resource_description
  ]

  # Where each registry group's attributes go in a request.
  @request_groups %{
    operation: :operation,
    job_template: :job,
    job_description: :job,
    subscription_template: :subscription_attributes,
    printer_description: :printer_attributes,
    document_template: :document_attributes,
    document_description: :document_attributes,
    system_description: :system_attributes,
    resource_description: :resource_attributes
  }

  @out_of_band [
    :no_value,
    :unknown,
    :unsupported,
    :not_settable,
    :delete_attribute,
    :admin_define
  ]
  @strings [:uri, :uri_scheme, :charset, :natural_language, :mime_media_type, :octet_string]

  @doc """
  Places attributes for an operation, returning `%{operation: [...], job: [...], groups: [...]}`
  with attribute tuples ready for `Hippy.Request`.
  """
  def place(operation_id, attributes) do
    placed =
      attributes
      |> Enum.sort()
      |> Enum.group_by(fn {name, value} -> place_group(operation_id, name, value) end, fn
        {name, value} -> attribute(name, value)
      end)
      |> Map.new(fn {group, tuples} -> {group, List.flatten(tuples)} end)

    %{
      operation: Map.get(placed, :operation, []),
      job: Map.get(placed, :job, []),
      groups: for({group, tuples} <- placed, group not in [:operation, :job], do: {group, tuples})
    }
  end

  # Unregistered attributes with an explicit syntax go in the operation's main group.
  defp place_group(operation_id, name, value) do
    if Attributes.known?(name) or not explicit?(value) do
      group(operation_id, name)
    else
      case main_group(operation_id) do
        [group] -> @request_groups[group]
        [] -> :operation
      end
    end
  end

  defp explicit?({syntax, _value}) when is_atom(syntax) and syntax not in [true, false, nil],
    do: true

  defp explicit?(_value), do: false

  defp main_group(operation_id) do
    case Hippy.IPP.Operation.decode(operation_id) do
      {:ok, operation} -> List.wrap(@operation_groups[operation])
      {:error, _} -> []
    end
  end

  @doc """
  Returns where an attribute goes in a request for an operation: `:operation`, `:job`, or a
  group tag such as `:printer_attributes`. Raises `ArgumentError` for attributes the registry
  doesn't know, or that can't be sent in a request.
  """
  def group(operation_id, name) do
    groups =
      Attributes.groups(name) ||
        raise ArgumentError,
              "#{inspect(name)} isn't in the IANA registry, so its syntax can't be inferred. " <>
                "Give it as {syntax, value}, or as {syntax, name, value} with " <>
                "operation_attributes:, job_attributes: or groups:"

    case Enum.find(main_group(operation_id) ++ @fallback_groups, &(&1 in groups)) do
      nil ->
        raise ArgumentError,
              "#{inspect(name)} is only registered in #{inspect(groups)}, which aren't sent in " <>
                "requests"

      group ->
        @request_groups[group]
    end
  end

  @doc """
  Returns the attribute tuples for a registered attribute and value, e.g.
  `[{:integer, "copies", 2}]`. A set whose values have different syntaxes gives one tuple per
  value, with `nil` as the name of the additional values.
  """
  def attribute(name, value) do
    if not Attributes.known?(name) and not explicit?(value) do
      raise ArgumentError,
            "#{inspect(name)} isn't in the IANA registry, so its syntax can't be inferred. " <>
              "Give it as {syntax, value}"
    end

    case values([name], value) do
      [] ->
        raise ArgumentError, "can't send an empty list as #{inspect(name)}"

      [{syntax, value}] ->
        [{syntax, name, value}]

      [{syntax, _} | _] = values ->
        if Enum.all?(values, &(elem(&1, 0) == syntax)),
          do: [{syntax, name, Enum.map(values, &elem(&1, 1))}],
          else: Enum.with_index(values, fn {s, v}, i -> {s, if(i == 0, do: name), v} end)
    end
  end

  # A list of {syntax, value}, one per value.
  defp values(_path, {syntax, value}) when is_atom(syntax) and syntax not in [true, false, nil] do
    value |> List.wrap() |> Enum.map(&{syntax, &1})
  end

  defp values(path, values) when is_list(values), do: Enum.flat_map(values, &values(path, &1))
  defp values(path, value), do: [value(path, types!(path), value)]

  defp types!(path) do
    Attributes.types(path) ||
      raise ArgumentError, "#{inspect(Enum.join(path, "/"))} isn't in the IANA registry"
  end

  defp value(path, types, value) do
    allowed = Keyword.keys(types)

    case syntax(allowed, value) do
      nil ->
        raise ArgumentError,
              "can't send #{inspect(value)} as #{Enum.join(path, "/")}, which takes " <>
                Enum.map_join(allowed, " | ", &to_string/1)

      :collection ->
        {:collection, members(path, value)}

      :enum when is_atom(value) ->
        {:enum, enum!(path, value)}

      syntax ->
        {syntax, value}
    end
  end

  defp syntax(allowed, value) when is_boolean(value), do: if(:boolean in allowed, do: :boolean)

  defp syntax(allowed, value) when value in @out_of_band,
    do: if(value in allowed or value == :no_value, do: value)

  defp syntax(allowed, value) when is_atom(value), do: if(:enum in allowed, do: :enum)

  defp syntax(allowed, value) when is_integer(value),
    do: Enum.find([:integer, :enum], &(&1 in allowed))

  defp syntax(allowed, %Range{}), do: if(:range_of_integer in allowed, do: :range_of_integer)
  defp syntax(allowed, %DateTime{}), do: if(:datetime in allowed, do: :datetime)
  defp syntax(allowed, %URI{}), do: if(:uri in allowed, do: :uri)
  defp syntax(allowed, %Hippy.PrintResolution{}), do: if(:resolution in allowed, do: :resolution)
  defp syntax(_allowed, %_{}), do: nil
  defp syntax(allowed, value) when is_map(value), do: if(:collection in allowed, do: :collection)

  defp syntax(allowed, {language, text}) when is_binary(language) and is_binary(text) do
    cond do
      :text in allowed -> :text_with_language
      :name in allowed -> :name_with_language
      true -> nil
    end
  end

  defp syntax(allowed, value) when is_binary(value) do
    keyword? = value =~ ~r/^[a-z0-9][a-z0-9._-]*$/

    cond do
      :keyword in allowed and (keyword? or :name not in allowed) -> :keyword
      :name in allowed -> :name_without_language
      :text in allowed -> :text_without_language
      true -> Enum.find(@strings, &(&1 in allowed))
    end
  end

  defp syntax(_allowed, _value), do: nil

  defp members(path, members) do
    Map.new(members, fn {member, value} ->
      case values(path ++ [member], value) do
        [single] -> {member, single}
        values -> {member, values}
      end
    end)
  end

  defp enum!(path, key) do
    case Hippy.IPP.Enum.encode(List.last(path), key) do
      {:ok, value} ->
        value

      {:error, _} ->
        raise ArgumentError, "#{inspect(key)} isn't a value of #{Enum.join(path, "/")}"
    end
  end
end
