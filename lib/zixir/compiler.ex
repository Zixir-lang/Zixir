defmodule Zixir.Compiler do
  @moduledoc """
  Main entry point for the Zixir Compiler (All 5 Phases).
  
  Orchestrates the complete compilation pipeline:
  1. Parse → 2. Type Inference → 3. MLIR Optimize → 4. GPU Analyze → 5. Code Gen
  
  Supports multiple backends:
  - Native (Zig → Binary)
  - GPU (CUDA/ROCm)
  - JIT execution
  """

  require Logger

  # Zig optimization mode flags
  @zig_mode_debug "-ODebug"
  @zig_mode_safe "-OReleaseSafe"
  @zig_mode_fast "-OReleaseFast"

  @doc """
  Compile Zixir source with all optimizations enabled.
  
  ## Pipeline
  1. Parse source to AST (Phase 1)
  2. Infer and check types (Phase 3)
  3. Optimize with MLIR (Phase 4)
  4. Analyze for GPU offloading (Phase 5)
  5. Generate code (Zig or GPU)
  
  ## Options
    * `:target` - :native, :cuda, :rocm (default: :native)
    * `:optimize` - :debug, :safe, :fast (default: :fast)
    * `:gpu` - Enable GPU acceleration if available (default: true)
    * `:mlir` - Enable MLIR optimization (default: true)
    * `:verbose` - Show compilation steps (default: false)
  """
  def compile(source, opts \\ [])
  
  def compile(source, opts) when is_binary(source) do
    verbose = opts[:verbose] || false
    
    log(verbose, "Starting Zixir compilation pipeline...")
    
    with {:ok, ast} <- phase1_parse(source, verbose),
         {:ok, typed_ast} <- phase3_typecheck(ast, verbose),
         {:ok, optimized_ast} <- phase4_optimize(typed_ast, opts, verbose),
         {:ok, gpu_plan} <- phase5_gpu_analyze(optimized_ast, opts, verbose),
         {:ok, result} <- codegen(optimized_ast, gpu_plan, opts, verbose) do
      log(verbose, "Compilation complete!")
      {:ok, result}
    else
      {:error, reason} = err ->
        Logger.error("Compilation failed: #{inspect(reason)}")
        err
    end
  end
  
  def compile({:program, _} = ast, opts) do
    verbose = opts[:verbose] || false
    
    log(verbose, "Starting Zixir compilation pipeline from AST...")
    
    with {:ok, typed_ast} <- phase3_typecheck(ast, verbose),
         {:ok, optimized_ast} <- phase4_optimize(typed_ast, opts, verbose),
         {:ok, gpu_plan} <- phase5_gpu_analyze(optimized_ast, opts, verbose),
         {:ok, result} <- codegen(optimized_ast, gpu_plan, opts, verbose) do
      log(verbose, "Compilation complete!")
      {:ok, result}
    else
      {:error, reason} = err ->
        Logger.error("Compilation failed: #{inspect(reason)}")
        err
    end
  end

  @doc """
  Compile a Zixir file to binary.
  """
  def compile_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, source} ->
        output = opts[:output] || derive_output_path(path)
        compile(source, Keyword.put(opts, :output, output))
      
      {:error, reason} ->
        {:error, "Cannot read file #{path}: #{reason}"}
    end
  end

  @doc """
  JIT compile and execute Zixir source.
  """
  def run(source, args \\ [], opts \\ []) when is_binary(source) do
    verbose = opts[:verbose] || false
    
    log(verbose, "JIT compiling...")
    
    with {:ok, _zig_code} <- compile_to_zig(source, opts) do
      Zixir.Compiler.Pipeline.run_string(source, args, opts)
    end
  end

  @doc """
  Compile Zixir source to Zig code (for inspection/debugging).
  """
  def compile_to_zig(source, _opts \\ []) when is_binary(source) do
    with {:ok, ast} <- phase1_parse(source, false),
         {:ok, typed_ast} <- phase3_typecheck(ast, false),
         {:ok, zig_code} <- Zixir.Compiler.ZigBackend.compile(typed_ast) do
      {:ok, zig_code}
    end
  end

  @doc """
  Type check Zixir source without compiling.
  """
  def typecheck(source) when is_binary(source) do
    with {:ok, ast} <- phase1_parse(source, false) do
      Zixir.Compiler.TypeSystem.infer(ast)
    end
  end

  @doc """
  Analyze source for GPU acceleration opportunities.
  """
  def gpu_analyze(source) when is_binary(source) do
    with {:ok, ast} <- phase1_parse(source, false),
         {:ok, typed_ast} <- phase3_typecheck(ast, false) do
      candidates = Zixir.Compiler.GPU.analyze(typed_ast)
      speedup = Zixir.Compiler.GPU.estimate_speedup(typed_ast)
      
      {:ok, %{candidates: candidates, speedup_estimate: speedup}}
    end
  end

  # Phase implementations

  defp phase1_parse(source, verbose) do
    log(verbose, "Phase 1: Parsing...")
    
    case Zixir.Compiler.Parser.parse(source) do
      {:ok, ast} ->
        log(verbose, "  ✓ Parsed successfully")
        {:ok, ast}
      
      {:error, error} ->
        {:error, "Parse error at line #{error.line}: #{error.message}"}
    end
  end

  defp phase3_typecheck(ast, verbose) do
    log(verbose, "Phase 3: Type inference and checking...")
    
    case Zixir.Compiler.TypeSystem.infer(ast) do
      {:ok, typed_ast} ->
        log(verbose, "  ✓ Type checking passed")
        {:ok, typed_ast}
      
      {:error, error} ->
        {:error, "Type error: #{error.message}"}
    end
  end

  defp phase4_optimize(ast, opts, verbose) do
    if opts[:mlir] != false and Zixir.Compiler.MLIR.available?() do
      log(verbose, "Phase 4: MLIR optimization...")
      
      # MLIR.optimize always returns {:ok, _} even when Beaver is unavailable
      {:ok, optimized} = Zixir.Compiler.MLIR.optimize(ast, passes: [:canonicalize, :cse, :vectorize])
      log(verbose, "  ✓ MLIR optimization complete")
      {:ok, optimized}
    else
      log(verbose, "Phase 4: MLIR optimization (skipped)")
      {:ok, ast}
    end
  end

  defp phase5_gpu_analyze(ast, opts, verbose) do
    if opts[:gpu] != false and Zixir.Compiler.GPU.available?() do
      log(verbose, "Phase 5: GPU analysis...")
      
      candidates = Zixir.Compiler.GPU.analyze(ast)
      {:ok, speedup, count} = Zixir.Compiler.GPU.estimate_speedup(ast)
      
      log(verbose, "  ✓ Found #{count} GPU candidates (estimated #{Float.round(speedup, 1)}x speedup)")
      
      {:ok, %{candidates: candidates, speedup: speedup}}
    else
      log(verbose, "Phase 5: GPU analysis (skipped)")
      {:ok, %{candidates: [], speedup: 1.0}}
    end
  end

  defp codegen(ast, gpu_plan, opts, verbose) do
    target = opts[:target] || :native
    
    case target do
      :native ->
        log(verbose, "Code generation: Native (Zig)")
        generate_native(ast, opts, verbose)
      
      :cuda ->
        log(verbose, "Code generation: CUDA")
        generate_cuda(ast, gpu_plan, opts, verbose)
      
      :rocm ->
        log(verbose, "Code generation: ROCm")
        generate_rocm(ast, gpu_plan, opts, verbose)
      
      _ ->
        {:error, "Unknown target: #{target}"}
    end
  end

  defp generate_native(ast, opts, _verbose) do
    with {:ok, zig_code} <- Zixir.Compiler.ZigBackend.compile(ast) do
      if opts[:output] do
        # Full compilation to binary
        case compile_zig(zig_code, opts) do
          {:ok, binary_path} -> {:ok, {:binary, binary_path}}
          {:error, reason} -> {:error, reason}
        end
      else
        # Just return Zig code
        {:ok, {:zig, zig_code}}
      end
    end
  end

  defp generate_cuda(ast, gpu_plan, opts, verbose) do
    # Extract GPU-suitable functions and compile to CUDA
    candidates = gpu_plan.candidates
    
    if length(candidates) == 0 do
      Logger.warning("No GPU candidates found, falling back to native")
      generate_native(ast, opts, verbose)
    else
      # Compile GPU kernels
      kernels = 
        Enum.map(candidates, fn candidate ->
          case Zixir.Compiler.GPU.compile(candidate.ast, backend: :cuda) do
            {:ok, kernel, _} -> {:ok, candidate.name, kernel}
            {:error, reason} -> {:error, reason}
          end
        end)
      
      # Generate host code that calls kernels
      host_code = generate_cuda_host(ast, kernels)
      
      {:ok, {:cuda, host_code, kernels}}
    end
  end

  defp generate_rocm(ast, gpu_plan, opts, verbose) do
    # Similar to CUDA but with ROCm backend
    generate_cuda(ast, gpu_plan, opts, verbose)
  end

  defp compile_zig(zig_code, opts) do
    output = opts[:output] || "output"
    optimize = opts[:optimize] || :fast
    
    # Write to temp file
    temp_file = Path.join(System.tmp_dir!(), "zixir_#{:erlang.unique_integer([:positive])}.zig")
    File.write!(temp_file, zig_code)
    
    # Compile with zig
    mode = case optimize do
      :debug -> @zig_mode_debug
      :safe -> @zig_mode_safe
      :fast -> @zig_mode_fast
      _ -> @zig_mode_fast
    end
    
    zig_exe = find_zig()
    
    if is_nil(zig_exe) do
      File.rm(temp_file)
      Zixir.Errors.not_found(:compiler, "zig")
    else
      cmd = "#{zig_exe} build-exe #{mode} -femit-bin=#{output} #{temp_file}"
      
      case System.cmd("cmd", ["/c", cmd], stderr_to_stdout: true) do
        {_, 0} ->
          File.rm(temp_file)
          {:ok, output}
        
        {output, _code} ->
          File.rm(temp_file)
          Zixir.Errors.compilation_failed("Zig", output)
      end
    end
  end

  defp generate_cuda_host(_ast, kernels) do
    # Generate C/C++ host code that manages GPU execution
    """
    // Auto-generated CUDA host code
    #include <cuda_runtime.h>
    #include <iostream>
    
    #{Enum.map(kernels, fn {:ok, name, _} -> "extern void #{name}(float*);" end)}
    
    int main() {
      // TODO: Implement host-side orchestration
      return 0;
    }
    """
  end

  # Helper functions

  defp find_zig do
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

  defp log(false, _msg), do: :ok
  defp log(true, msg) do
    IO.puts("[Zixir] #{msg}")
  end
end
