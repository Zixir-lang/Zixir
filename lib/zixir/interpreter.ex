defmodule Zixir.Interpreter do
  @moduledoc """
  Tree-walking interpreter for Zixir AST.
  
  Evaluates Zixir programs directly without compilation.
  Used for REPL, testing, and rapid prototyping.
  
  ## Features
  - Variable bindings and scoping
  - Function definitions and calls
  - Engine operations (Zig NIFs)
  - Python FFI calls
  - Pattern matching
  - Control flow (if/else, while, for)
  - Arrays and maps
  """

  alias Zixir.Parser.Unified

  @doc """
  Evaluate a Zixir program from source code.
  
  ## Returns
    - `{:ok, result, env}` - Successful evaluation with final environment
    - `{:error, reason}` - Evaluation error
  
  ## Examples
  
      iex> Zixir.Interpreter.eval("let x = 5")
      {:ok, 5, %{"x" => 5}}
      
      iex> Zixir.Interpreter.eval("x + 10", %{"x" => 5})
      {:ok, 15, %{"x" => 5}}
  """
  @spec eval(String.t(), map()) :: {:ok, term(), map()} | {:error, String.t()}
  def eval(source, env \\ %{}) when is_binary(source) do
    case Unified.parse(source) do
      {:ok, ast} -> eval_ast(ast, env)
      {:error, error} -> {:error, "Parse error: #{error.message}"}
    end
  end

  @doc """
  Evaluate an AST node.
  """
  @spec eval_ast(term(), map()) :: {:ok, term(), map()} | {:error, String.t()}
  def eval_ast({:program, []}, env), do: {:ok, nil, env}
  def eval_ast({:program, statements}, env) do
    eval_statements(statements, env, nil)
  end

  # ============================================================================
  # Statement Evaluation
  # ============================================================================

  defp eval_statements([], env, last_result), do: {:ok, last_result, env}
  
  defp eval_statements([stmt | rest], env, _last_result) do
    case eval_statement(stmt, env) do
      {:ok, result, new_env} -> eval_statements(rest, new_env, result)
      {:error, reason} -> {:error, reason}
    end
  end

  defp eval_statement({:let, name, expr, _line, _col}, env) do
    case eval_expr(expr, env) do
      {:ok, value} -> {:ok, value, Map.put(env, name, value)}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp eval_statement({:let, name, expr, _is_const, _line, _col}, env) do
    # Backward compatibility with old AST format
    eval_statement({:let, name, expr, _line, _col}, env)
  end

  defp eval_statement({:function, name, params, _return_type, body, _is_pub, _line, _col}, env) do
    # Store function definition in environment
    param_names = Enum.map(params, fn {pname, _ptype} -> pname end)
    func_def = {:func, param_names, body}
    {:ok, name, Map.put(env, name, func_def)}
  end

  defp eval_statement({:block, statements}, env) do
    eval_statements(statements, env, nil)
  end

  defp eval_statement(stmt, env) do
    # Expression statement
    case eval_expr(stmt, env) do
      {:ok, value} -> {:ok, value, env}
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Expression Evaluation
  # ============================================================================

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

  defp eval_expr({:unary, :neg, expr, _line, _col}, env) do
    with {:ok, val} <- eval_expr(expr, env) do
      {:ok, -val}
    end
  end

  defp eval_expr({:unary, :not, expr, _line, _col}, env) do
    with {:ok, val} <- eval_expr(expr, env) do
      {:ok, !val}
    end
  end

  defp eval_expr({:array, elements, _line, _col}, env) do
    eval_list(elements, env, [])
  end

  defp eval_expr({:map, entries, _line, _col}, env) do
    eval_map_entries(entries, env, [])
  end

  defp eval_expr({:index, array_expr, index_expr}, env) do
    with {:ok, array} <- eval_expr(array_expr, env),
         {:ok, index} <- eval_expr(index_expr, env) do
      eval_index(array, index)
    end
  end

  defp eval_expr({:field, object_expr, field_name}, env) do
    with {:ok, object} <- eval_expr(object_expr, env) do
      eval_field_access(object, field_name)
    end
  end

  defp eval_expr({:engine_call, func_name, args, _line, _col}, env) do
    with {:ok, evaled_args} <- eval_args(args, env) do
      op = String.to_atom(func_name)
      try do
        result = Zixir.Engine.run(op, evaled_args)
        {:ok, result}
      rescue
        e in ArgumentError ->
          {:error, "Engine operation #{func_name} failed: #{Exception.message(e)}"}
        e in ArithmeticError ->
          {:error, "Engine operation #{func_name} failed: #{Exception.message(e)}"}
        _e in FunctionClauseError ->
          {:error, "Engine operation #{func_name}: invalid arguments #{inspect(evaled_args)}"}
        e ->
          {:error, "Engine operation #{func_name} failed: #{Exception.message(e)}"}
      end
    end
  end
  
  defp eval_expr({:engine_call, func_name, args}, env) do
    # Backward compatibility: engine call without line/col
    eval_expr({:engine_call, func_name, args, 0, 0}, env)
  end

  defp eval_expr({:python_call, module, function, args, _line, _col}, env) do
    # Python FFI call
    with {:ok, evaled_args} <- eval_args(args, env) do
      Zixir.Intent.call_python(module, function, evaled_args)
    end
  end
  
  defp eval_expr({:python_call, module, function, args}, env) do
    # Backward compatibility: python call without line/col
    eval_expr({:python_call, module, function, args, 0, 0}, env)
  end

  defp eval_expr({:call, {:var, func_name, _line1, _col1}, args, _line2, _col2}, env) do
    with {:ok, evaled_args} <- eval_args(args, env) do
      case eval_builtin(func_name, evaled_args) do
        {:builtin, result} ->
          result

        :not_builtin ->
          case Map.get(env, func_name) do
            nil ->
              {:error, "Undefined function: #{func_name}"}

            {:func, param_names, body} ->
              if length(evaled_args) != length(param_names) do
                {:error, "Function #{func_name} expects #{length(param_names)} arguments, got #{length(evaled_args)}"}
              else
                call_env = Enum.zip(param_names, evaled_args)
                  |> Enum.reduce(env, fn {param, value}, acc_env ->
                    Map.put(acc_env, param, value)
                  end)
                eval_expr(body, call_env)
              end
          end
      end
    end
  end

  defp eval_expr({:call, func_expr, args, _line, _col}, env) do
    # General function call (e.g., lambda)
    with {:ok, func} <- eval_expr(func_expr, env),
         {:ok, evaled_args} <- eval_args(args, env) do
      eval_function_call(func, evaled_args)
    end
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

  defp eval_expr({:while, cond_expr, body, _line, _col}, env) do
    eval_while_loop(cond_expr, body, env, nil)
  end

  defp eval_expr({:for, var_name, iterable_expr, body, _line, _col}, env) do
    with {:ok, iterable} <- eval_expr(iterable_expr, env) do
      eval_for_loop(var_name, iterable, body, env)
    end
  end

  defp eval_expr({:match, value_expr, clauses, _line, _col}, env) do
    with {:ok, value} <- eval_expr(value_expr, env) do
      eval_match_clauses(value, clauses, env)
    end
  end

  defp eval_expr({:lambda, params, _return_type, body, _line, _col}, env) do
    param_names = Enum.map(params, fn {pname, _ptype} -> pname end)
    # Return a closure
    {:ok, {:closure, param_names, body, env}}
  end

  defp eval_expr({:pipe, left_expr, right_expr}, env) do
    with {:ok, left_val} <- eval_expr(left_expr, env) do
      case right_expr do
        {:call, func, args, line, col} ->
          eval_expr({:call, func, [{:literal, left_val} | args], line, col}, env)
        {:call, func, args} ->
          eval_expr({:call, func, [{:literal, left_val} | args]}, env)
        _ ->
          {:error, "Right side of pipe must be a function call"}
      end
    end
  end

  defp eval_expr({:literal, value}, _env), do: {:ok, value}

  defp eval_expr({:async, expr, _line, _col}, env) do
    # For now, async just evaluates synchronously
    # In a full implementation, this would spawn a Task
    eval_expr(expr, env)
  end

  defp eval_expr({:await, expr, _line, _col}, env) do
    # For now, await just evaluates
    # In a full implementation, this would wait for a Task
    eval_expr(expr, env)
  end

  defp eval_expr({:block, statements}, env) do
    eval_statements(statements, env, nil)
    |> case do
      {:ok, result, _new_env} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp eval_expr({:try, body, catches, _line, _col}, env) do
    case eval_expr(body, env) do
      {:ok, value} -> {:ok, value}
      {:error, reason} ->
        case find_matching_catch(catches, reason, env) do
          {:ok, value} -> {:ok, value}
          :no_match -> {:error, reason}
        end
    end
  end

  defp eval_expr(expr, _env) do
    {:error, "Unsupported expression: #{inspect(expr)}"}
  end

  defp find_matching_catch([], _reason, _env), do: :no_match
  defp find_matching_catch([{error_var, _error_type, catch_body} | rest], reason, env) do
    catch_env = Map.put(env, error_var, reason)
    case eval_expr(catch_body, catch_env) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> find_matching_catch(rest, reason, env)
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp eval_block({:block, statements}, env) do
    case eval_statements(statements, env, nil) do
      {:ok, result, _new_env} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp eval_block(expr, env) do
    eval_expr(expr, env)
  end

  defp eval_while_loop(cond_expr, body, env, _last_result) do
    case eval_expr(cond_expr, env) do
      {:ok, true} ->
        case eval_block(body, env) do
          {:ok, _result} -> eval_while_loop(cond_expr, body, env, nil)
          {:error, reason} -> {:error, reason}
        end
      {:ok, false} ->
        {:ok, nil}
      {:ok, other} ->
        {:error, "While loop condition must be boolean, got: #{inspect(other)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp eval_for_loop(_var_name, items, _body, _env) when not is_list(items) do
    {:error, "For loop requires a list, got: #{inspect(items)}"}
  end
  
  defp eval_for_loop(var_name, items, body, env) do
    Enum.reduce(items, {:ok, nil, env}, fn item, acc ->
      case acc do
        {:error, reason} -> {:error, reason}
        {:ok, _last_result, current_env} ->
          loop_env = Map.put(current_env, var_name, item)
          case eval_block(body, loop_env) do
            {:ok, result} -> {:ok, result, current_env}
            {:error, reason} -> {:error, reason}
          end
      end
    end)
    |> case do
      {:ok, result, _env} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp eval_match_clauses(_value, [], _env) do
    {:error, "No matching clause found"}
  end

  defp eval_match_clauses(value, [{pattern, body} | rest], env) do
    case match_pattern(pattern, value, env) do
      {:match, new_env} ->
        eval_expr(body, new_env)
      :no_match ->
        eval_match_clauses(value, rest, env)
    end
  end

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
    if length(elements) == length(value) do
      match_array_patterns(elements, value, env)
    else
      :no_match
    end
  end

  defp match_pattern({:binop, :==, left, right}, _value, env) do
    # Guard pattern
    with {:ok, lval} <- eval_expr(left, env),
         {:ok, rval} <- eval_expr(right, env) do
      if lval == rval, do: {:match, env}, else: :no_match
    else
      _ -> :no_match
    end
  end

  defp match_pattern({:call, {:var, "_", _, _}, [], _, _}, _value, env) do
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

  # ============================================================================
  # Built-in Functions
  # ============================================================================

  defp eval_builtin("length", [val]) when is_list(val), do: {:builtin, {:ok, length(val)}}
  defp eval_builtin("length", [val]) when is_binary(val), do: {:builtin, {:ok, String.length(val)}}
  defp eval_builtin("length", [val]) when is_map(val), do: {:builtin, {:ok, map_size(val)}}
  defp eval_builtin("length", [val]), do: {:builtin, {:error, "length() expects array, string, or map, got: #{inspect(val)}"}}

  defp eval_builtin("to_string", [val]) when is_integer(val), do: {:builtin, {:ok, Integer.to_string(val)}}
  defp eval_builtin("to_string", [val]) when is_float(val), do: {:builtin, {:ok, Float.to_string(val)}}
  defp eval_builtin("to_string", [val]) when is_binary(val), do: {:builtin, {:ok, val}}
  defp eval_builtin("to_string", [val]) when is_boolean(val), do: {:builtin, {:ok, Atom.to_string(val)}}
  defp eval_builtin("to_string", [val]) when is_nil(val), do: {:builtin, {:ok, "null"}}
  defp eval_builtin("to_string", [val]) when is_list(val), do: {:builtin, {:ok, inspect(val)}}
  defp eval_builtin("to_string", [val]) when is_map(val), do: {:builtin, {:ok, inspect(val)}}
  defp eval_builtin("to_string", [val]), do: {:builtin, {:ok, inspect(val)}}

  defp eval_builtin("print", args) do
    output = Enum.map_join(args, " ", &to_display_string/1)
    IO.puts(output)
    {:builtin, {:ok, output}}
  end

  defp eval_builtin("abs", [val]) when is_number(val), do: {:builtin, {:ok, abs(val)}}
  defp eval_builtin("abs", [val]), do: {:builtin, {:error, "abs() expects a number, got: #{inspect(val)}"}}

  defp eval_builtin("min", [a, b]) when is_number(a) and is_number(b), do: {:builtin, {:ok, min(a, b)}}
  defp eval_builtin("max", [a, b]) when is_number(a) and is_number(b), do: {:builtin, {:ok, max(a, b)}}

  defp eval_builtin("type_of", [val]) do
    type = cond do
      is_integer(val) -> "Int"
      is_float(val) -> "Float"
      is_binary(val) -> "String"
      is_boolean(val) -> "Bool"
      is_list(val) -> "Array"
      is_map(val) -> "Map"
      is_nil(val) -> "Null"
      true -> "Unknown"
    end
    {:builtin, {:ok, type}}
  end

  defp eval_builtin("parse_int", [val]) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> {:builtin, {:ok, n}}
      :error -> {:builtin, {:error, "Cannot parse '#{val}' as integer"}}
    end
  end

  defp eval_builtin("parse_float", [val]) when is_binary(val) do
    case Float.parse(val) do
      {n, _} -> {:builtin, {:ok, n}}
      :error -> {:builtin, {:error, "Cannot parse '#{val}' as float"}}
    end
  end

  defp eval_builtin("keys", [val]) when is_map(val), do: {:builtin, {:ok, Map.keys(val)}}
  defp eval_builtin("values", [val]) when is_map(val), do: {:builtin, {:ok, Map.values(val)}}

  defp eval_builtin("contains", [list, item]) when is_list(list), do: {:builtin, {:ok, item in list}}
  defp eval_builtin("contains", [str, sub]) when is_binary(str) and is_binary(sub), do: {:builtin, {:ok, String.contains?(str, sub)}}

  defp eval_builtin("split", [str, sep]) when is_binary(str) and is_binary(sep), do: {:builtin, {:ok, String.split(str, sep)}}
  defp eval_builtin("split", [str]) when is_binary(str), do: {:builtin, {:ok, String.split(str)}}

  defp eval_builtin("join", [list, sep]) when is_list(list) and is_binary(sep) do
    {:builtin, {:ok, Enum.map_join(list, sep, &to_display_string/1)}}
  end

  defp eval_builtin("reverse", [list]) when is_list(list), do: {:builtin, {:ok, Enum.reverse(list)}}
  defp eval_builtin("reverse", [str]) when is_binary(str), do: {:builtin, {:ok, String.reverse(str)}}

  defp eval_builtin("range", [a, b]) when is_integer(a) and is_integer(b), do: {:builtin, {:ok, Enum.to_list(a..b)}}

  defp eval_builtin("head", [list]) when is_list(list) and length(list) > 0, do: {:builtin, {:ok, hd(list)}}
  defp eval_builtin("tail", [list]) when is_list(list) and length(list) > 0, do: {:builtin, {:ok, tl(list)}}

  defp eval_builtin("push", [list, item]) when is_list(list), do: {:builtin, {:ok, list ++ [item]}}

  defp eval_builtin("upper", [str]) when is_binary(str), do: {:builtin, {:ok, String.upcase(str)}}
  defp eval_builtin("lower", [str]) when is_binary(str), do: {:builtin, {:ok, String.downcase(str)}}
  defp eval_builtin("trim", [str]) when is_binary(str), do: {:builtin, {:ok, String.trim(str)}}

  defp eval_builtin(_name, _args), do: :not_builtin

  defp to_display_string(val) when is_binary(val), do: val
  defp to_display_string(val) when is_integer(val), do: Integer.to_string(val)
  defp to_display_string(val) when is_float(val), do: Float.to_string(val)
  defp to_display_string(val) when is_boolean(val), do: Atom.to_string(val)
  defp to_display_string(nil), do: "null"
  defp to_display_string(val), do: inspect(val)

  defp eval_binop(:add, l, r) when is_number(l) and is_number(r), do: {:ok, l + r}
  defp eval_binop(:sub, l, r) when is_number(l) and is_number(r), do: {:ok, l - r}
  defp eval_binop(:mul, l, r) when is_number(l) and is_number(r), do: {:ok, l * r}
  defp eval_binop(:div, _l, r) when r == 0, do: {:error, "Division by zero"}
  defp eval_binop(:div, l, r) when is_number(l) and is_number(r), do: {:ok, l / r}
  defp eval_binop(:mod, _l, r) when r == 0, do: {:error, "Modulo by zero"}
  defp eval_binop(:mod, l, r) when is_integer(l) and is_integer(r), do: {:ok, rem(l, r)}
  defp eval_binop(:mod, l, r) when is_number(l) and is_number(r), do: {:ok, :math.fmod(l, r)}
  defp eval_binop(:==, l, r), do: {:ok, l == r}
  defp eval_binop(:!=, l, r), do: {:ok, l != r}
  defp eval_binop(:<, l, r) when is_number(l) and is_number(r), do: {:ok, l < r}
  defp eval_binop(:>, l, r) when is_number(l) and is_number(r), do: {:ok, l > r}
  defp eval_binop(:<=, l, r) when is_number(l) and is_number(r), do: {:ok, l <= r}
  defp eval_binop(:>=, l, r) when is_number(l) and is_number(r), do: {:ok, l >= r}
  defp eval_binop(:and, l, r), do: {:ok, l && r}
  defp eval_binop(:or, l, r), do: {:ok, l || r}
  defp eval_binop(:++, l, r) when is_binary(l) and is_binary(r), do: {:ok, l <> r}
  defp eval_binop(:++, l, r) when is_list(l) and is_list(r), do: {:ok, l ++ r}
  defp eval_binop(op, l, r), do: {:error, "Invalid binary operation: #{inspect(op)} on #{inspect(l)} and #{inspect(r)}"}

  defp eval_args(args, env) do
    eval_list(args, env, [])
  end

  defp eval_list([], _env, acc), do: {:ok, Enum.reverse(acc)}
  
  defp eval_list([elem | rest], env, acc) do
    case eval_expr(elem, env) do
      {:ok, value} -> eval_list(rest, env, [value | acc])
      {:error, reason} -> {:error, reason}
    end
  end

  defp eval_map_entries([], _env, acc), do: {:ok, Map.new(acc)}
  
  defp eval_map_entries([{key_expr, value_expr} | rest], env, acc) do
    with {:ok, key} <- eval_expr(key_expr, env),
         {:ok, value} <- eval_expr(value_expr, env) do
      eval_map_entries(rest, env, [{key, value} | acc])
    end
  end

  defp eval_index(array, index) when is_list(array) and is_integer(index) do
    if index >= 0 and index < length(array) do
      {:ok, Enum.at(array, index)}
    else
      {:error, "Index out of bounds: #{index}"}
    end
  end

  defp eval_index(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil -> {:ok, nil}
      value -> {:ok, value}
    end
  end

  defp eval_index(collection, _index) when not is_list(collection) and not is_map(collection) do
    {:error, "Cannot index value: #{inspect(collection)}"}
  end

  defp eval_field_access(map, field) when is_map(map) do
    case Map.get(map, field) do
      nil -> {:error, "Field not found: #{field}"}
      value -> {:ok, value}
    end
  end
  
  defp eval_field_access(object, _field) do
    {:error, "Cannot access field on non-object: #{inspect(object)}"}
  end

  defp eval_function_call({:closure, param_names, body, closure_env}, args) do
    if length(args) != length(param_names) do
      {:error, "Closure expects #{length(param_names)} arguments, got #{length(args)}"}
    else
      call_env = Enum.zip(param_names, args)
        |> Enum.reduce(closure_env, fn {param, value}, acc_env ->
          Map.put(acc_env, param, value)
        end)
      
      eval_expr(body, call_env)
    end
  end
  
  defp eval_function_call(func, _args) do
    {:error, "Not a function: #{inspect(func)}"}
  end
end
