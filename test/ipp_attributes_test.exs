defmodule Hippy.IPP.AttributesTest do
  use ExUnit.Case, async: true

  alias Hippy.IPP.Attributes

  @registry "test/fixtures/ipp_registry.json" |> File.read!() |> Jason.decode!()

  test "describes registered attributes" do
    assert Attributes.get("copies") == %{
             types: [integer: {1, :max}],
             set: false,
             groups: [:document_template, :job_template],
             status: nil,
             members: %{}
           }

    assert Attributes.set?("job-state-reasons")
    assert Attributes.types("job-state-reasons") == [keyword: nil]
    assert Attributes.types("media") == [keyword: nil, name: :max]
    assert Attributes.types("printer-resolution-supported") == [resolution: nil]
    assert :subscription_template in Attributes.groups("notify-events")
    assert :operation in Attributes.groups("job-name")
  end

  test "describes collection members, by path" do
    assert "media-size" in Map.keys(Attributes.members("media-col"))
    assert Attributes.types(["media-col", "media-size"]) == [collection: nil]
    assert Attributes.types(["media-col", "media-size", "x-dimension"]) == [integer: {1, :max}]
    assert Attributes.get(["media-col", "media-size", "missing"]) == nil

    # media-col-actual is registered as having the same members as media-col.
    assert Attributes.members("media-col-actual") == Attributes.members("media-col")
  end

  test "references to another collection's members are resolved" do
    for name <- Attributes.names(), definition = Attributes.get(name) do
      refute Map.has_key?(definition, :like), name

      for {member, member_definition} <- definition.members do
        refute Map.has_key?(member_definition, :like), "#{name} #{member}"
      end
    end
  end

  test "marks deprecated and obsolete attributes, but not ones that are only partly so" do
    assert Attributes.get("document-format-supplied").status == :obsolete

    # Obsolete in Document Status, but current as a Print-Job operation attribute.
    assert Attributes.get("compression").status == nil

    # "(extension)" in the registry isn't a status.
    assert Attributes.get("finishings-col").status == nil
  end

  test "unregistered attributes" do
    assert Attributes.get("x-vendor-attribute") == nil
    refute Attributes.known?("x-vendor-attribute")
    assert Attributes.set?("x-vendor-attribute") == nil
  end

  test "every attribute has types or members, and belongs to a group" do
    for name <- Attributes.names(), definition = Attributes.get(name) do
      assert definition.types != [] or definition.members != %{}, name
      assert definition.groups != [], name
    end
  end

  test "agrees with the enum values from the same registry" do
    assert Attributes.registry_updated() == @registry["updated"]

    for name <- Map.keys(@registry["enums"]) ++ Map.keys(@registry["enum_aliases"]),
        Attributes.known?(name) do
      assert Keyword.has_key?(Attributes.types(name), :enum), "#{name} should be an enum"
    end
  end
end
