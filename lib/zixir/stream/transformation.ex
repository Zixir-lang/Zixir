defmodule Zixir.Stream.Transformation do
  @moduledoc """
  Represents a stream transformation.
  
  Defines operations that can be applied to a stream:
  - map: Transform each element
  - filter: Keep only matching elements
  - batch: Group elements into batches
  - async: Process elements concurrently
  - buffer: Add backpressure buffering
  """
  
  defstruct [
    :source,           # Source stream or previous transformation
    :operation,        # :map, :filter, :batch, :async, :buffer
    :func,             # Transformation function
    :count,            # Number of elements to take
    :batch_size,       # Size for batch operations
    :max_concurrency,  # Max concurrent tasks for async
    :buffer_size,      # Buffer size for backpressure
    :opts              # Additional options
  ]
end
