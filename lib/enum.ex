defmodule Hippy.Enum do
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
end

defmodule Hippy.ValueError do
  defexception [:value]

  def message(exception) do
    "value #{inspect(exception.value)} not found"
  end
end
