defmodule Zixir.Python do
  @moduledoc """
  Unified Python integration for Zixir.

  This module provides a unified interface to Python, automatically selecting
  between:

  1. **Direct C API (NIF)** - 100-1000x faster when the NIF is available
  2. **Port-based** - Fallback when NIF is not available

  The NIF provides significant performance improvements for:
  - Function calls (no serialization overhead)
  - Large array operations (zero-copy transfers)
  - Repeated operations (cached module handles)

  ## Usage

      # All functions work transparently
      result = Zixir.Python.call("math", "sqrt", [16.0])
      # => {:ok, 4.0}

      # NumPy arrays are optimized
      arr = Zixir.Python.numpy_array([1.0, 2.0, 3.0])
      # => {:ok, %Zixir.Compiler.PythonNIF.Array{...}}

  ## Configuration

  To force port-based mode (bypass NIF):

      config :zixir, :python_mode, :port

  To prefer NIF (default):

      config :zixir, :python_mode, :nif
  """

  require Logger

  alias Zixir.Compiler.PythonNIF
  alias Zixir.Compiler.PythonFFI, as: PythonFFI

  @type mode :: :nif | :port | :auto

  @doc """
  Get the current Python integration mode.
  """
  def mode do
    Application.get_env(:zixir, :python_mode, :auto)
  end

  # Helper to route calls between NIF and Port modes with automatic fallback
  defp with_nif_fallback(port_fn, nif_fn) do
    case mode() do
      :port ->
        port_fn.()

      _ ->
        case nif_fn.() do
          {:error, :nif_not_loaded} -> port_fn.()
          result -> result
        end
    end
  end

  # Helper for functions that need special handling for reference handles
  defp with_nif_fallback_handle(handle, port_fn, nif_fn) do
    case mode() do
      :port ->
        port_fn.()

      _ when is_reference(handle) ->
        case nif_fn.() do
          {:error, :nif_not_loaded} -> port_fn.()
          result -> result
        end

      _ ->
        port_fn.()
    end
  end

  @doc """
  Check if the NIF is available and working.
  """
  def nif_available? do
    PythonNIF.available?()
  end

  @doc """
  Initialize Python integration.

  This is called automatically on first use, but can be called explicitly
  to control when initialization happens.
  """
  def init do
    case mode() do
      :port ->
        Zixir.Compiler.PythonFFI.init()

      :nif ->
        case PythonNIF.init() do
          {:ok, version} ->
            Logger.info("Python NIF initialized (version #{version})")
            {:ok, version}

          {:error, reason} ->
            Logger.warning("Python NIF not available (#{reason}), falling back to port mode")
            Zixir.Compiler.PythonFFI.init()
        end

      :auto ->
        case PythonNIF.init() do
          {:ok, version} ->
            Logger.info("Python NIF initialized (version #{version})")
            {:ok, version}

          {:error, _} ->
            Logger.info("Falling back to port-based Python")
            Zixir.Compiler.PythonFFI.init()
        end
    end
  end

  @doc """
  Finalize Python integration.
  """
  def finalize do
    PythonNIF.finalize()
    PythonFFI.finalize()
    :ok
  end

  @doc """
  Call a Python function.

  Automatically selects the fastest available method.
  """
  def call(module, function, args \\ [])
      when is_binary(module) and is_binary(function) and is_list(args) do
    with_nif_fallback(
      fn -> PythonFFI.call(module, function, args) end,
      fn -> PythonNIF.call(module, function, args) end
    )
  end

  @doc """
  Execute Python code.
  """
  def exec(code) when is_binary(code) do
    with_nif_fallback(
      fn -> PythonFFI.exec(code) end,
      fn -> PythonNIF.exec(code) end
    )
  end

  @doc """
  Check if a module is available.
  """
  def has_module?(module) when is_binary(module) do
    with_nif_fallback(
      fn -> PythonFFI.has_module?(module) end,
      fn -> PythonNIF.has_module?(module) end
    )
  end

  @doc """
  Create a NumPy array from a list.

  This is optimized for bulk data transfer.
  """
  def numpy_array(data) when is_list(data) do
    with_nif_fallback(
      fn -> PythonFFI.numpy_array(data) end,
      fn -> PythonNIF.numpy_array(data) end
    )
  end

  @doc """
  Import a module and return a handle for efficient repeated calls.
  """
  def import_module(module) when is_binary(module) do
    with_nif_fallback(
      fn -> {:ok, module} end,
      fn -> PythonNIF.import_module(module) end
    )
  end

  @doc """
  Call a function using a module handle.
  """
  def call_with_handle(handle, function, args)
      when is_binary(function) and is_list(args) do
    with_nif_fallback_handle(
      handle,
      fn -> PythonFFI.call(handle, function, args) end,
      fn -> PythonNIF.call_with_handle(handle, function, args) end
    )
  end

  @doc """
  Release a module handle.
  """
  def release_handle(handle) when is_reference(handle) do
    PythonNIF.release_handle(handle)
  end

  @doc """
  Get a string representation of a Python object.
  """
  def repr(value) do
    with_nif_fallback(
      fn -> PythonFFI.repr(value) end,
      fn -> PythonNIF.repr(value) end
    )
  end

  @doc """
  Get the type of a Python object.
  """
  def type(value) do
    with_nif_fallback(
      fn -> PythonFFI.type(value) end,
      fn -> PythonNIF.type(value) end
    )
  end

  @doc """
  Get a global variable from a module.
  """
  def get_global(module, name) when is_binary(module) and is_binary(name) do
    with_nif_fallback(
      fn -> PythonFFI.get_global(module, name) end,
      fn -> PythonNIF.get_global(module, name) end
    )
  end

  @doc """
  Set a global variable in a module.
  """
  def set_global(module, name, value) when is_binary(module) and is_binary(name) do
    with_nif_fallback(
      fn -> PythonFFI.set_global(module, name, value) end,
      fn -> PythonNIF.set_global(module, name, value) end
    )
  end

  @doc """
  Call a function from the math module.
  
  ## Examples
  
      iex> Zixir.Python.math("sqrt", [16.0])
      {:ok, 4.0}
  """
  def math(function, args) when is_binary(function) and is_list(args) do
    call("math", function, args)
  end

  @doc """
  Call a function from the numpy module.
  
  ## Examples
  
      iex> Zixir.Python.numpy("array", [[1, 2, 3]])
      {:ok, array}
  """
  def numpy(function, args) when is_binary(function) and is_list(args) do
    call("numpy", function, args)
  end

  @doc """
  Get Python pool statistics.
  
  Returns a map with pool health information.
  """
  def stats do
    Zixir.Python.Pool.stats()
  end

  @doc """
  Check if Python integration is healthy.
  
  Returns true if the Python pool has healthy workers available.
  """
  def healthy? do
    case stats() do
      %{healthy_workers: n} when n > 0 -> true
      _ -> false
    end
  end

  @doc """
  Execute multiple Python calls in parallel.
  
  ## Options
  
    * `:timeout` - Maximum time to wait for all calls (default: 30_000ms)
  
  ## Examples
  
      calls = [
        {"math", "sqrt", [1.0]},
        {"math", "sqrt", [4.0]},
        {"math", "sqrt", [9.0]}
      ]
      
      Zixir.Python.parallel(calls, timeout: 10_000)
  """
  def parallel(calls, opts \\ []) when is_list(calls) do
    Zixir.Python.Pool.parallel_calls(calls, opts)
  end
end
