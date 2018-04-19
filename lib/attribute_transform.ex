defmodule Hippy.AttributeTransform do
  @moduledoc """
  Functions for handling attribute transformations in an IPP response.
  """

  def handle_attribute({:enum, name, value}) do
    decoded = Hippy.Protocol.Enum.decode!(name, value)
    {:enum, name, decoded}
  end

  def handle_attribute({:boolean, name, value}) do
    {:boolean, name, to_boolean(value)}
  end

  def handle_attribute({:datetime, name, value}) do
    {:datetime, name, format_date(value)}
  end

  def handle_attribute({:resolution, name, {xf, f, u}}) do
    unit = Hippy.Protocol.ResolutionUnit.decode!(u)
    {:resolution, name, Hippy.PrintResolution.new(xf, f, unit)}
  end

  def handle_attribute({:range_of_integer, name, {l, u}}) do
    {:range_of_integer, name, Range.new(l, u)}
  end

  def handle_attribute({:uri, name, value}) do
    {:uri, name, URI.parse(value)}
  end

  def handle_attribute(other) do
    other
  end

  defp to_boolean(0), do: false
  defp to_boolean(1), do: true

  defp format_date(value) do
    {y, mo, d, h, min, s, ds, off_dir, off_h, off_min} = value

    date = "#{zpad2(y)}-#{zpad2(mo)}-#{zpad2(d)}"
    time = "T#{zpad2(h)}:#{zpad2(min)}:#{zpad2(s)}.#{ds}"
    offset = "#{off_dir}#{zpad2(off_h)}#{zpad2(off_min)}"

    case DateTime.from_iso8601("#{date}#{time}#{offset}") do
      {:ok, dt, _offset} -> dt
      error -> Tuple.append(error, value)
    end
  end

  defp zpad2(value) do
    to_string(value)
    |> String.pad_leading(2, "0")
  end
end
