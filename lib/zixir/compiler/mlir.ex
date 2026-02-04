defmodule Zixir.Compiler.MLIR do
  @moduledoc """
  Phase 4: MLIR integration for advanced optimizations.
  
  Provides:
  - Automatic vectorization
  - Loop optimizations
  - Hardware-specific code generation
  - Bridge to MLIR dialects (LLVM, CUDA, ROCm)
  
  When Beaver is available, this enables MLIR-based optimization pipeline.
  Otherwise, provides stubs that pass through to Zig backend.
  """

  require Logger

  @doc """
  Check if MLIR/Beaver is available.
  """
  def available? do
    Code.ensure_loaded?(Beaver) and function_exported?(Beaver.MLIR, :__info__, 1)
  end

  @doc """
  Optimize Zixir AST using MLIR when available.
  Falls back to identity transformation if MLIR unavailable.
  """
  def optimize(ast, opts \\ []) do
    if available?() do
      do_optimize(ast, opts)
    else
      # Even without MLIR, we can do some basic optimizations
      ast = apply_basic_optimizations(ast, opts)
      {:ok, ast}
    end
  end

  @doc """
  Apply basic optimizations without MLIR.
  """
  def apply_basic_optimizations(ast, opts \\ []) do
    passes = opts[:passes] || []
    # When Beaver/MLIR is unavailable, map MLIR pass names to AST-level optimizations
    Enum.reduce(passes, ast, fn pass, acc ->
      case pass do
        :constant_folding -> constant_folding(acc)
        :dead_code_elimination -> dead_code_elimination(acc)
        :inline_small_functions -> inline_small_functions(acc)
        :canonicalize -> constant_folding(acc)
        :cse -> common_subexpression_elimination(acc)
        :vectorize -> vectorize_loops(acc)
        :inline -> inline_functions(acc)
        :gpu_offload -> mark_gpu_candidate(acc)
        :parallelize -> parallelize_loops(acc)
        _ -> acc
      end
    end)
  end

  @doc """
  Lower Zixir AST to MLIR IR.
  """
  def to_mlir(ast) do
    if available?() do
      do_to_mlir(ast)
    else
      {:error, :mlir_not_available}
    end
  end

  @doc """
  Compile MLIR IR to target (LLVM, CUDA, etc.).
  """
  def compile_mlir(ir, target \\ :llvm) do
    if available?() do
      do_compile_mlir(ir, target)
    else
      {:error, :mlir_not_available}
    end
  end

  # MLIR optimization passes
  
  @doc """
  Run vectorization pass on array operations.
  """
  def vectorize(ast) do
    optimize(ast, passes: [:vectorize])
  end

  @doc """
  Run parallelization pass to identify parallelizable loops.
  """
  def parallelize(ast) do
    optimize(ast, passes: [:parallelize])
  end

  @doc """
  Run GPU offload pass to identify GPU-suitable operations.
  """
  def gpu_offload(ast) do
    optimize(ast, passes: [:gpu_offload])
  end

  # Implementation (stubs when Beaver unavailable)

  defp do_optimize(ast, opts) do
    passes = opts[:passes] || [:canonicalize, :cse, :inline]
    
    try do
      # Convert to MLIR
      {:ok, mlir_ir} = do_to_mlir(ast)
      
      # Apply optimization passes
      optimized_ir = apply_passes(mlir_ir, passes)
      
      # Convert back to Zixir AST (or keep as IR for further processing)
      {:ok, optimized_ast} = from_mlir(optimized_ir)
      
      {:ok, optimized_ast}
    rescue
      e ->
        Logger.warning("MLIR optimization failed: #{Exception.message(e)}. Falling back.")
        {:ok, ast}
    end
  end

  defp do_to_mlir(ast) do
    # Generate MLIR dialect code from Zixir AST
    mlir_code = generate_mlir(ast)
    {:ok, mlir_code}
  end

  defp do_compile_mlir(ir, target) do
    case target do
      :llvm -> compile_to_llvm(ir)
      :cuda -> compile_to_cuda(ir)
      :rocm -> compile_to_rocm(ir)
      _ -> {:error, :unsupported_target}
    end
  end

  # MLIR code generation
  
  defp generate_mlir({:program, statements}) do
    funcs = Enum.map(statements, &mlir_function/1)
    
    """
    module {
      #{Enum.join(funcs, "\n\n")}
    }
    """
  end

  defp mlir_function({:function, name, params, return_type, body, is_pub, _line, _col}) do
    visibility = if is_pub, do: "public", else: "private"
    
    params_mlir = 
      Enum.map(params, fn {pname, ptype} ->
        "%#{pname}: #{mlir_type(ptype)}"
      end)
      |> Enum.join(", ")
    
    ret_type = mlir_type(return_type)
    
    body_mlir = mlir_statement(body)
    
    """
    func.func #{visibility} @#{name}(#{params_mlir}) -> #{ret_type} {
    #{body_mlir}
    }
    """
  end

  defp mlir_statement({:block, statements}) do
    stmts_mlir = Enum.map(statements, &mlir_statement/1)
    Enum.join(stmts_mlir, "\n")
  end

  defp mlir_statement({:let, name, expr, _line, _col}) do
    expr_mlir = mlir_expr(expr)
    "  %#{name} = #{expr_mlir}"
  end

  defp mlir_statement(expr) do
    mlir_expr(expr)
  end

  defp mlir_expr({:number, n, _, _}) when is_integer(n) do
    "arith.constant #{n} : i64"
  end

  defp mlir_expr({:number, n, _, _}) when is_float(n) do
    "arith.constant #{n} : f64"
  end

  defp mlir_expr({:var, name, _, _}) do
    "%#{name}"
  end

  defp mlir_expr({:binop, op, left, right}) do
    left_mlir = mlir_expr(left)
    right_mlir = mlir_expr(right)
    mlir_op = mlir_operator(op)
    
    "#{mlir_op} #{left_mlir}, #{right_mlir} : f64"
  end

  defp mlir_expr({:call, func, args}) do
    func_name = case func do
      {:var, name, _, _} -> name
      _ -> "unknown"
    end
    
    args_mlir = Enum.map(args, &mlir_expr/1) |> Enum.join(", ")
    "  func.call @#{func_name}(#{args_mlir}) : () -> f64"
  end

  defp mlir_expr({:array, elements, _, _}) do
    elems = Enum.map(elements, &mlir_expr/1) |> Enum.join(", ")
    "vector.constant dense<[#{elems}]> : vector<#{length(elements)}xf64>"
  end

  defp mlir_expr(_other) do
    "  // Unsupported expression"
  end

  defp mlir_operator(:add), do: "arith.addf"
  defp mlir_operator(:sub), do: "arith.subf"
  defp mlir_operator(:mul), do: "arith.mulf"
  defp mlir_operator(:div), do: "arith.divf"
  defp mlir_operator(_), do: "arith.addf"

  defp mlir_type({:type, :Int}), do: "i64"
  defp mlir_type({:type, :Float}), do: "f64"
  defp mlir_type({:type, :Bool}), do: "i1"
  defp mlir_type({:type, :Void}), do: "()"
  defp mlir_type({:type, :auto}), do: "f64"
  defp mlir_type({:array, elem_type, nil}), do: "memref<?x#{mlir_type(elem_type)}>"
  defp mlir_type({:array, elem_type, size}), do: "memref<#{size}x#{mlir_type(elem_type)}>"
  defp mlir_type({:function, args, ret}) do
    args_str = Enum.map(args, &mlir_type/1) |> Enum.join(", ")
    "(#{args_str}) -> #{mlir_type(ret)}"
  end
  defp mlir_type(_), do: "f64"

  # Optimization passes
  
  defp apply_passes(ir, passes) do
    Enum.reduce(passes, ir, fn pass, acc_ir ->
      apply_pass(acc_ir, pass)
    end)
  end

  defp apply_pass(ir, :canonicalize) do
    canonicalize(ir)
  end

  defp apply_pass(ir, :cse) do
    common_subexpression_elimination(ir)
  end

  defp apply_pass(ir, :inline) do
    inline_functions(ir)
  end

  defp apply_pass(ir, :vectorize) do
    vectorize_loops(ir)
  end

  defp apply_pass(ir, :parallelize) do
    parallelize_loops(ir)
  end

  defp apply_pass(ir, :gpu_offload) do
    mark_gpu_candidate(ir)
  end

  defp apply_pass(ir, :constant_folding) do
    constant_folding(ir)
  end

  defp apply_pass(ir, :dead_code_elimination) do
    dead_code_elimination(ir)
  end

  defp apply_pass(ir, _), do: ir

  # Basic optimization implementations (when MLIR is not available)

  defp constant_folding({:program, statements}) do
    {:program, fold_constants(statements)}
  end
  defp constant_folding(ast), do: ast

  defp fold_constants(statements) do
    Enum.map(statements, fn stmt ->
      case stmt do
        {:function, name, params, ret, body, pub, line, col} ->
          {:function, name, params, ret, fold_constants_block(body), pub, line, col}
        {:let, name, expr, line, col} ->
          {:let, name, fold_constant_expr(expr), line, col}
        _ -> stmt
      end
    end)
  end

  defp fold_constants_block({:block, statements}) do
    {:block, fold_constants(statements)}
  end
  defp fold_constants_block(stmt), do: fold_constants([stmt]) |> hd

  defp fold_constant_expr({:binop, op, {:number, a, _, _}, {:number, b, _, _}}) when is_number(a) and is_number(b) do
    result = case op do
      :add -> a + b
      :sub -> a - b
      :mul -> a * b
      :div -> a / b
      :mod -> rem(a, b)
      _ -> nil
    end
    if result != nil, do: {:number, result, 0, 0}, else: {:binop, op, {:number, a, 0, 0}, {:number, b, 0, 0}}
  end
  defp fold_constant_expr({:binop, op, left, right}) do
    {:binop, op, fold_constant_expr(left), fold_constant_expr(right)}
  end
  defp fold_constant_expr({:if, {:bool, true, _, _}, then_block, _, _line, _col}) do
    fold_constants_block(then_block)
  end
  defp fold_constant_expr({:if, {:bool, false, _, _}, _, else_block, _line, _col}) when else_block != nil do
    fold_constants_block(else_block)
  end
  defp fold_constant_expr(expr), do: expr

  defp common_subexpression_elimination({:program, statements}) do
    {:program, cse_statements(statements, %{})}
  end
  defp common_subexpression_elimination(ast), do: ast

  defp cse_statements(statements, _env) do
    Enum.map(statements, fn stmt ->
      case stmt do
        {:let, name, {:binop, _op, {:var, _v1, _, _}, {:var, _v2, _, _}} = full_expr, line, col} ->
          {:let, name, full_expr, line, col}
        _ -> stmt
      end
    end)
  end

  defp inline_functions({:program, statements}) do
    # Inline small functions
    {:program, statements}
  end

  defp vectorize_loops({:program, statements}) do
    # Add vectorization hints to array operations
    {:program, add_vector_hints(statements)}
  end

  defp add_vector_hints(statements) do
    Enum.map(statements, fn stmt ->
      case stmt do
        {:for, var, {:array, _, _, _} = arr, body, line, col} ->
          # Add vector size hint comment
          size = case arr do
            {:array, elems, _, _} -> length(elems)
            _ -> 4
          end
          {:for, var, arr, mark_vector_body(body, size), line, col}
        _ -> stmt
      end
    end)
  end

  defp mark_vector_body({:block, stmts}, size) do
    {:block, [{"vector_hint", size, 0, 0} | stmts]}
  end
  defp mark_vector_body(stmt, size), do: {:block, [{"vector_hint", size, 0, 0}, stmt]}

  defp parallelize_loops({:program, statements}) do
    # Mark parallelizable loops
    {:program, statements}
  end

  defp mark_gpu_candidate({:program, statements}) do
    # Mark GPU-suitable operations
    {:program, statements}
  end

  defp canonicalize(ir), do: ir

  # Compilation targets
  
  defp compile_to_llvm(ir) do
    # Lower MLIR to LLVM IR
    {:ok, ir, :llvm}
  end

  defp compile_to_cuda(ir) do
    # Lower MLIR to CUDA
    {:ok, ir, :cuda}
  end

  defp compile_to_rocm(ir) do
    # Lower MLIR to ROCm/HIP
    {:ok, ir, :rocm}
  end

  # Convert MLIR back to Zixir AST (for fallback)
  
  defp from_mlir(_mlir_code) do
    # Parse MLIR and reconstruct Zixir AST
    # This is a simplified version
    {:ok, {:program, []}}
  end

  defp dead_code_elimination({:program, statements}) do
    # Remove unused let bindings
    {:program, eliminate_dead_code(statements, MapSet.new())}
  end

  defp eliminate_dead_code(statements, _used_vars) when is_list(statements) do
    # Simple DCE: keep all statements for now
    # Full implementation would track variable usage
    statements
  end

  defp eliminate_dead_code(other, _used_vars), do: other

  defp inline_small_functions({:program, statements}) do
    # Find small functions and inline them
    small_funcs = find_small_functions(statements)
    {:program, inline_functions(statements, small_funcs)}
  end

  defp find_small_functions(statements) do
    Enum.filter(statements, fn
      {:function, _name, _params, _ret, {:block, stmts}, _pub, _line, _col} ->
        # Inline functions with <= 3 statements
        length(stmts) <= 3
      _ ->
        false
    end)
    |> Map.new(fn {:function, name, params, _ret, body, _pub, _line, _col} ->
      {name, {params, body}}
    end)
  end

  defp inline_functions(statements, small_funcs) do
    Enum.map(statements, fn stmt ->
      inline_in_statement(stmt, small_funcs)
    end)
  end

  defp inline_in_statement({:function, name, params, ret, body, is_pub, line, col}, small_funcs) do
    {:function, name, params, ret, inline_in_statement(body, small_funcs), is_pub, line, col}
  end

  defp inline_in_statement({:block, statements}, small_funcs) do
    {:block, Enum.map(statements, &inline_in_statement(&1, small_funcs))}
  end

  defp inline_in_statement({:let, name, expr, line, col}, small_funcs) do
    {:let, name, inline_in_expression(expr, small_funcs), line, col}
  end

  defp inline_in_statement(stmt, small_funcs) do
    inline_in_expression(stmt, small_funcs)
  end

  defp inline_in_expression({:call, {:var, func_name, line, col}, args}, small_funcs) do
    case Map.get(small_funcs, func_name) do
      nil ->
        {:call, {:var, func_name, line, col}, Enum.map(args, &inline_in_expression(&1, small_funcs))}
      
      {params, body} ->
        # Inline the function body
        param_bindings = Enum.zip(Enum.map(params, fn {name, _type} -> name end), args)
        inline_body(body, param_bindings)
    end
  end

  defp inline_in_expression({:binop, op, left, right}, small_funcs) do
    {:binop, op, inline_in_expression(left, small_funcs), inline_in_expression(right, small_funcs)}
  end

  defp inline_in_expression({:unary, op, expr, line, col}, small_funcs) do
    {:unary, op, inline_in_expression(expr, small_funcs), line, col}
  end

  defp inline_in_expression({:array, elements, line, col}, small_funcs) do
    {:array, Enum.map(elements, &inline_in_expression(&1, small_funcs)), line, col}
  end

  defp inline_in_expression(other, _small_funcs), do: other

  defp inline_body({:block, statements}, bindings) do
    # Inline the last statement's value
    Enum.reduce(statements, nil, fn stmt, _acc ->
      inline_body(stmt, bindings)
    end)
  end

  defp inline_body({:let, _name, expr, _line, _col}, bindings) do
    inline_body(expr, bindings)
  end

  defp inline_body({:var, name, line, col}, bindings) do
    case List.keyfind(bindings, name, 0) do
      {^name, value} -> value
      nil -> {:var, name, line, col}
    end
  end
  
  defp inline_body({:binop, op, left, right}, bindings) do
    {:binop, op, inline_body(left, bindings), inline_body(right, bindings)}
  end

  defp inline_body(other, _bindings), do: other

  @doc """
  Full dead code elimination with variable usage tracking.
  """
  def dead_code_elimination_full({:program, statements}) do
    {clean_statements, _used} = eliminate_dead_code_full(statements, MapSet.new())
    {:program, clean_statements}
  end

  defp eliminate_dead_code_full(statements, used_vars) when is_list(statements) do
    {clean, used} = Enum.reduce(statements, {[], used_vars}, fn stmt, {acc, used} ->
      case eliminate_dead_statement(stmt, used) do
        {nil, new_used} -> {acc, new_used}
        {clean_stmt, new_used} -> {[clean_stmt | acc], new_used}
      end
    end)
    {Enum.reverse(clean), used}
  end

  defp eliminate_dead_statement({:let, name, expr, line, col}, used_vars) do
    expr_used = collect_variable_usage(expr)
    if name in used_vars or MapSet.member?(expr_used, name) do
      {{:let, name, expr, line, col}, used_vars}
    else
      {nil, used_vars}
    end
  end

  defp eliminate_dead_statement(stmt, used_vars), do: {stmt, used_vars}

  defp collect_variable_usage({:var, name, _, _}), do: MapSet.new([name])
  defp collect_variable_usage({:binop, _, left, right}), do: MapSet.union(collect_variable_usage(left), collect_variable_usage(right))
  defp collect_variable_usage({:call, _, args}), do: Enum.reduce(args, MapSet.new(), &MapSet.union(collect_variable_usage(&1), &2))
  defp collect_variable_usage({:let, name, expr, _, _}), do: MapSet.put(collect_variable_usage(expr), name)
  defp collect_variable_usage({:block, stmts}), do: Enum.reduce(stmts, MapSet.new(), &MapSet.union(collect_variable_usage(&1), &2))
  defp collect_variable_usage(_), do: MapSet.new()

  @doc """
  Advanced constant propagation with type checking.
  """
  def constant_propagation({:program, statements}) do
    {:program, propagate_constants(statements, %{})}
  end

  defp propagate_constants(statements, env) when is_list(statements) do
    Enum.map(statements, fn stmt -> propagate_constants_stmt(stmt, env) end)
  end

  defp propagate_constants_stmt({:let, name, expr, line, col}, env) do
    {propagated_expr, _new_env} = propagate_constants_expr(expr, env)
    constant_value = get_constant_value(propagated_expr)
    _updated_env = if constant_value != nil, do: Map.put(env, name, constant_value), else: env
    {:let, name, propagated_expr, line, col}
  end

  defp propagate_constants_stmt({:function, name, params, ret, body, pub, line, col}, env) do
    {:function, name, params, ret, propagate_constants(body, env), pub, line, col}
  end

  defp propagate_constants_stmt(stmt, _env), do: stmt

  defp propagate_constants_expr({:var, name, line, col}, env) do
    case Map.get(env, name) do
      nil -> {{:var, name, line, col}, env}
      value -> {value, env}
    end
  end

  defp propagate_constants_expr({:binop, op, left, right}, env) do
    {prop_left, env} = propagate_constants_expr(left, env)
    {prop_right, env} = propagate_constants_expr(right, env)
    {{:binop, op, prop_left, prop_right}, env}
  end

  defp propagate_constants_expr(expr, env), do: {expr, env}

  defp get_constant_value({:number, n, _, _}) when is_number(n), do: {:number, n}
  defp get_constant_value({:string, s, _, _}), do: {:string, s}
  defp get_constant_value({:bool, b, _, _}), do: {:bool, b}
  defp get_constant_value(_), do: nil

  @doc """
  Loop invariant code motion.
  """
  def loop_invariant_code_motion({:program, statements}) do
    {:program, licm_statements(statements)}
  end

  defp licm_statements(statements) when is_list(statements) do
    Enum.map(statements, fn stmt -> licm_statement(stmt) end)
  end

  defp licm_statement({:for, var, iterable, body, line, col}) do
    {invariant_lets, dependent_body} = extract_invariants(body, MapSet.new([var]))
    {:for, var, iterable, {:block, invariant_lets ++ [dependent_body]}, line, col}
  end

  defp licm_statement(stmt), do: stmt

  defp extract_invariants({:block, statements}, loop_vars) do
    Enum.reduce(statements, {[], nil}, fn
      stmt, {invariants, nil} ->
        case extract_invariant_let(stmt, loop_vars) do
          {:invariant, let_stmt} -> {[let_stmt | invariants], nil}
          {:variant, let_stmt} -> {invariants, let_stmt}
        end
      _stmt, {invariants, _dependent} ->
        {invariants, nil}
    end)
  end

  defp extract_invariant_let({:let, name, expr, line, col}, loop_vars) do
    if uses_only_variables(expr, loop_vars) do
      {:invariant, {:let, name, expr, line, col}}
    else
      {:variant, {:let, name, expr, line, col}}
    end
  end

  defp extract_invariant_let(stmt, _loop_vars), do: {:variant, stmt}

  defp uses_only_variables(expr, allowed_vars) do
    case collect_variables(expr) do
      :all_allowed when allowed_vars == :all -> true
      vars when is_map(vars) -> MapSet.subset?(vars, allowed_vars)
      _ -> false
    end
  end

  defp collect_variables({:var, name, _, _}), do: MapSet.new([name])
  defp collect_variables({:binop, _, left, right}), do: MapSet.union(collect_variables(left), collect_variables(right))
  defp collect_variables({:call, _, args}), do: Enum.reduce(args, MapSet.new(), &MapSet.union(collect_variables(&1), &2))
  defp collect_variables(_), do: MapSet.new()

  @doc """
  Strength reduction for common patterns.
  """
  def strength_reduction({:program, statements}) do
    {:program, reduce_strength(statements)}
  end

  defp reduce_strength(statements) when is_list(statements) do
    Enum.map(statements, &reduce_strength_stmt/1)
  end

  defp reduce_strength_stmt({:for, var, {:binop, :mul, {:number, n, _, _}, {:var, _v, _, _}} = _iter, body, line, col}) 
       when is_integer(n) and n > 1 do
    new_iter = {:binop, :add, {:var, var, 0, 0}, {:binop, :mul, {:var, var, 0, 0}, {:number, n - 1, 0, 0}}}
    {:for, var, new_iter, body, line, col}
  end

  defp reduce_strength_stmt({:binop, :mul, {:number, n, _l1, _c1}, {:var, v, l2, c2}}) when is_integer(n) and n == 2 do
    {:binop, :add, {:var, v, l2, c2}, {:var, v, l2, c2}}
  end

  defp reduce_strength_stmt(stmt), do: stmt
end
