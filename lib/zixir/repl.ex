defmodule Zixir.REPL do
  @moduledoc """
  Interactive REPL (Read-Eval-Print Loop) for Zixir.
  
  Features:
  - Line editing with history (if ex_tty is available)
  - Multi-line input support
  - Variable persistence across commands
  - Built-in help system
  - Command completion hints
  
  ## Usage
  
      iex> Zixir.REPL.start()
      
      zixir> let x = 10
      10
      
      zixir> x + 5
      15
      
      zixir> engine.list_sum([1.0, 2.0, 3.0])
      6.0
      
      zixir> :help
      Available commands: ...
      
      zixir> :quit
  """

  require Logger

  @welcome_message """
  Welcome to Zixir REPL v7.1.0
  Type :help for help, :quit to exit
  
  """

  @help_message """
  REPL Commands:
    :help        - Show this help message
    :quit, :q    - Exit the REPL
    :clear       - Clear the screen
    :vars        - Show defined variables
    :engine      - List available engine operations
    :python      - Check Python bridge status
    :reset       - Clear all variables
    
  Language Features:
    - let x = 5              - Variable binding
    - x + 10                 - Expression evaluation
    - engine.list_sum([...]) - Engine operations
    - python "math" "sqrt" (16.0)  - Python calls
    - if x > 5: 10 else: 20  - Conditionals
    - [1, 2, 3]              - Arrays
    - fn add(x, y): x + y    - Functions (experimental)
  """

  @doc """
  Start the interactive REPL.
  """
  def start(_opts) do
    IO.puts(@welcome_message)
    
    initial_state = %{
      env: %{},
      history: [],
      multiline_buffer: "",
      line_count: 0
    }
    
    loop(initial_state)
  end

  defp loop(state) do
    prompt = if state.multiline_buffer == "" do
      "zixir> "
    else
      "    ... "
    end
    
    case IO.gets(prompt) do
      :eof ->
        IO.puts("\nGoodbye!")
        :ok
      
      {:error, reason} ->
        IO.puts("Input error: #{inspect(reason)}")
        loop(state)
      
      line ->
        line = String.trim_trailing(line, "\n")
        
        case process_input(line, state) do
          {:continue, new_state} ->
            loop(new_state)
          
          {:exit, _} ->
            IO.puts("Goodbye!")
            :ok
        end
    end
  end

  defp process_input(line, state) do
    # Check for REPL commands
    case line do
      ":quit" -> {:exit, state}
      ":q" -> {:exit, state}
      ":help" -> 
        IO.puts(@help_message)
        {:continue, state}
      
      ":clear" ->
        IO.write("\e[H\e[2J")  # ANSI clear screen
        {:continue, state}
      
      ":vars" ->
        show_variables(state.env)
        {:continue, state}
      
      ":engine" ->
        show_engine_ops()
        {:continue, state}
      
      ":python" ->
        show_python_status()
        {:continue, state}
      
      ":reset" ->
        IO.puts("Cleared all variables")
        {:continue, %{state | env: %{}}}
      
      "" ->
        # Empty line in multiline mode ends the block
        if state.multiline_buffer != "" do
          process_multiline(state)
        else
          {:continue, state}
        end
      
      _ ->
        # Check if this looks like incomplete input
        if incomplete?(line) and state.multiline_buffer == "" do
          # Start multiline mode
          {:continue, %{state | multiline_buffer: line, line_count: state.line_count + 1}}
        else
          if state.multiline_buffer != "" do
            # Continue multiline
            new_buffer = state.multiline_buffer <> "\n" <> line
            {:continue, %{state | multiline_buffer: new_buffer, line_count: state.line_count + 1}}
          else
            # Single line evaluation
            evaluate(line, state)
          end
        end
    end
  end

  defp incomplete?(line) do
    # Check for signs of incomplete input
    cond do
      # Unclosed parentheses/brackets
      count_char(line, "(") > count_char(line, ")") -> true
      count_char(line, "[") > count_char(line, "]") -> true
      count_char(line, "{") > count_char(line, "}") -> true
      
      # Ends with continuation characters
      String.ends_with?(line, "\\") -> true
      
      # Ends with operators (likely continuation)
      String.ends_with?(line, "+") or 
      String.ends_with?(line, "-") or 
      String.ends_with?(line, "*") or 
      String.ends_with?(line, "/") -> true
      
      # Incomplete let statement
      String.starts_with?(line, "let") and !String.contains?(line, "=") -> true
      
      # Incomplete if statement
      String.starts_with?(line, "if") and !String.contains?(line, ":") -> true
      
      true -> false
    end
  end

  defp count_char(str, char) do
    String.split(str, char) |> length() |> Kernel.-(1)
  end

  defp process_multiline(state) do
    code = state.multiline_buffer
    evaluate(code, %{state | multiline_buffer: "", line_count: 0})
  end

  defp evaluate(code, state) do
    case Zixir.Interpreter.eval(code, state.env) do
      {:ok, result, new_env} ->
        if result != nil do
          IO.puts(format_result(result))
        end

        {:continue, %{state | env: new_env, history: [code | state.history]}}

      {:error, message} when is_binary(message) ->
        IO.puts("Error: #{message}")
        {:continue, %{state | multiline_buffer: "", line_count: 0}}

      {:error, %Zixir.CompileError{} = error} ->
        IO.puts("Error: #{error.message}")
        {:continue, %{state | multiline_buffer: "", line_count: 0}}

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        {:continue, %{state | multiline_buffer: "", line_count: 0}}
    end
  end

  defp format_result(result) when is_float(result) do
    # Format floats nicely
    if result == trunc(result) do
      "#{trunc(result)}.0"
    else
      "#{:erlang.float_to_binary(result, [:compact, decimals: 10])}"
    end
  end
  
  defp format_result(result) when is_list(result) do
    inner = Enum.map(result, &format_result/1) |> Enum.join(", ")
    "[#{inner}]"
  end
  
  defp format_result(result) when is_binary(result) do
    "\"#{result}\""
  end
  
  defp format_result(result) when is_map(result) do
    inner = Enum.map(result, fn {k, v} -> "#{k}: #{format_result(v)}" end) |> Enum.join(", ")
    "{#{inner}}"
  end
  
  defp format_result(nil), do: "nil"
  defp format_result(true), do: "true"
  defp format_result(false), do: "false"
  defp format_result(result), do: inspect(result)

  defp show_variables(env) do
    if map_size(env) == 0 do
      IO.puts("No variables defined")
    else
      IO.puts("Defined variables:")
      Enum.each(env, fn {name, value} ->
        IO.puts("  #{name} = #{format_result(value)}")
      end)
    end
  end

  @engine_categories [
    {"Aggregations", ~w(list_sum list_product list_mean list_min list_max list_variance list_std)},
    {"Vector", ~w(dot_product vec_add vec_sub vec_mul vec_div vec_scale)},
    {"Transform", ~w(map_add map_mul filter_gt sort_asc)},
    {"Search", ~w(find_index count_value)},
    {"Matrix", ~w(mat_mul mat_transpose)},
    {"String", ~w(string_count string_find string_starts_with string_ends_with)}
  ]

  defp show_engine_ops() do
    ops = Zixir.Engine.operations()
    IO.puts("Available engine operations (#{length(ops)} total):")
    IO.puts("")

    Enum.each(@engine_categories, fn {category, known_ops} ->
      matching = Enum.filter(ops, &(Atom.to_string(&1) in known_ops))
      unless matching == [] do
        IO.puts("#{category}: #{Enum.map_join(matching, ", ", &Atom.to_string/1)}")
      end
    end)

    uncategorized = Enum.reject(ops, fn op ->
      Enum.any?(@engine_categories, fn {_, known} -> Atom.to_string(op) in known end)
    end)
    unless uncategorized == [] do
      IO.puts("Other: #{Enum.map_join(uncategorized, ", ", &Atom.to_string/1)}")
    end

    IO.puts("")
    IO.puts("Example: engine.list_sum([1.0, 2.0, 3.0])")
  end

  defp show_python_status() do
    case Zixir.Python.healthy?() do
      true ->
        stats = Zixir.Python.stats()
        IO.puts("Python bridge: Healthy")
        IO.puts("  Workers: #{stats.healthy_workers}/#{stats.total_workers} healthy")
      
      false ->
        IO.puts("Python bridge: Not available")
        IO.puts("  Check that Python is installed and on PATH")
    end
  end
end
