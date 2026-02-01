defmodule Zixir.Compiler.PythonFFI do
  @moduledoc """
  Python FFI integration for Zixir.
  
  Provides access to Python ecosystem (NumPy, PyTorch, pandas, etc.)
  via port-based communication with Python process.
  
  ## Features
  - Python 3.10-3.12 support
  - NumPy array support  
  - Automatic module/function resolution
  - JSON-based data exchange
  
  ## Usage
  
      # Call Python function
      python "numpy" "array"([[1, 2], [3, 4]])
      
      # Or via FFI module directly
      Zixir.Compiler.PythonFFI.call("math", "sqrt", [16.0])
      # => {:ok, 4.0}
  """

  require Logger

  @doc """
  Initialize Python interpreter via port.
  Returns {:ok, version} on success, {:error, reason} on failure.
  
  ## Examples
  
      Zixir.Compiler.PythonFFI.init()
      # => {:ok, "3.11"} or {:error, :not_available}
  """
  def init do
    case System.find_executable("python3") do
      nil ->
        # Try python as fallback
        case System.find_executable("python") do
          nil -> {:error, :not_available}
          path -> {:ok, detect_python_version(path)}
        end
      
      path ->
        {:ok, detect_python_version(path)}
    end
  end

  defp detect_python_version(path) do
    case System.cmd(path, ["--version"], []) do
      {output, 0} ->
        # Parse "Python 3.11.5" -> "3.11"
        case Regex.run(~r/Python (\d+\.\d+)/, output) do
          [_, version] -> version
          _ -> "unknown"
        end
      
      _ ->
        "unknown"
    end
  end

  @doc """
  Check if Python is available.
  """
  def available? do
    System.find_executable("python3") != nil or System.find_executable("python") != nil
  end

  @doc """
  Get Python version string.
  """
  def version do
    case System.find_executable("python3") do
      nil ->
        case System.find_executable("python") do
          nil -> {:error, :not_available}
          path -> {:ok, detect_python_version(path)}
        end
      
      path ->
        {:ok, detect_python_version(path)}
    end
  end

  @doc """
  Check if a Python module is available.
  
  ## Examples
  
      Zixir.Compiler.PythonFFI.has_module?("numpy")
      # => true
  """
  def has_module?(name) when is_binary(name) do
    python_cmd = get_python_cmd()
    
    case System.cmd(python_cmd, ["-c", "import #{name}; print('ok')"], []) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Call a Python function with arguments.
  
  ## Examples
  
      Zixir.Compiler.PythonFFI.call("math", "sqrt", [16.0])
      # => {:ok, 4.0}
      
      Zixir.Compiler.PythonFFI.call("numpy", "array", [[1, 2], [3, 4]])
      # => {:ok, [[1, 2], [3, 4]]}
  """
  def call(module, function, args) when is_binary(module) and is_binary(function) and is_list(args) do
    python_cmd = get_python_cmd()
    
    # Build Python code to execute
    code = build_python_call(module, function, args)
    
    case System.cmd(python_cmd, ["-c", code], []) do
      {output, 0} ->
        parse_result(output)
      
      {error_output, _} ->
        Logger.debug("Python call failed: #{error_output}")
        Zixir.Errors.python_call_failed()
    end
  end

  @doc """
  Create a NumPy array from a list of numbers.
  
  ## Examples
  
      Zixir.Compiler.PythonFFI.numpy_array([1.0, 2.0, 3.0, 4.0])
      # => {:ok, [[1.0, 2.0, 3.0, 4.0]]}
  """
  def numpy_array(data) when is_list(data) do
    python_cmd = get_python_cmd()
    
    # Convert Elixir list to Python list and create NumPy array
    python_list = Jason.encode!(data)
    code = """
    import json, numpy as np
    data = json.loads('#{python_list}')
    arr = np.array(data)
    print(json.dumps(arr.tolist()))
    """
    
    case System.cmd(python_cmd, ["-c", code], []) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:ok, output}
        end
      
      {error_output, _} ->
        Logger.debug("NumPy creation failed: #{error_output}")
        {:error, :numpy_not_available}
    end
  end

  @doc """
  Get a reference to a NumPy array (for passing to other Python functions).
  """
  def get_numpy_array_ref(data) when is_list(data) do
    {:numpy_array, data}
  end

  @doc """
  Execute arbitrary Python code.
  
  ## Examples
  
      Zixir.Compiler.PythonFFI.exec("import numpy as np; x = np.array([1,2,3])")
      # => {:ok, ""}
  """
  def exec(code) when is_binary(code) do
    python_cmd = get_python_cmd()
    
    case System.cmd(python_cmd, ["-c", code], []) do
      {output, 0} -> {:ok, String.trim(output)}
      {error_output, _} -> {:error, String.trim(error_output)}
    end
  end

  @doc """
  Import and return a Python module.
  """
  def import_module(name) when is_binary(name) do
    exec("import #{name}; print(#{name}.__doc__)")
  end

  @doc """
  Cleanup (no-op for port-based approach).
  """
  def finalize do
    :ok
  end

  # Private functions

  defp get_python_cmd do
    System.find_executable("python3") || System.find_executable("python") || "python3"
  end

  defp build_python_call(module, function, args) do
    # Build Python code that imports module, calls function, and prints result as JSON
    args_json = Jason.encode!(args)
    
    """
    import json, sys
    #{module} = __import__('#{module}')
    func = getattr(#{module}, '#{function}', None)
    args = json.loads('#{args_json}')
    result = func(*args) if args else func()
    if isinstance(result, (list, tuple)):
        print(json.dumps(list(result)))
    elif isinstance(result, dict):
        print(json.dumps(result))
    else:
        print(result)
    """
  end

  defp parse_result(output) do
    trimmed = String.trim(output)
    
    case Jason.decode(trimmed) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} ->
        # Try to parse as number
        case Float.parse(trimmed) do
          {n, ""} -> {:ok, n}
          {n, _} -> {:ok, n}
          :error ->
            case Integer.parse(trimmed) do
              {n, ""} -> {:ok, n}
              _ -> {:ok, trimmed}
            end
        end
    end
  end
end
