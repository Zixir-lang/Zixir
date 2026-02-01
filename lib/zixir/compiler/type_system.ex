defmodule Zixir.Compiler.TypeSystem do
  @moduledoc """
  Phase 3: Type inference and checking system for Zixir.
  
  Implements Hindley-Milner style type inference with support for:
  - Parametric polymorphism
  - Gradual typing (explicit types override inferred)
  - Type checking at compile time
  """

  defmodule Type do
    @moduledoc "Type representations"
    
    # Base types
    defstruct [:kind, :name, :params]
    
    @type t :: 
      :int |
      :float |
      :bool |
      :string |
      :void |
      {:array, t} |
      {:function, [t], t} |
      {:var, integer()} |  # Type variable for inference
      {:poly, String.t(), [t]}  # Parametric type
    
    def int(), do: :int
    def float(), do: :float
    def bool(), do: :bool
    def string(), do: :string
    def void(), do: :void
    def array(elem_type), do: {:array, elem_type}
    def function(args, ret), do: {:function, args, ret}
    def var(id), do: {:var, id}
    def poly(name, params), do: {:poly, name, params}
  end

  @doc """
  Convert an internal type representation to a human-readable string.

  ## Examples

      iex> type_to_string(:int)
      "Int"
      
      iex> type_to_string({:array, :float})
      "[Float]"
  """
  @spec type_to_string(Type.t()) :: String.t()
  def type_to_string(:int), do: "Int"
  def type_to_string(:float), do: "Float"
  def type_to_string(:bool), do: "Bool"
  def type_to_string(:string), do: "String"
  def type_to_string(:void), do: "Void"
  def type_to_string({:array, t}), do: "[#{type_to_string(t)}]"
  def type_to_string({:function, args, ret}) do
    args_str = Enum.map(args, &type_to_string/1) |> Enum.join(", ")
    "(#{args_str}) -> #{type_to_string(ret)}"
  end
  def type_to_string({:var, id}), do: "'t#{id}"
  def type_to_string({:poly, name, params}) do
    params_str = Enum.map(params, &type_to_string/1) |> Enum.join(", ")
    "#{name}<#{params_str}>"
  end
  def type_to_string(t), do: inspect(t)

  defmodule TypeError do
    defexception [:message, :location, :expected, :actual]
    
    @impl true
    def exception(opts) do
      message = opts[:message] || format_error(opts)
      %TypeError{
        message: message,
        location: opts[:location],
        expected: opts[:expected],
        actual: opts[:actual]
      }
    end
    
    defp format_error(opts) do
      expected = Zixir.Compiler.TypeSystem.type_to_string(opts[:expected])
      actual = Zixir.Compiler.TypeSystem.type_to_string(opts[:actual])
      "Type mismatch: expected #{expected}, got #{actual}"
    end
  end

  @doc """
  Infer types for all expressions in the AST.
  Returns {:ok, typed_ast} or {:error, TypeError}
  """
  @spec infer(term()) :: {:ok, term()} | {:error, TypeError.t()}
  def infer({:program, _} = ast) do
    env = %{}
    var_counter = 0
    
    try do
      result = infer_program(ast, env, var_counter)
      {typed_ast, _final_env, _final_counter} = wrap_result(result)
      {:ok, typed_ast}
    rescue
      e in TypeError -> {:error, e}
    end
  end
  
  def infer(ast) do
    # If not a program, wrap it and infer
    infer({:program, List.wrap(ast)})
  end

  defp wrap_result({{:program, _} = typed_ast, env, counter}) do
    {typed_ast, env, counter}
  end
  
  defp wrap_result({typed_stmts, env, counter}) when is_list(typed_stmts) do
    {{:program, typed_stmts}, env, counter}
  end
  
  defp wrap_result(other) do
    other
  end

  @doc """
  Check if an expression matches an expected type.
  """
  @spec check_type(term(), Type.t(), map()) :: :ok | {:error, String.t()}
  def check_type(expr, expected_type, env) do
    {typed_expr, _new_env, _counter} = infer_expr(expr, env, 0)
    inferred_type = get_type(typed_expr)
    
    if types_match?(inferred_type, expected_type) do
      :ok
    else
      {:error, "Expected #{type_to_string(expected_type)}, got #{type_to_string(inferred_type)}"}
    end
  end

  # Type inference implementation
  
  defp infer_program({:program, statements}, env, counter) do
    {typed_stmts, new_env, new_counter} = 
      Enum.reduce(statements, {[], env, counter}, fn stmt, {acc, e, c} ->
        {typed_stmt, new_e, new_c} = infer_statement(stmt, e, c)
        {[typed_stmt | acc], new_e, new_c}
      end)
    
    {{:program, Enum.reverse(typed_stmts)}, new_env, new_counter}
  end

  defp infer_statement({:function, name, params, return_type, body, is_pub, line, col}, env, counter) do
    # Create type variables for parameters if types not specified
    {param_types, counter} = 
      Enum.map_reduce(params, counter, fn {_pname, ptype}, c ->
        case ptype do
          {:type, :auto} -> 
            {Type.var(c), c + 1}
          {:type, t} -> 
            {zixir_type_to_internal(t), c}
          t -> 
            {zixir_type_to_internal(t), c}
        end
      end)
    
    # Determine return type
    ret_type = case return_type do
      {:type, :auto} -> Type.var(counter)
      {:type, t} -> zixir_type_to_internal(t)
      t -> zixir_type_to_internal(t)
    end
    
    counter = if match?({:var, _}, ret_type), do: counter + 1, else: counter
    
    # Add function to environment
    func_type = Type.function(param_types, ret_type)
    env = Map.put(env, name, func_type)
    
    # Add parameters to environment for body inference
    body_env = 
      Enum.reduce(Enum.zip(params, param_types), env, fn {{pname, _}, ptype}, e ->
        Map.put(e, pname, ptype)
      end)
    
    # Infer body type
    {typed_body, _final_body_env, counter} = infer_statement(body, body_env, counter)
    
    # Unify body type with return type
    body_type = get_type(typed_body)
    {unified_ret, _} = unify(ret_type, body_type, %{})
    
    typed_func = {:function, name, Enum.zip(params, param_types), unified_ret, typed_body, is_pub, line, col}
    {set_type(typed_func, func_type), env, counter}
  end

  defp infer_statement({:let, name, expr, line, col}, env, counter) do
    {typed_expr, new_env, counter} = infer_expr(expr, env, counter)
    expr_type = get_type(typed_expr)
    
    new_env = Map.put(new_env, name, expr_type)
    typed_let = {:let, name, typed_expr, line, col}
    {set_type(typed_let, expr_type), new_env, counter}
  end

  defp infer_statement({:block, statements}, env, counter) do
    {typed_stmts, new_env, counter} = 
      Enum.reduce(statements, {[], env, counter}, fn stmt, {acc, e, c} ->
        {typed_stmt, new_e, new_c} = infer_statement(stmt, e, c)
        {[typed_stmt | acc], new_e, new_c}
      end)
    
    # Block type is the type of the last statement
    block_type = if length(typed_stmts) > 0 do
      get_type(hd(typed_stmts))
    else
      Type.void()
    end
    
    typed_block = {:block, Enum.reverse(typed_stmts)}
    {set_type(typed_block, block_type), new_env, counter}
  end

  defp infer_statement(stmt, env, counter) do
    # Treat as expression statement
    infer_expr(stmt, env, counter)
  end

  defp infer_expr({:number, n, line, col}, env, counter) when is_integer(n) do
    {set_type({:number, n, line, col}, Type.int()), env, counter}
  end

  defp infer_expr({:number, n, line, col}, env, counter) when is_float(n) do
    {set_type({:number, n, line, col}, Type.float()), env, counter}
  end

  defp infer_expr({:string, _, line, col}, env, counter) do
    {set_type({:string, :inferred, line, col}, Type.string()), env, counter}
  end

  defp infer_expr({:bool, _, line, col}, env, counter) do
    {set_type({:bool, :inferred, line, col}, Type.bool()), env, counter}
  end

  defp infer_expr({:var, name, line, col}, env, counter) do
    case Map.get(env, name) do
      nil -> 
        # Create new type variable for unknown variable
        type = Type.var(counter)
        new_env = Map.put(env, name, type)
        {set_type({:var, name, line, col}, type), new_env, counter + 1}
      
      type -> 
        {set_type({:var, name, line, col}, type), env, counter}
    end
  end

  defp infer_expr({:binop, op, left, right}, env, counter) do
    {typed_left, env, counter} = infer_expr(left, env, counter)
    {typed_right, env, counter} = infer_expr(right, env, counter)
    
    left_type = get_type(typed_left)
    right_type = get_type(typed_right)
    
    # Determine result type based on operator
    result_type = case op do
      :add -> infer_arithmetic_type(left_type, right_type)
      :sub -> infer_arithmetic_type(left_type, right_type)
      :mul -> infer_arithmetic_type(left_type, right_type)
      :div -> Type.float()  # Division always returns float
      :and -> Type.bool()
      :or -> Type.bool()
      :eq -> Type.bool()
      :neq -> Type.bool()
      :lt -> Type.bool()
      :gt -> Type.bool()
      _ -> Type.var(counter)
    end
    
    typed_binop = {:binop, op, typed_left, typed_right}
    {set_type(typed_binop, result_type), env, counter}
  end

  defp infer_expr({:unary, op, expr, line, col}, env, counter) do
    {typed_expr, env, counter} = infer_expr(expr, env, counter)
    expr_type = get_type(typed_expr)
    
    result_type = case op do
      :neg -> expr_type
      :not -> Type.bool()
      _ -> Type.var(counter)
    end
    
    typed_unary = {:unary, op, typed_expr, line, col}
    {set_type(typed_unary, result_type), env, counter}
  end

  defp infer_expr({:call, func, args}, env, counter) do
    {typed_func, env, counter} = infer_expr(func, env, counter)
    func_type = get_type(typed_func)
    
    {typed_args, {env, counter}} = 
      Enum.map_reduce(args, {env, counter}, fn arg, {e, c} ->
        {typed_arg, new_e, new_c} = infer_expr(arg, e, c)
        {typed_arg, {new_e, new_c}}
      end)
    
    arg_types = Enum.map(typed_args, &get_type/1)
    
    # Infer or unify return type
    ret_type = case func_type do
      {:function, expected_args, expected_ret} ->
        # Unify argument types
        Enum.zip(arg_types, expected_args)
        |> Enum.reduce({expected_ret, %{}}, fn {actual, expected}, {ret, subst} ->
          {_unified, new_subst} = unify(actual, expected, subst)
          {apply_substitution(ret, new_subst), Map.merge(subst, new_subst)}
        end)
        |> elem(0)
      
      {:var, _} -> 
        # Create function type with new return variable
        ret_var = Type.var(counter)
        new_func_type = Type.function(arg_types, ret_var)
        {_unified, _} = unify(func_type, new_func_type, %{})
        ret_var
      
      _ -> 
        Type.var(counter)
    end
    
    counter = if match?({:var, _}, ret_type), do: counter + 1, else: counter
    
    typed_call = {:call, typed_func, typed_args}
    {set_type(typed_call, ret_type), env, counter}
  end

  defp infer_expr({:if, cond_expr, then_block, else_block, line, col}, env, counter) do
    {typed_cond, env, counter} = infer_expr(cond_expr, env, counter)
    {typed_then, env, counter} = infer_statement(then_block, env, counter)
    
    then_type = get_type(typed_then)
    
    if else_block do
      {typed_else, env, counter} = infer_statement(else_block, env, counter)
      else_type = get_type(typed_else)
      
      # Unify then and else types
      {unified_type, _} = unify(then_type, else_type, %{})
      
      typed_if = {:if, typed_cond, typed_then, typed_else, line, col}
      {set_type(typed_if, unified_type), env, counter}
    else
      typed_if = {:if, typed_cond, typed_then, nil, line, col}
      {set_type(typed_if, then_type), env, counter}
    end
  end

  defp infer_expr({:array, elements, line, col}, env, counter) do
    {typed_elements, {env, counter}} = 
      Enum.map_reduce(elements, {env, counter}, fn elem, {e, c} ->
        {typed_elem, new_e, new_c} = infer_expr(elem, e, c)
        {typed_elem, {new_e, new_c}}
      end)
    
    elem_types = Enum.map(typed_elements, &get_type/1)
    
    # Unify all element types
    array_elem_type = 
      if length(elem_types) > 0 do
        Enum.reduce(tl(elem_types), hd(elem_types), fn t, acc ->
          {unified, _} = unify(acc, t, %{})
          unified
        end)
      else
        Type.var(counter)
      end
    
    counter = if match?({:var, _}, array_elem_type), do: counter + 1, else: counter
    
    typed_array = {:array, typed_elements, line, col}
    {set_type(typed_array, Type.array(array_elem_type)), env, counter}
  end

  defp infer_expr({:index, array, index}, env, counter) do
    {typed_array, env, counter} = infer_expr(array, env, counter)
    {typed_index, env, counter} = infer_expr(index, env, counter)
    
    array_type = get_type(typed_array)
    
    elem_type = case array_type do
      {:array, t} -> t
      {:var, _} -> Type.var(counter)
      _ -> Type.var(counter)
    end
    
    counter = if match?({:var, _}, elem_type), do: counter + 1, else: counter
    
    typed_index_expr = {:index, typed_array, typed_index}
    {set_type(typed_index_expr, elem_type), env, counter}
  end

  # Type unification
  defp unify(t1, t2, subst) when t1 == t2, do: {t1, subst}
  
  defp unify({:var, id}, t, subst) do
    case Map.get(subst, id) do
      nil -> 
        if occurs_in?(id, t) do
          raise TypeError, message: "Occurs check failed - infinite type", location: 0
        end
        {t, Map.put(subst, id, t)}
      
      bound -> unify(bound, t, subst)
    end
  end
  
  defp unify(t, {:var, id}, subst), do: unify({:var, id}, t, subst)
  
  defp unify({:array, t1}, {:array, t2}, subst) do
    {unified, new_subst} = unify(t1, t2, subst)
    {{:array, unified}, new_subst}
  end
  
  defp unify({:function, args1, ret1}, {:function, args2, ret2}, subst) do
    if length(args1) != length(args2) do
      raise TypeError, message: "Function arity mismatch", location: 0
    end
    
    {unified_args, subst} = 
      Enum.zip(args1, args2)
      |> Enum.reduce({[], subst}, fn {a1, a2}, {acc, s} ->
        {u, new_s} = unify(a1, a2, s)
        {[u | acc], new_s}
      end)
    
    {unified_ret, final_subst} = unify(ret1, ret2, subst)
    {{:function, Enum.reverse(unified_args), unified_ret}, final_subst}
  end
  
  defp unify(t1, t2, _subst) do
    raise TypeError, 
      message: "Cannot unify #{type_to_string(t1)} with #{type_to_string(t2)}", 
      location: 0
  end

  defp occurs_in?(id, {:var, id2}), do: id == id2
  defp occurs_in?(id, {:array, t}), do: occurs_in?(id, t)
  defp occurs_in?(id, {:function, args, ret}) do
    Enum.any?(args, &occurs_in?(id, &1)) or occurs_in?(id, ret)
  end
  defp occurs_in?(_, _), do: false

  defp apply_substitution({:var, id}, subst) do
    case Map.get(subst, id) do
      nil -> {:var, id}
      t -> apply_substitution(t, subst)
    end
  end
  
  defp apply_substitution({:array, t}, subst) do
    {:array, apply_substitution(t, subst)}
  end
  
  defp apply_substitution({:function, args, ret}, subst) do
    {:function, 
     Enum.map(args, &apply_substitution(&1, subst)),
     apply_substitution(ret, subst)}
  end
  
  defp apply_substitution(t, _), do: t

  # Helper functions
  defp infer_arithmetic_type(:int, :int), do: :int
  defp infer_arithmetic_type(:float, _), do: :float
  defp infer_arithmetic_type(_, :float), do: :float
  defp infer_arithmetic_type({:var, _} = v, _), do: v
  defp infer_arithmetic_type(_, {:var, _} = v), do: v
  defp infer_arithmetic_type(_, _), do: :float

  defp zixir_type_to_internal(:Int), do: :int
  defp zixir_type_to_internal(:Float), do: :float
  defp zixir_type_to_internal(:Bool), do: :bool
  defp zixir_type_to_internal(:String), do: :string
  defp zixir_type_to_internal(:Void), do: :void
  defp zixir_type_to_internal(t) when is_atom(t), do: t
  defp zixir_type_to_internal(_), do: {:var, 0}

  defp types_match?(t1, t2), do: t1 == t2

  # Pattern: {tag, value} -> type is 2nd element
  defp get_type({_, _, type}), do: type
  # Pattern: {tag, value, extra} -> type is 3rd element  
  defp get_type({_, _, _, type}), do: type
  # Pattern: {tag, value, line, col} -> type is 4th element (4 total)
  defp get_type({_, _, _, _, type}), do: type
  # Pattern: {tag, value, line, col, type} -> type is 5th element (5 total)
  defp get_type({_, _, _, _, _, type}), do: type
  # Fallback for {:type, type, term}
  defp get_type({:type, type}), do: type
  defp get_type(_), do: :unknown

  defp set_type({tag, a, b, c, d}, type), do: {tag, a, b, c, d, type}
  defp set_type({tag, a, b, c}, type), do: {tag, a, b, c, type}
  defp set_type({tag, a, b}, type), do: {tag, a, b, type}
  defp set_type({tag, a}, type), do: {tag, a, type}
  defp set_type(term, type), do: {:type, type, term}

  @doc """
  Get the type of an expression from the typed AST.
  """
  @spec expr_type(term()) :: Type.t()
  def expr_type({_, _, _, _, _, type}), do: type
  def expr_type({_, _, _, _, type}), do: type
  def expr_type({_, _, _, type}), do: type
  def expr_type({:type, type, _}), do: type
  def expr_type({_, _, type}), do: type
  def expr_type({_, type}), do: type
  def expr_type(_), do: :unknown

  @doc """
  Check if a type is concrete (fully resolved, no type variables).
  """
  @spec concrete_type?(Type.t()) :: boolean()
  def concrete_type?({:var, _}), do: false
  def concrete_type?({:array, elem_type}), do: concrete_type?(elem_type)
  def concrete_type?({:function, args, ret}) do
    Enum.all?(args, &concrete_type?/1) and concrete_type?(ret)
  end
  def concrete_type?({:poly, _, params}) do
    Enum.all?(params, &concrete_type?/1)
  end
  def concrete_type?(_), do: true

  @doc """
  Format a type for display to the user.
  """
  @spec format_type(Type.t()) :: String.t()
  def format_type(type), do: type_to_string(type)

  @doc """
  Run type inference and return detailed results.
  """
  @spec infer_detailed(term()) :: {:ok, term(), map()} | {:error, TypeError.t()}
  def infer_detailed(ast) do
    case infer(ast) do
      {:ok, typed_ast} ->
        stats = collect_type_stats(typed_ast)
        {:ok, typed_ast, stats}
      
      {:error, error} ->
        {:error, error}
    end
  end

  defp collect_type_stats({:program, statements}) do
    types = collect_all_types(statements, [])
    
    %{
      total_expressions: length(types),
      concrete_types: Enum.count(types, &concrete_type?/1),
      type_variables: Enum.count(types, fn {:var, _} -> true; _ -> false end),
      function_types: Enum.count(types, fn {:function, _, _} -> true; _ -> false end),
      array_types: Enum.count(types, fn {:array, _} -> true; _ -> false end)
    }
  end

  defp collect_all_types(statements, acc) when is_list(statements) do
    Enum.reduce(statements, acc, fn stmt, a ->
      collect_all_types(stmt, a)
    end)
  end

  defp collect_all_types({:function, _, _, _, body, _, _, _, _}, acc) do
    collect_all_types(body, acc)
  end

  defp collect_all_types({:let, _, expr, _, _, _}, acc) do
    collect_all_types(expr, acc)
  end

  defp collect_all_types({:block, statements}, acc) do
    collect_all_types(statements, acc)
  end

  defp collect_all_types({_, _, _, _, _, type}, acc) do
    [type | acc]
  end

  defp collect_all_types({_, _, _, _, type}, acc) do
    [type | acc]
  end

  defp collect_all_types({_, _, _, type}, acc) do
    [type | acc]
  end

  defp collect_all_types({:type, type, _}, acc) do
    [type | acc]
  end

  defp collect_all_types({_, _, type}, acc) do
    [type | acc]
  end

  defp collect_all_types({_, type}, acc) do
    [type | acc]
  end

  defp collect_all_types(_, acc), do: acc

  defp infer_expr({:lambda, params, return_type, body, line, col}, env, counter) do
    {param_types, counter} = 
      Enum.map_reduce(params, counter, fn {_pname, ptype}, c ->
        case ptype do
          {:type, :auto} -> {Type.var(c), c + 1}
          {:type, t} -> {zixir_type_to_internal(t), c}
          t -> {zixir_type_to_internal(t), c}
        end
      end)
    
    ret_type = case return_type do
      {:type, :auto} -> Type.var(counter)
      {:type, t} -> zixir_type_to_internal(t)
      t -> zixir_type_to_internal(t)
    end
    
    counter = if match?({:var, _}, ret_type), do: counter + 1, else: counter
    
    lambda_env = 
      Enum.reduce(Enum.zip(params, param_types), env, fn {{pname, _}, ptype}, e ->
        Map.put(e, pname, ptype)
      end)
    
    {typed_body, _final_env, counter} = infer_statement(body, lambda_env, counter)
    body_type = get_type(typed_body)
    
    {unified_ret, _} = unify(ret_type, body_type, %{})
    
    lambda_type = Type.function(param_types, unified_ret)
    typed_lambda = {:lambda, Enum.zip(params, param_types), unified_ret, typed_body, line, col}
    {set_type(typed_lambda, lambda_type), env, counter}
  end

  defp infer_expr({:struct, name, fields, line, col}, env, counter) do
    field_types = Enum.map(fields, fn {fname, ftype} ->
      {fname, zixir_type_to_internal(ftype)}
    end)
    
    struct_type = {:struct, field_types}
    typed_struct = {:struct, name, field_types, line, col}
    {set_type(typed_struct, struct_type), env, counter}
  end

  defp infer_expr({:struct_init, name, field_inits, line, col}, env, counter) do
    {typed_inits, {env, counter}} = 
      Enum.map_reduce(field_inits, {env, counter}, fn {fname, expr}, {e, c} ->
        {typed_expr, new_e, new_c} = infer_expr(expr, e, c)
        {{fname, typed_expr}, {new_e, new_c}}
      end)
    
    field_types = Enum.map(typed_inits, fn {fname, typed_expr} ->
      {fname, get_type(typed_expr)}
    end)
    
    struct_type = {:struct, field_types}
    typed_init = {:struct_init, name, typed_inits, line, col}
    {set_type(typed_init, struct_type), env, counter}
  end

  defp infer_expr({:struct_get, struct_expr, field_name, line, col}, env, counter) do
    {typed_struct, env, counter} = infer_expr(struct_expr, env, counter)
    struct_type = get_type(typed_struct)
    
    field_type = case struct_type do
      {:struct, field_types} ->
        case List.keyfind(field_types, field_name, 0) do
          {^field_name, ftype} -> ftype
          nil -> Type.var(counter)
        end
      _ -> Type.var(counter)
    end
    
    counter = if match?({:var, _}, field_type), do: counter + 1, else: counter
    
    typed_get = {:struct_get, typed_struct, field_name, line, col}
    {set_type(typed_get, field_type), env, counter}
  end

  defp infer_expr({:map, entries, line, col}, env, counter) when is_list(entries) do
    {typed_entries, {env, counter}} = 
      Enum.map_reduce(entries, {env, counter}, fn {key_expr, value_expr}, {e, c} ->
        {typed_key, new_e, new_c} = infer_expr(key_expr, e, c)
        {typed_value, final_e, final_c} = infer_expr(value_expr, new_e, new_c)
        {{typed_key, typed_value}, {final_e, final_c}}
      end)
    
    key_types = Enum.map(typed_entries, fn {k, _} -> get_type(k) end)
    value_types = Enum.map(typed_entries, fn {_, v} -> get_type(v) end)
    
    unified_key = if length(key_types) > 0 do
      Enum.reduce(tl(key_types), hd(key_types), fn t, acc ->
        {u, _} = unify(acc, t, %{})
        u
      end)
    else
      Type.var(counter)
    end
    
    unified_value = if length(value_types) > 0 do
      Enum.reduce(tl(value_types), hd(value_types), fn t, acc ->
        {u, _} = unify(acc, t, %{})
        u
      end)
    else
      Type.var(counter + 1)
    end
    
    counter = if match?({:var, _}, unified_key), do: counter + 1, else: counter
    counter = if match?({:var, _}, unified_value), do: counter + 1, else: counter
    
    map_type = {:map, unified_key, unified_value}
    typed_map = {:map, typed_entries, line, col}
    {set_type(typed_map, map_type), env, counter}
  end

  defp infer_expr({:map_get, map_expr, key_expr, line, col}, env, counter) do
    {typed_map, env, counter} = infer_expr(map_expr, env, counter)
    {typed_key, env, counter} = infer_expr(key_expr, env, counter)
    
    map_type = get_type(typed_map)
    
    value_type = case map_type do
      {:map, _, value_type} -> value_type
      _ -> Type.var(counter)
    end
    
    counter = if match?({:var, _}, value_type), do: counter + 1, else: counter
    
    typed_get = {:map_get, typed_map, typed_key, line, col}
    {set_type(typed_get, value_type), env, counter}
  end

  defp infer_expr({:list_comp, generator, filter, map_expr, line, col}, env, counter) do
    {typed_gen, env, counter} = infer_expr(generator, env, counter)
    
    env_with_gen = case generator do
      {:for_gen, var, _} -> Map.put(env, var, Type.var(counter))
      _ -> env
    end
    
    env_with_gen = if filter != nil do
      {_typed_filter, env_with_gen, _counter} = infer_expr(filter, env_with_gen, counter)
      env_with_gen
    else
      env_with_gen
    end
    
    {typed_map, _env_with_gen, counter} = infer_expr(map_expr, env_with_gen, counter)
    elem_type = get_type(typed_map)
    
    typed_comp = {:list_comp, typed_gen, nil, typed_map, line, col}
    {set_type(typed_comp, Type.array(elem_type)), env, counter}
  end

  defp infer_expr({:range, start, end_expr, line, col}, env, counter) do
    {typed_start, env, counter} = infer_expr(start, env, counter)
    {typed_end, env, counter} = infer_expr(end_expr, env, counter)
    
    start_type = get_type(typed_start)
    end_type = get_type(typed_end)
    
    range_type = case {start_type, end_type} do
      {:int, :int} -> Type.array(:int)
      {_, _} -> Type.array(Type.var(counter))
    end
    
    typed_range = {:range, typed_start, typed_end, line, col}
    {set_type(typed_range, range_type), env, counter}
  end

  defp infer_expr({:try, body, catches, line, col}, env, counter) do
    {typed_body, env, counter} = infer_statement(body, env, counter)
    body_type = get_type(typed_body)
    
    catch_types = Enum.map(catches, fn {_var, _type, catch_body} ->
      {typed_catch, _env, _counter} = infer_statement(catch_body, env, counter)
      get_type(typed_catch)
    end)
    
    unified_type = if length(catch_types) > 0 do
      Enum.reduce(catch_types, body_type, fn ct, acc ->
        {u, _} = unify(acc, ct, %{})
        u
      end)
    else
      body_type
    end
    
    typed_try = {:try, typed_body, catches, line, col}
    {set_type(typed_try, unified_type), env, counter}
  end

  defp infer_expr({:async, expr, line, col}, env, counter) do
    {typed_expr, env, counter} = infer_expr(expr, env, counter)
    expr_type = get_type(typed_expr)
    
    future_type = {:future, expr_type}
    typed_async = {:async, typed_expr, line, col}
    {set_type(typed_async, future_type), env, counter}
  end

  defp infer_expr({:await, expr, line, col}, env, counter) do
    {typed_expr, env, counter} = infer_expr(expr, env, counter)
    expr_type = get_type(typed_expr)
    
    result_type = case expr_type do
      {:future, t} -> t
      _ -> Type.var(counter)
    end
    
    counter = if match?({:var, _}, result_type), do: counter + 1, else: counter
    
    typed_await = {:await, typed_expr, line, col}
    {set_type(typed_await, result_type), env, counter}
  end

  # Catch-all for any unhandled expression types
  defp infer_expr(expr, env, counter) do
    {set_type(expr, Type.var(counter)), env, counter + 1}
  end
end
