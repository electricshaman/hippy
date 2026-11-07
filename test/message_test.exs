defmodule Hippy.MessageTest do
  use ExUnit.Case, async: true

  alias Hippy.Message

  test "captured responses decode exactly and re-encode to the same bytes" do
    for path <- Path.wildcard("test/captures/*_res.bin") do
      bin = File.read!(path)
      assert Message.encode(Message.decode(bin)) == bin, path
    end
  end

  test "groups are kept in order, one per job" do
    message = Message.decode(File.read!("test/captures/ipp_get_jobs_res.bin"))
    [{:operation, _} | jobs] = message.groups

    assert length(jobs) > 1
    assert Enum.all?(jobs, &match?({:job, _}, &1))

    {:job, attributes} = hd(jobs)
    assert {"job-id", [integer: id]} = List.keyfind(attributes, "job-id", 0)
    assert is_integer(id)
  end

  test "values are as on the wire" do
    message = Message.decode(File.read!("test/captures/get_printer_attributes_res.bin"))
    {:printer, attributes} = List.keyfind(message.groups, :printer, 0)

    assert {"printer-state", [enum: state]} = List.keyfind(attributes, "printer-state", 0)
    assert is_integer(state)

    assert {"printer-is-accepting-jobs", [boolean: accepting]} =
             List.keyfind(attributes, "printer-is-accepting-jobs", 0)

    assert accepting in [0, 1]

    assert {"printer-uri-supported", [{:uri, uri} | _]} =
             List.keyfind(attributes, "printer-uri-supported", 0)

    assert is_binary(uri)
    assert message.code == 0
    assert Message.status(message) == :successful_ok
  end

  test "status and operation as atoms, or integers when unknown" do
    assert Message.status(%Message{code: 0x0406}) == :client_error_not_found
    assert Message.status(%Message{code: 0x04FF}) == 0x04FF
    assert Message.operation(%Message{code: 0x0002}) == :print_job
    assert Message.operation(%Message{code: 0x7777}) == 0x7777
  end

  test "generated messages round-trip in both directions" do
    :rand.seed(:exsss, {7, 8, 9})

    for _ <- 1..300 do
      message = %Message{
        version: Enum.random([{1, 1}, {2, 0}]),
        # Operation ids and status codes are signed 16-bit integers (RFC 8010).
        code: :rand.uniform(0x7FFF) - 1,
        request_id: :rand.uniform(1_000_000),
        groups:
          for _ <- 1..:rand.uniform(5) do
            tag = Enum.random([:operation, :job, :printer, :subscription, :document, 0x0B])
            {tag, for(_ <- 1..:rand.uniform(5), do: random_attribute())}
          end,
        data: :crypto.strong_rand_bytes(:rand.uniform(16) - 1)
      }

      bin = Message.encode(message)
      assert Message.decode(bin) == message, inspect(message, limit: :infinity)
      assert Message.encode(Message.decode(bin)) == bin
    end
  end

  test "streamed data" do
    message = %Message{code: 2, request_id: 1, groups: [{:operation, []}], data: ["ab", "cd"]}
    assert Enum.join(Message.encode(message)) == Message.encode(%{message | data: "abcd"})
  end

  test "invalid messages raise" do
    assert_raise ArgumentError, ~r/unknown attribute group :bogus/, fn ->
      Message.encode(%Message{code: 2, request_id: 1, groups: [{:bogus, []}]})
    end

    assert_raise ArgumentError, ~r/request_id is required/, fn ->
      Message.encode(%Message{code: 2, groups: []})
    end
  end

  defp random_attribute do
    {"x-#{:rand.uniform(500)}", for(_ <- 1..:rand.uniform(3), do: random_value(2))}
  end

  defp random_value(depth) do
    values = [
      {:integer, :rand.uniform(1_000_000) - 500_000},
      {:enum, :rand.uniform(100)},
      {:boolean, :rand.uniform(2) - 1},
      {:keyword, "kw-#{:rand.uniform(100)}"},
      {:name_without_language, "Name #{:rand.uniform(100)}"},
      {:text_with_language, {"en", "text"}},
      {:datetime, {2026, 11, 7, 9, 30, 0, 0, "+", 0, 0}},
      {:resolution, {600, 600, 3}},
      {:range_of_integer, {1, :rand.uniform(50)}},
      {:no_value, nil},
      {0x60, :crypto.strong_rand_bytes(2)}
    ]

    collection =
      if depth > 0,
        do: [
          {:collection,
           [
             {"a", [random_value(depth - 1)]},
             {"b", [random_value(depth - 1), random_value(depth - 1)]}
           ]}
        ],
        else: []

    Enum.random(values ++ collection)
  end
end
