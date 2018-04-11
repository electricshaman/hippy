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

  @defined_enums %{
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
    "finishings-supported" => Hippy.Protocol.Finishing
  }

  defp get_enum_module(attribute) do
    # TODO: convert to lookup from map.
    case attribute do
      "job-state" -> {:ok, Hippy.Protocol.JobState}
      "status-code" -> {:ok, Hippy.Protocol.StatusCode}
      "printer-state" -> {:ok, Hippy.Protocol.PrinterState}
      "printer-type" -> {:ok, Hippy.Protocol.PrinterType}
      "operations-supported" -> {:ok, Hippy.Protocol.Operation}
      "print-quality" -> {:ok, Hippy.Protocol.PrintQuality}
      "print-quality-default" -> {:ok, Hippy.Protocol.PrintQuality}
      "print-quality-supported" -> {:ok, Hippy.Protocol.PrintQuality}
      "finishings" -> {:ok, Hippy.Protocol.Finishing}
      "finishings-default" -> {:ok, Hippy.Protocol.Finishing}
      "finishings-supported" -> {:ok, Hippy.Protocol.Finishing}
      "orientation-requested" -> {:ok, Hippy.Protocol.Orientation}
      "orientation-requested-supported" -> {:ok, Hippy.Protocol.Orientation}
      _ -> :error
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
