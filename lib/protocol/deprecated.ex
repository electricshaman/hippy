defmodule Hippy.Protocol.Deprecated do
  @moduledoc false

  # Defines a module that delegates every function to its replacement in Hippy.IPP, marking
  # each one deprecated so callers get a compile-time warning naming the new function.
  defmacro __using__(to) do
    to = Macro.expand(to, __CALLER__)
    Code.ensure_compiled!(to)

    for {name, arity} <- to.__info__(:functions) do
      args = Macro.generate_arguments(arity, __MODULE__)

      quote do
        @deprecated unquote("Use #{inspect(to)}.#{name}/#{arity} instead")
        defdelegate unquote(name)(unquote_splicing(args)), to: unquote(to)
      end
    end
  end
end

defmodule Hippy.Protocol.Enum do
  @moduledoc false

  # Still usable with `use` and as a behaviour, as documented in 0.4.1.
  @callback decode(value :: integer()) :: {:ok, term()} | {:error, term()}

  defmacro __using__(map) do
    IO.warn(
      "use Hippy.Protocol.Enum is deprecated, use Hippy.IPP.Enum instead",
      Macro.Env.stacktrace(__CALLER__)
    )

    Hippy.IPP.Enum.generate(map)
  end

  use Hippy.Protocol.Deprecated, Hippy.IPP.Enum
end

defmodule Hippy.Protocol.DelimiterTag do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.DelimiterTag
end

defmodule Hippy.Protocol.Finishing do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.Finishing
end

defmodule Hippy.Protocol.JobState do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.JobState
end

defmodule Hippy.Protocol.Operation do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.Operation
end

defmodule Hippy.Protocol.Orientation do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.Orientation
end

defmodule Hippy.Protocol.PrintQuality do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.PrintQuality
end

defmodule Hippy.Protocol.PrinterState do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.PrinterState
end

defmodule Hippy.Protocol.PrinterType do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.PrinterType
end

defmodule Hippy.Protocol.PrinterWifiState do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.PrinterWifiState
end

defmodule Hippy.Protocol.ResolutionUnit do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.ResolutionUnit
end

defmodule Hippy.Protocol.StatusCode do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.StatusCode
end

defmodule Hippy.Protocol.ValueTag do
  @moduledoc false
  use Hippy.Protocol.Deprecated, Hippy.IPP.ValueTag
end
