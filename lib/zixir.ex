defmodule Zixir do
  @moduledoc """
  Zixir: three-tier runtime — Elixir (orchestrator), Zig (engine), Python (specialist).

  - `run_engine/2` — hot path (math, data) → Zig NIFs
  - `call_python/3` — library calls → Python via port
  - `eval/1`, `run/1` — run Zixir source (parse + compile + evaluate)
  """

  @doc """
  Run engine (Zig) operation. Use for memory-critical math and high-speed data.
  """
  defdelegate run_engine(op, args), to: Zixir.Intent

  @doc """
  Call Python specialist. Use for library calls only (module, function, args).
  """
  defdelegate call_python(module, function, args), to: Zixir.Intent

  @doc """
  Parse, compile, and evaluate Zixir source. Returns {:ok, result} or {:error, Zixir.CompileError}.
  """
  def eval(source) when is_binary(source) do
    case Zixir.Compiler.Parser.parse(source) do
      {:ok, ast} -> eval_ast(ast)
      {:error, %Zixir.Compiler.Parser.ParseError{} = e} ->
        {:error, %Zixir.CompileError{message: e.message, line: e.line, column: e.column}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Interpret simple AST expressions directly
  defp eval_ast({:program, []}), do: {:ok, nil}
  defp eval_ast({:program, [single_expr]}), do: eval_expr(single_expr)
  defp eval_ast({:program, statements}) do
    # Evaluate multiple statements with environment
    eval_statements(statements, %{})
  end

  defp eval_statements([], _env), do: {:ok, nil}
  defp eval_statements([stmt], env), do: eval_statement(stmt, env)
  defp eval_statements([stmt | rest], env) do
    case eval_statement(stmt, env) do
      {:ok, _result, new_env} -> eval_statements(rest, new_env)
      {:ok, result} -> eval_statements(rest, env) |> update_last_result(result)
      {:error, _reason} = err -> err
    end
  end

  defp update_last_result({:ok, _}, result), do: {:ok, result}
  defp update_last_result({:error, _} = err, _), do: err

  defp eval_statement({:let, name, expr, _line, _col}, env) do
    case eval_expr(expr, env) do
      {:ok, value} -> {:ok, value, Map.put(env, name, value)}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp eval_statement({:function, name, params, _return_type, body, _is_pub, _line, _col}, env) do
    # Store function definition in environment
    # params is list of {param_name, param_type}
    param_names = Enum.map(params, fn {pname, _ptype} -> pname end)
    func_def = {:func, param_names, body}
    {:ok, name, Map.put(env, name, func_def)}
  end
  
  defp eval_statement(stmt, env), do: eval_expr(stmt, env)

  defp eval_expr(expr), do: eval_expr(expr, %{})
  
  defp eval_expr({:number, n, _line, _col}, _env) when is_number(n), do: {:ok, n}
  defp eval_expr({:string, s, _line, _col}, _env) when is_binary(s), do: {:ok, s}
  defp eval_expr({:bool, b, _line, _col}, _env) when is_boolean(b), do: {:ok, b}
  defp eval_expr({:var, name, _line, _col}, env) do
    case Map.get(env, name) do
      nil -> {:error, "Undefined variable: #{name}"}
      value -> {:ok, value}
    end
  end
  
  defp eval_expr({:binop, op, left, right}, env) do
    with {:ok, lval} <- eval_expr(left, env),
         {:ok, rval} <- eval_expr(right, env) do
      eval_binop(op, lval, rval)
    end
  end
  
  defp eval_expr({:call, {:field, {:var, "engine", _, _}, func_name}, args}, env) do
    # Engine call: engine.list_sum([...])
    with {:ok, evaled_args} <- eval_args(args, env) do
      op = String.to_atom(func_name)
      result = Zixir.Engine.run(op, evaled_args)
      {:ok, result}
    end
  end
  
  defp eval_expr({:call, {:var, func_name, _line, _col}, args}, env) do
    # User-defined function call: add(1, 2)
    case Map.get(env, func_name) do
      nil -> 
        {:error, "Undefined function: #{func_name}"}
      
      {:func, param_names, body} ->
        with {:ok, evaled_args} <- eval_args(args, env) do
          if length(evaled_args) != length(param_names) do
            {:error, "Function #{func_name} expects #{length(param_names)} arguments, got #{length(evaled_args)}"}
          else
            # Create new environment with parameters bound
            call_env = Enum.zip(param_names, evaled_args)
              |> Enum.reduce(env, fn {param, value}, acc_env ->
                Map.put(acc_env, param, value)
              end)
            
            # Evaluate function body
            eval_expr(body, call_env)
          end
        end
    end
  end
  
  defp eval_expr({:array, elements, _line, _col}, env) do
    eval_args(elements, env)
  end

  defp eval_expr({:if, cond_expr, then_block, else_block, _line, _col}, env) do
    with {:ok, cond_val} <- eval_expr(cond_expr, env) do
      if cond_val do
        eval_block(then_block, env)
      else
        if else_block do
          eval_block(else_block, env)
        else
          {:ok, nil}
        end
      end
    end
  end

  defp eval_expr({:unary, :not, expr, _line, _col}, env) do
    with {:ok, val} <- eval_expr(expr, env) do
      {:ok, !val}
    end
  end

  defp eval_expr({:unary, :neg, expr, _line, _col}, env) do
    with {:ok, val} <- eval_expr(expr, env) do
      {:ok, -val}
    end
  end

  defp eval_expr({:block, statements}, env) do
    eval_block_statements(statements, env)
  end

  defp eval_expr({:while, cond_expr, body, _line, _col}, env) do
    eval_while_loop(cond_expr, body, env)
  end

  defp eval_expr({:for, var_name, iterable, body, _line, _col}, env) do
    with {:ok, items} <- eval_expr(iterable, env) do
      eval_for_loop(var_name, items, body, env)
    end
  end

  defp eval_expr({:match, value_expr, clauses, _line, _col}, env) do
    with {:ok, value} <- eval_expr(value_expr, env) do
      eval_match(value, clauses, env)
    end
  end
  
  defp eval_expr(_expr, _env) do
    {:error, "Unsupported expression"}
  end

  defp eval_block({:block, statements}, env) do
    eval_block_statements(statements, env)
  end

  defp eval_block(expr, env) do
    eval_expr(expr, env)
  end

  defp eval_block_statements([], _env), do: {:ok, nil}
  defp eval_block_statements([stmt], env), do: eval_statement(stmt, env)
  defp eval_block_statements([stmt | rest], env) do
    case eval_statement(stmt, env) do
      {:ok, _result, new_env} -> eval_block_statements(rest, new_env)
      {:ok, result} -> 
        # If it's the last statement, return the result
        if rest == [] do
          {:ok, result}
        else
          eval_block_statements(rest, env)
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp eval_while_loop(cond_expr, body, env) do
    eval_while_loop_iter(cond_expr, body, env, nil)
  end

  defp eval_while_loop_iter(cond_expr, body, env, last_result) do
    case eval_expr(cond_expr, env) do
      {:ok, true} ->
        case eval_block(body, env) do
          {:ok, result} -> eval_while_loop_iter(cond_expr, body, env, result)
          {:error, reason} -> {:error, reason}
        end
      {:ok, false} ->
        {:ok, last_result}
      {:ok, _other} ->
        {:error, "While loop condition must be boolean"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp eval_for_loop(var_name, items, body, env) when is_list(items) do
    eval_for_loop_iter(var_name, items, body, env, nil)
  end

  defp eval_for_loop(_var_name, _items, _body, _env) do
    {:error, "For loop requires a list"}
  end

  defp eval_for_loop_iter(_var_name, [], _body, _env, last_result) do
    {:ok, last_result}
  end

  defp eval_for_loop_iter(var_name, [item | rest], body, env, _last_result) do
    # Bind the variable and evaluate the body
    loop_env = Map.put(env, var_name, item)
    case eval_block(body, loop_env) do
      {:ok, result} -> eval_for_loop_iter(var_name, rest, body, env, result)
      {:error, reason} -> {:error, reason}
    end
  end

  defp eval_args(args, env) do
    Enum.reduce_while(args, {:ok, []}, fn arg, {:ok, acc} ->
      case eval_expr(arg, env) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp eval_binop(:add, l, r) when is_number(l) and is_number(r), do: {:ok, l + r}
  defp eval_binop(:sub, l, r) when is_number(l) and is_number(r), do: {:ok, l - r}
  defp eval_binop(:mul, l, r) when is_number(l) and is_number(r), do: {:ok, l * r}
  defp eval_binop(:div, l, r) when is_number(l) and is_number(r) and r != 0, do: {:ok, l / r}
  defp eval_binop(:div, _l, r) when r == 0, do: {:error, "Division by zero"}
  
  # Comparison operators
  defp eval_binop(:==, l, r), do: {:ok, l == r}
  defp eval_binop(:!=, l, r), do: {:ok, l != r}
  defp eval_binop(:<, l, r) when is_number(l) and is_number(r), do: {:ok, l < r}
  defp eval_binop(:>, l, r) when is_number(l) and is_number(r), do: {:ok, l > r}
  defp eval_binop(:<=, l, r) when is_number(l) and is_number(r), do: {:ok, l <= r}
  defp eval_binop(:>=, l, r) when is_number(l) and is_number(r), do: {:ok, l >= r}
  
  # Boolean operators
  defp eval_binop(:and, l, r), do: {:ok, l && r}
  defp eval_binop(:or, l, r), do: {:ok, l || r}
  
  defp eval_binop(_op, _l, _r), do: {:error, "Invalid binary operation"}

  # Pattern matching evaluation
  defp eval_match(_value, [], _env) do
    {:error, "No matching clause found"}
  end

  defp eval_match(value, [{pattern, body} | rest], env) do
    case match_pattern(pattern, value, env) do
      {:match, new_env} ->
        # Pattern matched, evaluate body with new bindings
        eval_expr(body, new_env)
      
      :no_match ->
        # Try next clause
        eval_match(value, rest, env)
    end
  end

  # Pattern matching logic
  defp match_pattern({:number, n, _, _}, value, env) when is_number(value) do
    if n == value, do: {:match, env}, else: :no_match
  end

  defp match_pattern({:string, s, _, _}, value, env) when is_binary(value) do
    if s == value, do: {:match, env}, else: :no_match
  end

  defp match_pattern({:bool, b, _, _}, value, env) when is_boolean(value) do
    if b == value, do: {:match, env}, else: :no_match
  end

  defp match_pattern({:var, name, _, _}, value, env) do
    # Variable pattern - binds value to name
    {:match, Map.put(env, name, value)}
  end

  defp match_pattern({:array, elements, _, _}, value, env) when is_list(value) do
    # Array pattern matching
    if length(elements) == length(value) do
      match_array_patterns(elements, value, env)
    else
      :no_match
    end
  end

  defp match_pattern({:binop, :==, left, right}, _value, env) do
    # Guard pattern - evaluate and check if true
    with {:ok, lval} <- eval_expr(left, env),
         {:ok, rval} <- eval_expr(right, env) do
      if lval == rval, do: {:match, env}, else: :no_match
    else
      _ -> :no_match
    end
  end

  defp match_pattern({:binop, :<, left, right}, _value, env) do
    with {:ok, lval} <- eval_expr(left, env),
         {:ok, rval} <- eval_expr(right, env) do
      if is_number(lval) and is_number(rval) and lval < rval, 
        do: {:match, env}, 
        else: :no_match
    else
      _ -> :no_match
    end
  end

  defp match_pattern({:binop, :>, left, right}, _value, env) do
    with {:ok, lval} <- eval_expr(left, env),
         {:ok, rval} <- eval_expr(right, env) do
      if is_number(lval) and is_number(rval) and lval > rval, 
        do: {:match, env}, 
        else: :no_match
    else
      _ -> :no_match
    end
  end

  defp match_pattern({:call, {:var, "_", _, _}, []}, _value, env) do
    # Wildcard pattern - matches anything
    {:match, env}
  end

  defp match_pattern(_pattern, _value, _env) do
    :no_match
  end

  defp match_array_patterns([], [], env), do: {:match, env}
  
  defp match_array_patterns([p | p_rest], [v | v_rest], env) do
    case match_pattern(p, v, env) do
      {:match, new_env} -> match_array_patterns(p_rest, v_rest, new_env)
      :no_match -> :no_match
    end
  end
  
  defp match_array_patterns(_, _, _env), do: :no_match

  @doc """
  Like eval/1 but raises on parse/compile error. Returns the result.
  """
  def run(source) when is_binary(source) do
    case eval(source) do
      {:ok, result} -> result
      {:error, %Zixir.CompileError{} = e} -> raise e
      {:error, %Zixir.Compiler.Parser.ParseError{} = e} -> 
        raise %Zixir.CompileError{message: e.message}
      {:error, reason} when is_binary(reason) ->
        raise %Zixir.CompileError{message: reason}
    end
  end

  @doc """
  Start the interactive REPL (Read-Eval-Print Loop).
  
  ## Example
  
      iex> Zixir.repl()
      Welcome to Zixir REPL v0.1.0
      Type :help for help, :quit to exit
      
      zixir> let x = 10
      10
      zixir> x + 5
      15
      zixir> :quit
      Goodbye!
  """
  def repl(opts \\ []) do
    Zixir.REPL.start(opts)
  end
end
