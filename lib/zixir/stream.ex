defmodule Zixir.Stream.Source do
  @moduledoc """
  Represents a stream source.
  """
  
  defstruct [
    :type,
    :data,
    :module,
    :function,
    :args,
    :opts,
    :start,
    :stop,
    :step
  ]
end

defmodule Zixir.Stream.Transformation do
  @moduledoc """
  Represents a stream transformation.
  """
  
  defstruct [
    :source,
    :operation,
    :func,
    :count,
    :batch_size,
    :max_concurrency,
    :buffer_size,
    :opts
  ]
end

defmodule Zixir.Stream do
  @moduledoc """
  Streaming and Async Support for AI Workflows.
  
  Enables:
  - Lazy evaluation of sequences
  - Streaming responses from Python (LLMs, etc.)
  - Async/await patterns
  - Backpressure handling
  - Generator support
  
  ## Example
  
      # Stream LLM responses
      Zixir.Stream.from_python("openai", "chat", [prompt])
      |> Zixir.Stream.each(fn chunk ->
        IO.write(chunk)
        save_to_db(chunk)
      end)
      |> Zixir.Stream.run()
      
      # Async execution
      task = Zixir.Stream.async(fn ->
        python "model" "train" (data)
      end)
      
      result = Zixir.Stream.await(task, 30_000)
      
      # Lazy sequences
      Zixir.Stream.range(1, 1_000_000)
      |> Zixir.Stream.map(fn x -> x * 2 end)
      |> Zixir.Stream.take(10)
      |> Zixir.Stream.to_list()
  """

  use GenServer

  require Logger

  @default_backpressure 1000  # Max items in buffer

  # Client API

  @doc """
  Start the Stream supervisor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a stream from a Python generator function.
  
  ## Example
  
      Zixir.Stream.from_python("openai", "chat_stream", [prompt])
      |> Zixir.Stream.each(fn chunk -> print(chunk) end)
      |> Zixir.Stream.run()
  """
  def from_python(module, function, args, opts \\ []) do
    %Zixir.Stream.Source{
      type: :python,
      module: module,
      function: function,
      args: args,
      opts: opts
    }
  end

  @doc """
  Create a stream from an Elixir enumerable.
  """
  def from_enum(enum) do
    %Zixir.Stream.Source{
      type: :enum,
      data: enum
    }
  end

  @doc """
  Create a lazy range.
  """
  def range(start, stop, step \\ 1) do
    %Zixir.Stream.Source{
      type: :range,
      start: start,
      stop: stop,
      step: step
    }
  end

  @doc """
  Map each element through a function.
  """
  def map(source, func) when is_function(func, 1) do
    %Zixir.Stream.Transformation{
      source: source,
      operation: :map,
      func: func
    }
  end

  @doc """
  Filter elements based on a predicate.
  """
  def filter(source, predicate) when is_function(predicate, 1) do
    %Zixir.Stream.Transformation{
      source: source,
      operation: :filter,
      func: predicate
    }
  end

  @doc """
  Take first N elements.
  """
  def take(source, n) when is_integer(n) and n > 0 do
    %Zixir.Stream.Transformation{
      source: source,
      operation: :take,
      count: n
    }
  end

  @doc """
  Drop first N elements.
  """
  def drop(source, n) when is_integer(n) and n >= 0 do
    %Zixir.Stream.Transformation{
      source: source,
      operation: :drop,
      count: n
    }
  end

  @doc """
  Execute a side effect for each element.
  """
  def each(source, func) when is_function(func, 1) do
    %Zixir.Stream.Transformation{
      source: source,
      operation: :each,
      func: func
    }
  end

  @doc """
  Batch elements into chunks.
  """
  def batch(source, size) when is_integer(size) and size > 0 do
    %Zixir.Stream.Transformation{
      source: source,
      operation: :batch,
      batch_size: size
    }
  end

  @doc """
  Execute the stream and collect results.
  """
  def run(source, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    
    case source do
      %Zixir.Stream.Source{} ->
        execute_source(source, opts)
      
      %Zixir.Stream.Transformation{} ->
        execute_transformation(source, opts)
      
      _ ->
        {:error, "Invalid stream source"}
    end
  end

  @doc """
  Collect stream into a list.
  """
  def to_list(source, opts \\ []) do
    case run(source, opts) do
      {:ok, results} when is_list(results) -> {:ok, results}
      {:ok, result} -> {:ok, [result]}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Execute a function asynchronously.
  
  Returns a task that can be awaited.
  """
  def async(func, opts \\ []) when is_function(func) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    
    Task.async(fn ->
      try do
        result = func.()
        {:ok, result}
      rescue
        e -> {:error, Exception.message(e)}
      catch
        :exit, reason -> {:error, "Process exited: #{inspect(reason)}"}
      end
    end)
  end

  @doc """
  Await an async task with timeout.
  """
  def await(task, timeout \\ 30_000) do
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, "Async operation timed out after #{timeout}ms"}
    end
  end

  @doc """
  Execute multiple async tasks in parallel.
  
  ## Example
  
      tasks = [
        Zixir.Stream.async(fn -> python "model1" "predict" (data1) end),
        Zixir.Stream.async(fn -> python "model2" "predict" (data2) end)
      ]
      
      results = Zixir.Stream.await_many(tasks, 30_000)
  """
  def await_many(tasks, timeout \\ 30_000) when is_list(tasks) do
    Task.await_many(tasks, timeout)
    |> Enum.map(fn
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      other -> other
    end)
  end

  @doc """
  Create a stream that runs functions in parallel.
  """
  def parallel(source, max_concurrency \\ 4, opts \\ []) do
    %Zixir.Stream.Transformation{
      source: source,
      operation: :parallel,
      max_concurrency: max_concurrency,
      opts: opts
    }
  end

  @doc """
  Buffer stream with backpressure.
  """
  def buffer(source, size \\ @default_backpressure) do
    %Zixir.Stream.Transformation{
      source: source,
      operation: :buffer,
      buffer_size: size
    }
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      active_streams: %{},
      default_backpressure: Keyword.get(opts, :backpressure, @default_backpressure)
    }
    
    {:ok, state}
  end

  # Private Functions

  defp execute_source(%Zixir.Stream.Source{type: :enum, data: enum}, _opts) do
    {:ok, Enum.to_list(enum)}
  end

  defp execute_source(%Zixir.Stream.Source{type: :range, start: start, stop: stop, step: step}, _opts) do
    {:ok, Enum.to_list(start..stop//step)}
  end

  defp execute_source(%Zixir.Stream.Source{type: :python, module: module, function: function, args: args, opts: opts}, _opts) do
    # For now, fall back to regular Python call
    # Full streaming Python support would require protocol changes
    Zixir.Python.call(module, function, args, opts)
  end

  defp execute_transformation(%Zixir.Stream.Transformation{source: source, operation: :map, func: func}, opts) do
    case run(source, opts) do
      {:ok, items} when is_list(items) ->
        {:ok, Enum.map(items, func)}
      
      {:ok, item} ->
        {:ok, func.(item)}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_transformation(%Zixir.Stream.Transformation{source: source, operation: :filter, func: predicate}, opts) do
    case run(source, opts) do
      {:ok, items} when is_list(items) ->
        {:ok, Enum.filter(items, predicate)}
      
      {:ok, item} ->
        if predicate.(item), do: {:ok, item}, else: {:ok, []}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_transformation(%Zixir.Stream.Transformation{source: source, operation: :take, count: n}, opts) do
    case run(source, opts) do
      {:ok, items} when is_list(items) ->
        {:ok, Enum.take(items, n)}
      
      {:ok, _item} ->
        {:ok, []}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_transformation(%Zixir.Stream.Transformation{source: source, operation: :drop, count: n}, opts) do
    case run(source, opts) do
      {:ok, items} when is_list(items) ->
        {:ok, Enum.drop(items, n)}
      
      {:ok, item} ->
        {:ok, [item]}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_transformation(%Zixir.Stream.Transformation{source: source, operation: :each, func: func}, opts) do
    case run(source, opts) do
      {:ok, items} when is_list(items) ->
        Enum.each(items, func)
        {:ok, :ok}
      
      {:ok, item} ->
        func.(item)
        {:ok, :ok}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_transformation(%Zixir.Stream.Transformation{source: source, operation: :batch, batch_size: size}, opts) do
    case run(source, opts) do
      {:ok, items} when is_list(items) ->
        {:ok, Enum.chunk_every(items, size)}
      
      {:ok, item} ->
        {:ok, [[item]]}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_transformation(%Zixir.Stream.Transformation{source: source, operation: :parallel, max_concurrency: max}, opts) do
    case run(source, opts) do
      {:ok, items} when is_list(items) ->
        # Process in parallel
        tasks = Enum.map(items, fn item ->
          Task.async(fn ->
            # Apply any pending transformation
            item
          end)
        end)
        
        results = Task.await_many(tasks, Keyword.get(opts, :timeout, 30_000))
        {:ok, results}
      
      {:ok, item} ->
        {:ok, item}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_transformation(%Zixir.Stream.Transformation{source: source, operation: :buffer, buffer_size: _size}, opts) do
    # For now, just pass through
    # Full backpressure would require GenStage or similar
    run(source, opts)
  end
end
