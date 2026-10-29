defmodule Hippy.Protocol.Enum do
  @moduledoc """
  Defines enums for IPP values, and decodes enum attributes in responses.

  Define an enum from a map of names to values:

      defmodule MyApp.VendorState do
        use Hippy.Protocol.Enum, %{
          idle: 0x01,
          busy: 0x02
        }
      end

  This generates a function per name (`MyApp.VendorState.busy()` returns `2`) along with
  `encode/1`, `encode!/1`, `decode/1` and `decode!/1`.

  ## Decoding attributes

  Enum attributes in a response are decoded using the module registered for the attribute
  name. Hippy registers modules for common attributes such as `job-state` and
  `orientation-requested`. Register more, or override the built-in ones, with:

      config :hippy, enums: %{
        "x-vendor-state" => MyApp.VendorState,
        "input-orientation-requested" => Hippy.Protocol.Orientation
      }

  When `xxx-default` or `xxx-supported` has no module registered, the module for `xxx` is
  used. Values without a registered module, or not found in the enum, are left as integers.

  A registered module doesn't have to use this macro, as long as it implements this
  behaviour (see `Hippy.Protocol.PrinterType` for an example).
  """

  @doc "Decodes an enum value received from a printer."
  @callback decode(value :: integer()) :: {:ok, term()} | {:error, term()}

  defmacro __using__(map) do
    generate(map)
  end

  def generate(map) do
    quote bind_quoted: [map: map] do
      @behaviour Hippy.Protocol.Enum

      @left map
      @right map |> Enum.map(fn {k, v} -> {v, k} end) |> Map.new()
      @keys Map.keys(map)
      @values Map.values(map)

      def map do
        @left
      end

      for {k, v} <- @left do
        def unquote(k)() do
          unquote(v)
        end
      end

      def encode!(key) do
        case encode(key) do
          {:ok, value} -> value
          {:error, _} -> raise KeyError, key: key
        end
      end

      def encode(key) do
        if Map.has_key?(@left, key) do
          {:ok, apply(__MODULE__, key, [])}
        else
          {:error, :bad_key}
        end
      end

      def decode!(value) do
        case decode(value) do
          {:ok, key} -> key
          {:error, _} -> raise Hippy.ValueError, value: value
        end
      end

      @impl Hippy.Protocol.Enum
      def decode(value) do
        case Map.fetch(@right, value) do
          {:ok, _key} = ok -> ok
          :error -> {:error, :bad_value}
        end
      end
    end
  end

  def decode!(attribute, value) do
    case get_enum_module(attribute) do
      {:ok, mod} ->
        mod.decode!(value)

      :error ->
        raise Hippy.EnumError, name: attribute
    end
  end

  def decode(attribute, value) do
    case get_enum_module(attribute) do
      {:ok, mod} ->
        mod.decode(value)

      :error ->
        {:error, {:enum_not_defined, attribute, value}}
    end
  end

  @builtin_enums %{
    "job-state" => Hippy.Protocol.JobState,
    "status-code" => Hippy.Protocol.StatusCode,
    "printer-state" => Hippy.Protocol.PrinterState,
    "printer-type" => Hippy.Protocol.PrinterType,
    "operations-supported" => Hippy.Protocol.Operation,
    "print-quality" => Hippy.Protocol.PrintQuality,
    "finishings" => Hippy.Protocol.Finishing,
    "finishings-ready" => Hippy.Protocol.Finishing,
    "orientation-requested" => Hippy.Protocol.Orientation,
    "landscape-orientation-requested-preferred" => Hippy.Protocol.Orientation,
    "printer-wifi-state" => Hippy.Protocol.PrinterWifiState
  }

  defp get_enum_module(attribute) do
    enums = Map.merge(@builtin_enums, Application.get_env(:hippy, :enums, %{}))

    with :error <- Map.fetch(enums, attribute) do
      # xxx-default and xxx-supported take values of the same enum as xxx.
      case Regex.run(~r/^(.+)-(default|supported)$/, attribute) do
        [_, base, _] -> Map.fetch(enums, base)
        nil -> :error
      end
    end
  end
end

defmodule Hippy.ValueError do
  defexception [:value]

  def message(exception) do
    "value #{inspect(exception.value)} not found in enum"
  end
end

defmodule Hippy.EnumError do
  defexception [:name]

  def message(exception) do
    "enum not defined for attribute with name #{inspect(exception.name)}"
  end
end
