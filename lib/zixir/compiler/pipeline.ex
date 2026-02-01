defmodule Zixir.Compiler.Pipeline do
  @moduledoc """
  Phase 1: Main compilation pipeline.
  
  Orchestrates the full compilation process:
  Zixir Source → Parse → Generate Zig → Compile with Zig → Binary
  """

  require Logger

  @doc """
  Compile a Zixir source file to an executable binary.
  
  ## Options
    * `:output` - Output path for binary (default: derived from input)
    * `:optimize` - Optimization level: :debug, :release_safe, :release_fast (default: :release_fast)
    * `:target` - Target triple (default: native)
    * `:verbose` - Print compilation steps (default: false)
  
  ## Examples
      Zixir.Compiler.Pipeline.compile_file("main.zr")
      Zixir.Compiler.Pipeline.compile_file("main.zr", optimize: :release_fast, verbose: true)
  """
  def compile_file(source_path, opts \\ []) do
    output_path = opts[:output] || derive_output_path(source_path)
    optimize = opts[:optimize] || :release_fast
    verbose = opts[:verbose] || false
    
    log(verbose, "Compiling #{source_path}...")
    
    with {:ok, source} <- read_source(source_path),
         {:ok, ast} <- parse_source(source, source_path),
         {:ok, zig_code} <- generate_zig(ast),
         {:ok, zig_file} <- write_zig_file(zig_code, source_path),
         {:ok, binary} <- compile_zig(zig_file, output_path, optimize, verbose),
         :ok <- File.rm(zig_file) do
      log(verbose, "Successfully compiled to #{output_path}")
      {:ok, binary}
    else
      {:error, reason} = err ->
        Logger.error("Compilation failed: #{inspect(reason)}")
        err
    end
  end

  @doc """
  Compile Zixir source string to Zig code (without full binary compilation).
  Useful for debugging and IDE support.
  """
  def compile_string(source, opts \\ []) do
    with {:ok, ast} <- parse_source(source, "<string>"),
         {:ok, zig_code} <- generate_zig(ast, opts) do
      {:ok, zig_code}
    end
  end

  @doc """
  JIT compile and run Zixir source.
  """
  def run_string(source, args \\ [], opts \\ []) do
    verbose = opts[:verbose] || false
    
    with {:ok, ast} <- parse_source(source, "<string>"),
         {:ok, zig_code} <- generate_zig(ast, opts),
         {:ok, binary_path} <- jit_compile(zig_code, verbose),
         {:ok, result} <- execute_binary(binary_path, args, verbose) do
      # Cleanup
      File.rm(binary_path)
      File.rm(binary_path <> ".zig")
      
      {:ok, result}
    end
  end

  # Private functions

  defp read_source(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "Failed to read #{path}: #{reason}"}
    end
  end

  defp parse_source(source, filename) do
    case Zixir.Compiler.Parser.parse(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, error} -> 
        {:error, "Parse error in #{filename} at line #{error.line}: #{error.message}"}
    end
  end

  defp generate_zig(ast, _opts \\ []) do
    case Zixir.Compiler.ZigBackend.compile(ast) do
      {:ok, code} -> {:ok, code}
      {:error, reason} -> Zixir.Errors.code_generation_failed(reason)
    end
  end

  defp write_zig_file(zig_code, source_path) do
    zig_path = source_path <> ".zig"
    
    # Add runtime header
    full_code = add_runtime_preamble(zig_code)
    
    case File.write(zig_path, full_code) do
      :ok -> {:ok, zig_path}
      {:error, reason} -> {:error, "Failed to write #{zig_path}: #{reason}"}
    end
  end

  defp compile_zig(zig_file, output_path, optimize, verbose) do
    zig_exe = find_zig_executable()
    
    if is_nil(zig_exe) do
      Zixir.Errors.not_found_with_help(:compiler, "zig", "Run 'mix zig.get' first.")
    else
      mode_flag = case optimize do
        :debug -> "-ODebug"
        :release_safe -> "-OReleaseSafe"
        :release_fast -> "-OReleaseFast"
        _ -> "-OReleaseFast"
      end
      
      cmd = "#{zig_exe} build-exe #{mode_flag} -femit-bin=#{output_path} #{zig_file}"
      log(verbose, "Running: #{cmd}")
      
      case System.cmd("cmd", ["/c", cmd], stderr_to_stdout: true) do
        {_, 0} -> {:ok, output_path}
        {output, code} -> 
          Zixir.Errors.compilation_failed_with_code("Zig", code, output)
      end
    end
  end

  defp jit_compile(zig_code, verbose) do
    # Create temp files
    temp_base = Path.join(System.tmp_dir!(), "zixir_jit_#{:erlang.unique_integer([:positive])}")
    zig_file = temp_base <> ".zig"
    binary = temp_base <> if(:os.type() == {:win32, :nt}, do: ".exe", else: "")
    
    full_code = add_runtime_preamble(zig_code)
    File.write!(zig_file, full_code)
    
    zig_exe = find_zig_executable()
    
    if is_nil(zig_exe) do
      Zixir.Errors.not_found(:compiler, "zig")
    else
      cmd = "#{zig_exe} build-exe -OReleaseFast -femit-bin=#{binary} #{zig_file}"
      log(verbose, "JIT compiling...")
      
      case System.cmd("cmd", ["/c", cmd], stderr_to_stdout: true) do
        {_, 0} -> {:ok, binary}
        {output, _code} -> Zixir.Errors.jit_compilation_failed(output)
      end
    end
  end

  defp execute_binary(binary_path, args, verbose) do
    log(verbose, "Running #{binary_path}...")
    
    case System.cmd(binary_path, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _code} -> {:ok, output}  # Non-zero exit still returns output
    end
  end

  defp find_zig_executable do
    # Check for zigler's cached zig first
    zigler_zig = Path.join([Application.app_dir(:zigler), "..", "..", "zig", "zig"])
    
    cond do
      File.exists?(zigler_zig) -> zigler_zig
      System.find_executable("zig") -> "zig"
      true -> nil
    end
  end

  defp derive_output_path(source_path) do
    base = Path.basename(source_path, ".zr")
    base = Path.basename(base, ".zixir")
    base <> if(:os.type() == {:win32, :nt}, do: ".exe", else: "")
  end

  defp add_runtime_preamble(zig_code) do
    _runtime_path = Path.join([Application.app_dir(:zixir), "priv", "zig", "zixir_runtime.zig"])
    
    preamble = """
    // Zixir Runtime Preamble
    const std = @import("std");
    
    // Import runtime if available
    const zixir = if (@hasDecl(@import("root"), "zixir_runtime"))
      @import("root").zixir_runtime
    else
      struct {
        pub fn print(msg: []const u8) void {
          std.debug.print("{s}", .{msg});
        }
        
        pub fn println(msg: []const u8) void {
          std.debug.print("{s}\n", .{msg});
        }
      };
    
    """
    
    preamble <> zig_code
  end

  defp log(false, _msg), do: :ok
  defp log(true, msg) do
    IO.puts("[Zixir] #{msg}")
  end
end
