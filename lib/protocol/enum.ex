defmodule Hippy.Protocol.Enum do
  defmacro __using__(map) do
    generate(map)
  end

  def generate(map) do
    quote bind_quoted: [map: map] do
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

      def decode(value) do
        case Map.fetch(@right, value) do
          {:ok, key} = ok -> ok
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

  defp get_enum_module(attribute) do
    %{
      "job-state" => Hippy.Protocol.JobState,
      "status-code" => Hippy.Protocol.StatusCode,
      "printer-state" => Hippy.Protocol.PrinterState,
      "printer-type" => Hippy.Protocol.PrinterType,
      "operations-supported" => Hippy.Protocol.Operation,
      "print-quality" => Hippy.Protocol.PrintQuality,
      "print-quality-default" => Hippy.Protocol.PrintQuality,
      "print-quality-supported" => Hippy.Protocol.PrintQuality,
      "finishings" => Hippy.Protocol.Finishing,
      "finishings-default" => Hippy.Protocol.Finishing,
      "finishings-supported" => Hippy.Protocol.Finishing,
      "orientation-requested" => Hippy.Protocol.Orientation,
      "orientation-requested-supported" => Hippy.Protocol.Orientation,
      "orientation-requested-default" => Hippy.Protocol.Orientation,
      "landscape-orientation-requested-preferred" => Hippy.Protocol.Orientation,
      "printer-wifi-state" => Hippy.Protocol.PrinterWifiState
    }
    |> Map.fetch(attribute)
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
