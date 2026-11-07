defmodule Hippy.EncoderTest do
  use ExUnit.Case

  alias Hippy.{Encoder, Message, Operation}

  defp operation_attributes(%Message{groups: [{:operation, attributes} | _]}), do: attributes

  test "job attributes are encoded in a job attributes group" do
    bin =
      Operation.PrintJob.new("http://localhost:631/printers/p", "DOC")
      |> Operation.build_request()
      |> Map.put(:request_id, 1)
      |> Encoder.encode()

    orientation = Hippy.IPP.Orientation.portrait()

    assert String.ends_with?(
             bin,
             <<0x02, 0x23, 21::16, "orientation-requested", 4::16, orientation::32, 0x03, "DOC">>
           )
  end

  test "requests without job attributes have no job attributes group" do
    bin =
      Operation.GetPrinterAttributes.new("http://localhost:631/printers/p")
      |> Operation.build_request()
      |> Map.put(:request_id, 1)
      |> Encoder.encode()

    assert String.ends_with?(bin, <<"ipp://localhost:631/printers/p", 0x03>>)
  end

  test "requests start with the common operation attributes" do
    message =
      Operation.CancelJob.new("https://localhost/printers/p", 7,
        charset: "us-ascii",
        language: "fr"
      )
      |> Operation.build_request()

    assert operation_attributes(message) == [
             {"attributes-charset", [charset: "us-ascii"]},
             {"attributes-natural-language", [natural_language: "fr"]},
             {"printer-uri", [uri: "ipps://localhost/printers/p"]},
             {"job-id", [integer: 7]}
           ]
  end

  test "groups are encoded in order" do
    attr = fn tag, name, value ->
      <<tag, byte_size(name)::16, name::binary, byte_size(value)::16, value::binary>>
    end

    message = %Message{
      code: 0x02,
      request_id: 1,
      groups: [
        {:operation, []},
        {:job, [{"copies", [integer: 2]}]},
        {:subscription, [{"notify-events", [keyword: "job-completed"]}]},
        {:printer, [{"printer-location", [text_without_language: "Lab"]}]},
        {:subscription, [{"notify-events", [keyword: "printer-stopped"]}]}
      ]
    }

    assert Encoder.encode(message) ==
             <<1, 1, 0x02::16, 1::32, 0x01>> <>
               <<0x02>> <>
               attr.(0x21, "copies", <<2::32>>) <>
               <<0x06>> <>
               attr.(0x44, "notify-events", "job-completed") <>
               <<0x04>> <>
               attr.(0x41, "printer-location", "Lab") <>
               <<0x06>> <> attr.(0x44, "notify-events", "printer-stopped") <> <<0x03>>
  end

  test "invalid groups are rejected" do
    for group <- [{:end_of_attributes, []}, {:bogus, []}, :printer] do
      assert_raise ArgumentError, fn ->
        Encoder.encode(%Message{code: 0x0B, request_id: 1, groups: [group]})
      end
    end
  end

  test "documents can be an enumerable of binaries" do
    message = %Message{code: 0x02, request_id: 1, data: ["ab", "cd"]}

    stream = Encoder.encode(message)
    refute is_binary(stream)
    assert stream |> Enum.join() == Encoder.encode(%{message | data: "abcd"})

    assert_raise ArgumentError, ~r/data must be a binary or an Enumerable/, fn ->
      Encoder.encode(%{message | data: 123})
    end
  end

  test "messages without a request id are rejected" do
    assert_raise ArgumentError, ~r/request_id is required/, fn ->
      Encoder.encode(%Message{code: 0x0B})
    end
  end

  test "which-jobs atoms are encoded as hyphenated keywords" do
    message =
      Operation.GetJobs.new("http://localhost:631/printers/p", which_jobs: :not_completed)
      |> Operation.build_request()

    assert {"which-jobs", [keyword: "not-completed"]} in operation_attributes(message)
  end
end

defmodule Hippy.EncoderValuesTest do
  use ExUnit.Case, async: true

  alias Hippy.{Encoder, Message, PrintResolution}

  # Build a request from {syntax, name, value} tuples, encode it, decode it (requests and
  # responses share a layout) and read its operation attributes as a map.
  defp round_trip(tuples) do
    0x02
    |> Message.build_request(%{charset: "utf-8", language: "en"}, tuples)
    |> Map.put(:request_id, 1)
    |> Encoder.encode()
    |> Message.decode()
    |> Message.operation_attributes()
    |> Map.drop(["attributes-charset", "attributes-natural-language"])
  end

  test "every value syntax round-trips" do
    media_col =
      {:collection, "media-col",
       %{
         "media-size" =>
           {:collection,
            %{"x-dimension" => {:integer, 21000}, "y-dimension" => {:integer, 29700}}},
         "media-type" => {:keyword, "stationery"}
       }}

    assert round_trip([
             {:integer, "copies", -2},
             {:enum, "x-unregistered-enum", 4},
             {:boolean, "ipp-attribute-fidelity", true},
             {:boolean, "x-false", false},
             {:keyword, "sides", "two-sided-long-edge"},
             {:mime_media_type, "document-format", "application/pdf"},
             {:text_without_language, "job-message", "hello ✓"},
             {:name_without_language, "job-name", ""},
             {:text_with_language, "x-text", {"fr", "bonjour"}},
             {:name_with_language, "x-name", {"de", "Hallo"}},
             {:octet_string, "x-octets", <<0, 255>>},
             {:uri_scheme, "x-scheme", "ipps"},
             {:range_of_integer, "page-ranges", 1..5},
             {:resolution, "printer-resolution", PrintResolution.new(600, 300, :dpi)},
             media_col
           ]) == %{
             "copies" => -2,
             "x-unregistered-enum" => 4,
             "ipp-attribute-fidelity" => true,
             "x-false" => false,
             "sides" => "two-sided-long-edge",
             "document-format" => "application/pdf",
             "job-message" => "hello ✓",
             "job-name" => "",
             "x-text" => {"fr", "bonjour"},
             "x-name" => {"de", "Hallo"},
             "x-octets" => <<0, 255>>,
             "x-scheme" => "ipps",
             # page-ranges is a set.
             "page-ranges" => [1..5],
             "printer-resolution" => PrintResolution.new(600, 300, :dpi),
             "media-col" => %{
               "media-size" => %{"x-dimension" => 21000, "y-dimension" => 29700},
               "media-type" => "stationery"
             }
           }
  end

  test "out-of-band values ignore the value" do
    assert round_trip([
             {:delete_attribute, "job-hold-until", nil},
             {:no_value, "job-name", "ignored"},
             {:not_settable, "printer-name", nil}
           ]) == %{
             "job-hold-until" => :delete_attribute,
             "job-name" => :no_value,
             "printer-name" => :not_settable
           }
  end

  test "URIs accept strings and URI structs" do
    assert %{"a" => %URI{host: "h"}, "b" => %URI{host: "h"}} =
             round_trip([{:uri, "a", "ipp://h/p"}, {:uri, "b", URI.parse("ipp://h/p")}])
  end

  test "date-times keep their time and offset" do
    {:ok, dt, _} = DateTime.from_iso8601("2026-10-29T13:45:07.300-04:00")
    %{"x-time" => decoded} = round_trip([{:datetime, "x-time", dt}])

    assert DateTime.compare(decoded, dt) == :eq
  end

  test "lists encode multi-valued attributes and members" do
    assert round_trip([
             {:keyword, "finishings-x", ["a", "b"]},
             {{:set1, :integer}, "x-ints", [1, 2, 3]},
             {:collection, "x-cols",
              [%{"m" => {:keyword, "1"}}, %{"m" => {:keyword, ["2", "3"]}}]}
           ]) == %{
             "finishings-x" => ["a", "b"],
             "x-ints" => [1, 2, 3],
             "x-cols" => [%{"m" => "1"}, %{"m" => ["2", "3"]}]
           }
  end

  test "values that can't be encoded raise" do
    for {attribute, message} <- [
          {{:integer, "copies", "2"}, ~s(cannot encode "2" as :integer for attribute "copies")},
          {{:keyword, "sides", :two_sided}, ~s(cannot encode :two_sided as :keyword)},
          {{:bogus, "x", "y"}, "unknown attribute syntax :bogus"},
          {{:keyword, :sides, "x"}, "invalid attribute"},
          {{:collection, "c", %{"m" => "x"}}, ~s(invalid value "x" for member "m")}
        ] do
      assert_raise ArgumentError, ~r/#{Regex.escape(message)}/, fn -> round_trip([attribute]) end
    end
  end
end
