defmodule Zixir.Errors do
  @moduledoc """
  Standardized error messages for Zixir.

  Provides consistent error formatting across the codebase, making errors
  easier to understand, maintain, and potentially internationalize in the future.

  ## Examples

      # Not found errors
      Zixir.Errors.not_found(:compiler, "zig")
      # => {:error, "Compiler not found: zig"}

      # Compilation errors
      Zixir.Errors.compilation_failed("CUDA", "out of memory")
      # => {:error, "CUDA compilation failed: out of memory"}

      # Timeout errors
      Zixir.Errors.timeout("module resolution", 30_000)
      # => {:error, "Module resolution timed out after 30000ms"}

      # File errors
      Zixir.Errors.file_not_found("/path/to/file.zr")
      # => {:error, "File not found: /path/to/file.zr"}
  """

  @doc """
  Standard "not found" error.

  ## Examples

      iex> Zixir.Errors.not_found(:compiler, "zig")
      {:error, "Compiler not found: zig"}

      iex> Zixir.Errors.not_found(:module, "MyModule")
      {:error, "Module not found: MyModule"}
  """
  @spec not_found(atom() | String.t(), String.t()) :: {:error, String.t()}
  def not_found(type, name) do
    type_str = format_type(type)
    {:error, "#{type_str} not found: #{name}"}
  end

  @doc """
  Standard "not found with help" error.

  ## Examples

      iex> Zixir.Errors.not_found_with_help(:compiler, "zig", "Run 'mix zig.get'")
      {:error, "Compiler not found: zig. Run 'mix zig.get'"}
  """
  @spec not_found_with_help(atom() | String.t(), String.t(), String.t()) :: {:error, String.t()}
  def not_found_with_help(type, name, help_text) do
    type_str = format_type(type)
    {:error, "#{type_str} not found: #{name}. #{help_text}"}
  end

  @doc """
  Standard compilation failure error.

  ## Examples

      iex> Zixir.Errors.compilation_failed("Zig", "syntax error")
      {:error, "Zig compilation failed: syntax error"}

      iex> Zixir.Errors.compilation_failed("CUDA", "out of memory")
      {:error, "CUDA compilation failed: out of memory"}
  """
  @spec compilation_failed(String.t(), String.t()) :: {:error, String.t()}
  def compilation_failed(tool, reason) do
    {:error, "#{tool} compilation failed: #{reason}"}
  end

  @doc """
  Standard compilation failure with exit code.

  ## Examples

      iex> Zixir.Errors.compilation_failed_with_code("Zig", 1, "error output")
      {:error, "Zig compilation failed (exit 1): error output"}
  """
  @spec compilation_failed_with_code(String.t(), integer(), String.t()) :: {:error, String.t()}
  def compilation_failed_with_code(tool, exit_code, output) do
    {:error, "#{tool} compilation failed (exit #{exit_code}): #{output}"}
  end

  @doc """
  Standard timeout error.

  ## Examples

      iex> Zixir.Errors.timeout("operation", 30_000)
      {:error, "Operation timed out after 30000ms"}
  """
  @spec timeout(atom() | String.t(), integer()) :: {:error, String.t()}
  def timeout(operation, duration_ms) do
    operation_str = format_operation(operation)
    {:error, "#{operation_str} timed out after #{duration_ms}ms"}
  end

  @doc """
  Standard file not found error.

  ## Examples

      iex> Zixir.Errors.file_not_found("/path/to/file.zr")
      {:error, "File not found: /path/to/file.zr"}
  """
  @spec file_not_found(String.t()) :: {:error, String.t()}
  def file_not_found(path) do
    {:error, "File not found: #{path}"}
  end

  @doc """
  Standard file not found with search paths.

  ## Examples

      iex> Zixir.Errors.file_not_found_in_paths("MyModule", ["lib/", "src/"])
      {:error, "Module not found in search paths: MyModule"}
  """
  @spec file_not_found_in_paths(String.t(), list(String.t())) :: {:error, String.t()}
  def file_not_found_in_paths(name, _paths) do
    {:error, "Module not found in search paths: #{name}"}
  end

  @doc """
  Standard execution failure error.

  ## Examples

      iex> Zixir.Errors.execution_failed("Python", "module not found")
      {:error, "Python execution failed: module not found"}
  """
  @spec execution_failed(String.t(), String.t()) :: {:error, String.t()}
  def execution_failed(system, reason) do
    {:error, "#{system} execution failed: #{reason}"}
  end

  @doc """
  Standard device/info query failure.

  ## Examples

      iex> Zixir.Errors.device_info_failed("GPU")
      {:error, "GPU device info failed"}
  """
  @spec device_info_failed(String.t()) :: {:error, String.t()}
  def device_info_failed(device_type) do
    {:error, "#{device_type} device info failed"}
  end

  @doc """
  Standard code generation failure.

  ## Examples

      iex> Zixir.Errors.code_generation_failed("invalid AST")
      {:error, "Code generation failed: invalid AST"}
  """
  @spec code_generation_failed(String.t()) :: {:error, String.t()}
  def code_generation_failed(reason) do
    {:error, "Code generation failed: #{reason}"}
  end

  @doc """
  Standard validation failure with multiple errors.

  ## Examples

      iex> Zixir.Errors.validation_failed(["error1", "error2"])
      {:error, "Validation failed: error1, error2"}
  """
  @spec validation_failed(list(String.t())) :: {:error, String.t()}
  def validation_failed(errors) when is_list(errors) do
    {:error, "Validation failed: #{Enum.join(errors, ", ")}"}
  end

  @doc """
  Standard JIT compilation failure.

  ## Examples

      iex> Zixir.Errors.jit_compilation_failed("linker error")
      {:error, "JIT compilation failed: linker error"}
  """
  @spec jit_compilation_failed(String.t()) :: {:error, String.t()}
  def jit_compilation_failed(reason) do
    {:error, "JIT compilation failed: #{reason}"}
  end

  @doc """
  Standard external command failure.

  ## Examples

      iex> Zixir.Errors.external_command_failed("git", "clone failed")
      {:error, "Git command failed: clone failed"}
  """
  @spec external_command_failed(atom() | String.t(), String.t()) :: {:error, String.t()}
  def external_command_failed(command, reason) do
    command_str = String.capitalize(to_string(command))
    {:error, "#{command_str} command failed: #{reason}"}
  end

  @doc """
  Standard Python call failure.

  ## Examples

      iex> Zixir.Errors.python_call_failed()
      {:error, "Python call failed"}
  """
  @spec python_call_failed() :: {:error, String.t()}
  def python_call_failed do
    {:error, "Python call failed"}
  end

  @doc """
  Standard protocol decode failure.

  ## Examples

      iex> Zixir.Errors.decode_failed()
      {:error, "Protocol decode failed"}
  """
  @spec decode_failed() :: {:error, String.t()}
  def decode_failed do
    {:error, "Protocol decode failed"}
  end

  # Helper functions for formatting

  defp format_type(type) when is_atom(type) do
    type
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_type(type) when is_binary(type) do
    String.capitalize(type)
  end

  defp format_operation(operation) when is_atom(operation) do
    operation
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_operation(operation) when is_binary(operation) do
    String.capitalize(operation)
  end
end
