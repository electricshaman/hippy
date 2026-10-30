defmodule Hippy.RoundTripTest do
  @moduledoc """
  Decoding with `raw: true` and encoding again gives back the original bytes.

  Requests and responses share a layout, so a raw response is re-encoded by turning it into a
  `Hippy.Request` with the same groups (in the order of `Hippy.Response`'s fields).
  """

  use ExUnit.Case, async: true

  alias Hippy.{Decoder, Encoder}

  @groups [
    :job_attributes,
    :printer_attributes,
    :unsupported_attributes,
    :subscription_attributes,
    :event_notification_attributes,
    :resource_attributes,
    :document_attributes,
    :system_attributes
  ]

  defp to_request(res) do
    groups =
      for field <- @groups, group <- groups(Map.fetch!(res, field)), group != [] do
        {field, group}
      end

    %Hippy.Request{
      version: res.version,
      operation_id: res.status_code,
      request_id: res.request_id,
      operation_attributes: res.operation_attributes,
      groups: groups,
      data: res.data
    }
  end

  # Repeated groups are lists of groups; the others are a single group.
  defp groups([first | _] = groups) when is_list(first), do: groups
  defp groups(group), do: [group]

  defp round_trip(bin), do: bin |> Decoder.decode(raw: true) |> to_request() |> Encoder.encode()

  test "captured responses from real printers re-encode to the same bytes" do
    for path <- Path.wildcard("test/captures/*_res.bin") do
      bin = File.read!(path)
      assert round_trip(bin) == bin, "#{path} didn't round-trip"
    end
  end

  describe "raw decoding" do
    setup do
      %{
        res: Decoder.decode(File.read!("test/captures/get_printer_attributes_res.bin"), raw: true)
      }
    end

    test "keeps values as they were on the wire", %{res: %{printer_attributes: [printer]} = res} do
      assert is_integer(res.status_code)

      assert {:enum, "printer-state", state} = List.keyfind(printer, "printer-state", 1)
      assert is_integer(state)

      assert {:uri, "printer-uri-supported", uri} =
               List.keyfind(printer, "printer-uri-supported", 1)

      assert is_binary(uri)

      assert {:boolean, "printer-is-accepting-jobs", accepting} =
               List.keyfind(printer, "printer-is-accepting-jobs", 1)

      assert accepting in [0, 1]
    end

    test "keeps one tuple per value, and repeated attributes", %{
      res: %{printer_attributes: [printer]}
    } do
      # Additional values have no name.
      assert Enum.any?(printer, &match?({_, nil, _}, &1))

      # The capture's printer repeats some attributes by name; raw decoding keeps both.
      names = for {_, name, _} <- printer, name != nil, do: name
      assert length(names) > length(Enum.uniq(names))
    end
  end

  test "generated messages round-trip" do
    :rand.seed(:exsss, {1, 2, 3})

    for _ <- 1..200 do
      # Hippy.Response keeps each kind of group in its own field, so groups of different kinds
      # only round-trip in that order (#47 removes this limit).
      groups =
        for _ <- 1..:rand.uniform(4) do
          {Enum.random([:job_attributes, :printer_attributes, :subscription_attributes]),
           Enum.flat_map(1..:rand.uniform(6), fn _ -> random_attribute() end)}
        end
        |> Enum.sort_by(fn {field, _} -> Enum.find_index(@groups, &(&1 == field)) end)

      req = %Hippy.Request{
        operation_id: Enum.random([0x0000, 0x0001, 0x0400, 0x0406]),
        request_id: :rand.uniform(1000),
        operation_attributes: [{:charset, "attributes-charset", "utf-8"}],
        groups: groups,
        data: :crypto.strong_rand_bytes(:rand.uniform(8) - 1)
      }

      bin = Encoder.encode(req)
      assert round_trip(bin) == bin, "didn't round-trip: #{inspect(req, limit: :infinity)}"
    end
  end

  defp random_attribute do
    name = "x-#{:rand.uniform(1000)}"

    values =
      for _ <- 1..:rand.uniform(3) do
        Enum.random([
          {:integer, :rand.uniform(1_000_000) - 500_000},
          {:enum, :rand.uniform(100)},
          {:boolean, :rand.uniform(2) - 1},
          {:keyword, "kw-#{:rand.uniform(100)}"},
          {:text_with_language, {"en", "text #{:rand.uniform(100)}"}},
          {:datetime, {2026, 10, 30, 12, 30, 15, 3, "-", 4, 0}},
          {:resolution, {600, 300, 3}},
          {:range_of_integer, {1, :rand.uniform(100)}},
          {:no_value, :no_value},
          {0x60, :crypto.strong_rand_bytes(3)},
          {:collection,
           [{"m", {:integer, nil, 1}}, {"a", [{:keyword, nil, "x"}, {:keyword, nil, "y"}]}]}
        ])
      end

    # The first value carries the name, and any others are additional values (a set), possibly
    # in mixed syntaxes.
    [{syntax, value} | rest] = values
    [{syntax, name, value} | Enum.map(rest, fn {s, v} -> {s, nil, v} end)]
  end
end
