defmodule Mix.Tasks.Zixir do
  @moduledoc """
  Unified Zixir CLI tool.
  
  ## Commands
  
  - `mix zixir compile <file.zr>` - Compile to native binary
  - `mix zixir run <file.zr>` - Compile and run immediately
  - `mix zixir test [files]` - Run tests
  - `mix zixir repl` - Start interactive REPL
  - `mix zixir check <file.zr>` - Type check only
  - `mix zixir python` - Test Python FFI connection
  
  ## Options
  
  - `--optimize` - Optimization level: debug, release_safe, release_fast (default: release_fast)
  - `--verbose` - Show detailed compilation output
  - `--target` - Cross-compilation target triple
  - `--output` - Output file path
  
  ## Examples
  
      mix zixir compile main.zr
      mix zixir run main.zr --verbose
      mix zixir compile main.zr --optimize release_safe --output myapp
      mix zixir test
      mix zixir repl
  """

  use Mix.Task

  @shortdoc "Zixir language compiler and toolchain"

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:zixir)
    
    case args do
      ["compile" | rest] -> compile_command(rest)
      ["run" | rest] -> run_command(rest)
      ["test" | rest] -> test_command(rest)
      ["repl" | _] -> repl_command()
      ["check" | rest] -> check_command(rest)
      ["python" | rest] -> python_command(rest)
      ["help" | _] -> help_command()
      [] -> 
        IO.puts("Error: No command specified")
        help_command()
        System.halt(1)
      [cmd | _] -> 
        IO.puts("Unknown command: #{cmd}")
        help_command()
        System.halt(1)
    end
  end

  # Command implementations
  
  defp compile_command(args) do
    {opts, files, _} = OptionParser.parse(args,
      switches: [
        optimize: :string,
        verbose: :boolean,
        target: :string,
        output: :string
      ],
      aliases: [
        o: :output,
        v: :verbose,
        O: :optimize
      ]
    )
    
    case files do
      [file | _] ->
        optimize = parse_optimize(opts[:optimize])
        
        IO.puts("Compiling #{file}...")
        
        case Zixir.Compiler.Pipeline.compile_file(file,
          optimize: optimize,
          verbose: opts[:verbose] || false,
          target: opts[:target],
          output: opts[:output]
        ) do
          {:ok, binary_path} ->
            IO.puts("✓ Compiled successfully: #{binary_path}")
            
          {:error, reason} ->
            IO.puts("✗ Compilation failed: #{reason}")
            System.halt(1)
        end
        
      [] ->
        IO.puts("Error: No input file specified")
        IO.puts("Usage: mix zixir compile <file.zr>")
        System.halt(1)
    end
  end
  
  defp run_command(args) do
    {opts, files, extra_args} = OptionParser.parse(args,
      switches: [
        optimize: :string,
        verbose: :boolean
      ],
      aliases: [
        v: :verbose,
        O: :optimize
      ]
    )
    
    case files do
      [file | _] ->
        optimize = parse_optimize(opts[:optimize])
        verbose = opts[:verbose] || false
        
        if verbose, do: IO.puts("Running #{file}...")
        
        # Read and compile
        case File.read(file) do
          {:ok, source} ->
            case Zixir.Compiler.Pipeline.run_string(source, extra_args,
              optimize: optimize,
              verbose: verbose
            ) do
              {:ok, output} ->
                IO.puts(output)
                
              {:error, reason} ->
                IO.puts("✗ Execution failed: #{reason}")
                System.halt(1)
            end
            
          {:error, reason} ->
            IO.puts("✗ Cannot read file: #{reason}")
            System.halt(1)
        end
        
      [] ->
        IO.puts("Error: No input file specified")
        IO.puts("Usage: mix zixir run <file.zr> [args...]")
        System.halt(1)
    end
  end
  
  defp test_command(args) do
    {_opts, files, _} = OptionParser.parse(args,
      switches: [
        verbose: :boolean,
        include: :string
      ],
      aliases: [
        v: :verbose
      ]
    )
    
    IO.puts("Running Zixir tests...")
    
    # Run compiler tests
    test_files = if length(files) > 0 do
      files
    else
      Path.wildcard("test/**/*_test.exs")
    end
    
    # Run tests using ExUnit
    ExUnit.start()
    
    Enum.each(test_files, fn file ->
      if File.exists?(file) do
        Code.require_file(file)
      end
    end)
    
    # Also run Zixir source tests if any
    zixir_tests = Path.wildcard("test/**/*.zr")
    
    if length(zixir_tests) > 0 do
      IO.puts("\nRunning #{length(zixir_tests)} Zixir source tests...")
      
      Enum.each(zixir_tests, fn test_file ->
        IO.puts("  Testing #{test_file}...")
        
        case File.read(test_file) do
          {:ok, source} ->
            case Zixir.Compiler.Parser.parse(source) do
              {:ok, ast} ->
                case Zixir.Compiler.TypeSystem.infer(ast) do
                  {:ok, _} -> 
                    IO.puts("    ✓ #{test_file}")
                  {:error, error} ->
                    IO.puts("    ✗ #{test_file}: #{error.message}")
                end
              {:error, error} ->
                IO.puts("    ✗ #{test_file}: Parse error at line #{error.line}")
            end
            
          {:error, reason} ->
            IO.puts("    ✗ #{test_file}: Cannot read file (#{reason})")
        end
      end)
    end
    
    # Run ExUnit tests
    IO.puts("\nRunning ExUnit tests...")
    ExUnit.run()
  end
  
  defp repl_command do
    IO.puts("Zixir REPL (Interactive Shell)")
    IO.puts("Type :quit or :q to exit, :help for commands")
    IO.puts("")
    
    repl_loop(%{})
  end
  
  defp repl_loop(env) do
    IO.write("zixir> ")
    
    case IO.gets("") do
      :eof -> 
        IO.puts("\nGoodbye!")
        
      {:error, _} ->
        IO.puts("\nInput error. Exiting.")
        
      line ->
        input = String.trim(line)
        
        case input do
          "" -> repl_loop(env)
          
          ":quit" -> IO.puts("Goodbye!")
          ":q" -> IO.puts("Goodbye!")
          
          ":help" ->
            IO.puts("Commands:")
            IO.puts("  :quit, :q    - Exit REPL")
            IO.puts("  :help        - Show this help")
            IO.puts("  :env         - Show current environment")
            IO.puts("  :type <expr> - Show type of expression")
            IO.puts("")
            repl_loop(env)
            
          ":env" ->
            IO.inspect(env, pretty: true)
            repl_loop(env)
            
          ":type " <> expr ->
            case Zixir.Compiler.Parser.parse(expr) do
              {:ok, ast} ->
                case Zixir.Compiler.TypeSystem.infer({:program, [ast]}) do
                  {:ok, typed_ast} ->
                    type = extract_type(typed_ast)
                    IO.puts("Type: #{type_to_string(type)}")
                  {:error, error} ->
                    IO.puts("Type error: #{error.message}")
                end
              {:error, error} ->
                IO.puts("Parse error: #{error.message}")
            end
            repl_loop(env)
            
          _ ->
            # Evaluate expression
            case Zixir.Compiler.Parser.parse(input) do
              {:ok, _ast} ->
                case Zixir.Compiler.Pipeline.run_string(input, [], verbose: false) do
                  {:ok, result} ->
                    IO.puts("=> #{String.trim(result)}")
                    repl_loop(env)
                    
                  {:error, reason} ->
                    IO.puts("Error: #{reason}")
                    repl_loop(env)
                end
                
              {:error, error} ->
                IO.puts("Parse error at line #{error.line}: #{error.message}")
                repl_loop(env)
            end
        end
    end
  end
  
  defp check_command(args) do
    case args do
      [file | _] ->
        IO.puts("Type checking #{file}...")
        
        case File.read(file) do
          {:ok, source} ->
            case Zixir.Compiler.Parser.parse(source) do
              {:ok, ast} ->
                case Zixir.Compiler.TypeSystem.infer(ast) do
                  {:ok, typed_ast} ->
                    IO.puts("✓ Type checking passed")
                    
                    if "--show-types" in args do
                      show_inferred_types(typed_ast)
                    end
                    
                  {:error, error} ->
                    IO.puts("✗ Type error at line #{error.location}: #{error.message}")
                    System.halt(1)
                end
                
              {:error, error} ->
                IO.puts("✗ Parse error at line #{error.line}: #{error.message}")
                System.halt(1)
            end
            
          {:error, reason} ->
            IO.puts("✗ Cannot read file: #{reason}")
            System.halt(1)
        end
        
      [] ->
        IO.puts("Error: No input file specified")
        IO.puts("Usage: mix zixir check <file.zr>")
        System.halt(1)
    end
  end
  
  defp python_command(_args) do
    IO.puts("Testing Python FFI connection...")
    
    case Zixir.Compiler.PythonFFI.init() do
      {:ok, version} ->
        IO.puts("✓ Python interpreter initialized (version #{version})")
        
        # Test basic call
        case Zixir.Compiler.PythonFFI.call("math", "sqrt", [16.0]) do
          {:ok, result} ->
            IO.puts("✓ Python call successful: math.sqrt(16.0) = #{result}")
            
          {:error, reason} ->
            IO.puts("✗ Python call failed: #{reason}")
        end
        
        # Test module availability
        modules = ["math", "numpy", "pandas", "sys"]
        IO.puts("\nChecking common modules:")
        
        Enum.each(modules, fn mod ->
          if Zixir.Compiler.PythonFFI.has_module?(mod) do
            IO.puts("  ✓ #{mod}")
          else
            IO.puts("  ✗ #{mod} (not available)")
          end
        end)
        
        Zixir.Compiler.PythonFFI.finalize()
        IO.puts("\n✓ Python FFI test complete")
        
      {:error, reason} ->
        IO.puts("✗ Failed to initialize Python: #{reason}")
        System.halt(1)
    end
  end
  
  defp help_command do
    IO.puts(@moduledoc)
  end
  
  # Helper functions
  
  defp parse_optimize(nil), do: :release_fast
  defp parse_optimize("debug"), do: :debug
  defp parse_optimize("safe"), do: :release_safe
  defp parse_optimize("fast"), do: :release_fast
  defp parse_optimize("0"), do: :debug
  defp parse_optimize("1"), do: :release_safe
  defp parse_optimize("2"), do: :release_fast
  defp parse_optimize(_), do: :release_fast
  
  defp extract_type({:program, [stmt | _]}) do
    extract_type(stmt)
  end
  
  defp extract_type({_, _, _, _, _, type}), do: type
  defp extract_type({_, _, _, _, type}), do: type
  defp extract_type({_, _, _, type}), do: type
  defp extract_type({_, _, type}), do: type
  defp extract_type({_, type}), do: type
  defp extract_type(_), do: :unknown
  
  defp type_to_string(:int), do: "Int"
  defp type_to_string(:float), do: "Float"
  defp type_to_string(:bool), do: "Bool"
  defp type_to_string(:string), do: "String"
  defp type_to_string(:void), do: "Void"
  defp type_to_string({:array, t}), do: "[#{type_to_string(t)}]"
  defp type_to_string({:function, args, ret}) do
    args_str = Enum.map(args, &type_to_string/1) |> Enum.join(", ")
    "(#{args_str}) -> #{type_to_string(ret)}"
  end
  defp type_to_string({:var, id}), do: "'t#{id}"
  defp type_to_string(t), do: inspect(t)
  
  defp show_inferred_types({:program, stmts}) do
    IO.puts("\nInferred types:")
    Enum.each(stmts, &show_stmt_type/1)
  end
  
  defp show_stmt_type({:function, name, _, ret_type, _, _, _, _}) do
    IO.puts("  #{name}: #{type_to_string(ret_type)}")
  end
  
  defp show_stmt_type({:let, name, expr, _, _}) do
    type = extract_type(expr)
    IO.puts("  #{name}: #{type_to_string(type)}")
  end
  
  defp show_stmt_type(_), do: :ok
end
