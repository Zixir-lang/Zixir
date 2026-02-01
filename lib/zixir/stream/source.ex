defmodule Zixir.Stream.Source do
  @moduledoc """
  Represents a stream source.
  
  Defines the origin of a data stream, which can be:
  - A Python function call
  - A generator function
  - An enumerable collection
  - A range of values
  """
  
  defstruct [
    :type,        # :python, :generator, :enum, :range
    :data,        # For :enum type
    :module,      # For :python type
    :function,    # For :python type
    :args,        # For :python type
    :opts,        # Additional options
    :start,       # For :range type
    :stop,        # For :range type
    :step         # For :range type
  ]
end
