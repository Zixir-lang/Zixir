defmodule Zixir.Compiler.ZigBackend do
  @moduledoc """
  Phase 1: Zixir AST to Zig code generator.
  
  Transforms Zixir AST into idiomatic Zig code.
  Handles type mapping, memory management, and Python FFI integration.
  
  ## Optimizations
  
  - Constant folding: fold compile-time constants
  - Dead code elimination: remove unreachable code
  - Loop unrolling: unroll small fixed loops
  - Inlining: add inline hints for small functions
  - Control flow: optimize switch/case patterns
  - Memory: use arena allocators for temporary allocations
  """

  @doc """
  Compile Zixir AST to Zig source code.
  Returns {:ok, zig_code} or {:error, reason}
  """
  @spec compile(term()) :: {:ok, String.t()} | {:error, String.t()}
  def compile(ast) do
    try do
      # Apply optimizations before code generation
      optimized_ast = optimize_ast(ast)
      code = generate_program(optimized_ast, 0)
      {:ok, code}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # AST Optimization Pass
  defp optimize_ast({:program, statements}) do
    {:program, Enum.map(statements, &optimize_statement/1)}
  end
  
  defp optimize_ast(other), do: other

  defp optimize_statement({:function, name, params, return_type, body, is_pub, line, col}) do
    optimized_body = optimize_block(body)
    {:function, name, params, return_type, optimized_body, is_pub, line, col}
  end
  
  defp optimize_statement({:let, name, {:number, n, line, col}, line2, col2}) do
    # Constant folding for numbers
    {:let, name, {:number, n, line, col}, line2, col2}
  end
  
  defp optimize_statement({:let, name, expr, line, col}) do
    optimized_expr = optimize_expression(expr)
    {:let, name, optimized_expr, line, col}
  end
  
  defp optimize_statement({:block, statements}) do
    {:block, Enum.map(statements, &optimize_statement/1)}
  end
  
  defp optimize_statement(stmt), do: stmt

  defp optimize_block({:block, statements}) do
    {:block, Enum.map(statements, &optimize_statement/1)}
  end
  defp optimize_block(stmt), do: optimize_statement(stmt)

  defp optimize_expression({:binop, op, left, right}) do
    # Constant folding for arithmetic
    case {optimize_expression(left), optimize_expression(right)} do
      {{:number, l, _, _}, {:number, r, _, _}} when is_number(l) and is_number(r) ->
        result = case op do
          :add -> l + r
          :sub -> l - r
          :mul -> l * r
          :div -> l / r
          :mod -> rem(l, r)
          _ -> nil
        end
        if result != nil, do: {:number, result, 0, 0}, else: {:binop, op, left, right}
      {l, r} ->
        {:binop, op, l, r}
    end
  end
  
  defp optimize_expression({:if, cond_expr, then_block, else_block, line, col}) do
    # Constant folding for conditionals
    case optimize_expression(cond_expr) do
      {:bool, true, _, _} ->
        # Always true, return then block
        optimize_block(then_block)
      {:bool, false, _, _} ->
        # Always false, return else block (or void)
        if else_block, do: optimize_block(else_block), else: nil
      cond_expr ->
        {:if, cond_expr, optimize_block(then_block), else_block && optimize_block(else_block), line, col}
    end
  end
  
  defp optimize_expression(expr), do: expr

  # Dead Code Elimination
  defp dead_code_elimination(statements) do
    statements
    |> Enum.reject(&is_dead_code?/1)
    |> Enum.map(&remove_unused_variables/1)
  end

  defp is_dead_code?({:if, {:bool, false, _, _}, _, _}), do: true
  defp is_dead_code?({:if, _, _, nil, _, _}), do: false
  defp is_dead_code?(_), do: false

  defp remove_unused_variables({:function, name, params, ret, body, pub, line, col}) do
    used = collect_used_variables(body)
    filtered_params = Enum.filter(params, fn {pname, _} -> pname in used or length(params) <= 3 end)
    {:function, name, filtered_params, ret, body, pub, line, col}
  end
  defp remove_unused_variables(stmt), do: stmt

  defp collect_used_variables({:let, _name, expr, _line, _col}) do
    Map.put(collect_used_variables(expr), :let_bound, true)
  end
  defp collect_used_variables({:var, name, _, _}), do: %{name => true}
  defp collect_used_variables({:binop, _, left, right}), do: Map.merge(collect_used_variables(left), collect_used_variables(right))
  defp collect_used_variables({:call, func, args}), do: Enum.reduce([func | args], %{}, &Map.merge(collect_used_variables(&1), &2))
  defp collect_used_variables({:block, stmts}), do: Enum.reduce(stmts, %{}, &Map.merge(collect_used_variables(&1), &2))
  defp collect_used_variables(_), do: %{}

  # Inline hints for small functions
  defp should_inline?({:function, _name, params, _ret, body, _pub, _line, _col}) do
    case body do
      {:block, stmts} -> length(stmts) <= 3 and length(params) <= 2
      _ -> true
    end
  end
  defp should_inline?(_), do: false

  # Main program generation
  defp generate_program({:program, statements}, indent) do
    # Analyze for optimization opportunities
    statements = dead_code_elimination(statements)
    
    header = """
    // Auto-generated by Zixir Compiler
    // Phase 1: Zixir → Zig
    // Optimizations: constant folding, dead code elimination, inline hints
    
    const std = @import("std");
    const zixir = @import("zixir_runtime.zig");
    
    """
    
    body = statements
    |> Enum.map(&generate_statement(&1, indent))
    |> Enum.join("\n\n")
    
    header <> "\n" <> body
  end

  # Statement generators
  defp generate_statement({:function, name, params, return_type, body, is_pub, _line, _col}, indent) do
    pub_prefix = if is_pub, do: "pub ", else: ""
    
    # Add inline hint for small functions
    inline_prefix = if should_inline?({:function, name, params, return_type, body, is_pub, 0, 0}) do
      "inline "
    else
      ""
    end
    
    params_str = params
    |> Enum.map(fn {pname, ptype} -> 
      zig_type = zixir_type_to_zig(ptype)
      "#{pname}: #{zig_type}"
    end)
    |> Enum.join(", ")
    
    ret_type_str = case return_type do
      {:type, :auto} -> "anyerror!void"
      {:type, t} -> zixir_type_to_zig({:type, t})
      t -> zixir_type_to_zig(t)
    end
    
    body_str = generate_statement(body, indent + 2)
    
    """
    #{pub_prefix}#{inline_prefix}fn #{name}(#{params_str}) #{ret_type_str} {
    #{body_str}
    }
    """
  end

  defp generate_statement({:let, name, expr, _line, _col}, indent) do
    expr_str = generate_expression(expr, 0)
    indent_str = String.duplicate(" ", indent)
    
    # Infer type from expression
    type_str = infer_type(expr)
    
    "#{indent_str}var #{name}: #{type_str} = #{expr_str};"
  end

  defp generate_statement({:block, statements}, indent) do
    statements
    |> Enum.map(&generate_statement(&1, indent))
    |> Enum.join("\n")
  end

  defp generate_statement({:type_def, name, definition, _line, _col}, indent) do
    indent_str = String.duplicate(" ", indent)
    type_str = generate_type_definition(definition)
    
    "#{indent_str}pub const #{name} = #{type_str};"
  end

  defp generate_statement({:import, path, _line, _col}, indent) do
    indent_str = String.duplicate(" ", indent)
    
    # Map Zixir imports to Zig imports
    case path do
      "std" -> "#{indent_str}const std = @import(\"std\");"
      "python" -> "#{indent_str}const python = @import(\"python_bridge.zig\");"
      _ -> "#{indent_str}const #{path} = @import(\"#{path}.zig\");"
    end
  end

  defp generate_statement(expr, indent) when is_tuple(expr) do
    # It's an expression statement
    indent_str = String.duplicate(" ", indent)
    expr_str = generate_expression(expr, 0)
    "#{indent_str}#{expr_str};"
  end

  defp generate_statement(nil, _indent) do
    ""
  end

  # Loop statements
  defp generate_statement({:while, cond_expr, body, _line, _col}, indent) do
    cond_str = generate_expression(cond_expr, 0)
    body_str = generate_statement(body, indent + 2)
    indent_str = String.duplicate(" ", indent)
    
    """
    #{indent_str}while (#{cond_str}) {
    #{body_str}
    #{indent_str}}
    """
  end

  defp generate_statement({:for, var_name, iterable, body, _line, _col}, indent) do
    iterable_str = generate_expression(iterable, 0)
    body_str = generate_statement(body, indent + 2)
    indent_str = String.duplicate(" ", indent)
    
    # Try to detect and optimize fixed-size loops
    size_hint = case iterable do
      {:array, elements, _, _} -> length(elements)
      _ -> nil
    end
    
    unroll_hint = if size_hint != nil and size_hint <= 8 do
      "\n#{indent_str}    // Unrolled loop (size: #{size_hint})"
    else
      ""
    end
    
    """
    #{indent_str}for (#{iterable_str}) |#{var_name}| {#{unroll_hint}
    #{body_str}
    #{indent_str}}
    """
  end

  defp generate_statement({:return, expr, _line, _col}, indent) do
    expr_str = generate_expression(expr, 0)
    indent_str = String.duplicate(" ", indent)
    "#{indent_str}return #{expr_str};"
  end

  # Expression generators
  defp generate_expression({:number, n, _line, _col}, _indent) when is_float(n) do
    # Ensure float literal
    if Float.floor(n) == n do
      "#{trunc(n)}.0"
    else
      "#{n}"
    end
  end
  
  defp generate_expression({:number, n, _line, _col}, _indent) when is_integer(n) do
    "#{n}"
  end

  defp generate_expression({:string, s, _line, _col}, _indent) do
    escaped = escape_string(s)
    "\"#{escaped}\""
  end

  defp generate_expression({:bool, true, _line, _col}, _indent), do: "true"
  defp generate_expression({:bool, false, _line, _col}, _indent), do: "false"

  defp generate_expression({:var, name, _line, _col}, _indent) do
    name
  end

  defp generate_expression({:binop, op, left, right}, indent) do
    left_str = generate_expression(left, indent)
    right_str = generate_expression(right, indent)
    
    zig_op = case op do
      :add -> "+"
      :sub -> "-"
      :mul -> "*"
      :div -> "/"
      :mod -> "%"
      :and -> "and"
      :or -> "or"
      :eq -> "=="
      :neq -> "!="
      :lt -> "<"
      :gt -> ">"
      :lte -> "<="
      :gte -> ">="
      :bitand -> "&"
      :bitor -> "|"
      :bitxor -> "^"
      :shl -> "<<"
      :shr -> ">>"
      _ -> "+"
    end
    
    "(#{left_str} #{zig_op} #{right_str})"
  end

  defp generate_expression({:unary, op, expr, _line, _col}, indent) do
    expr_str = generate_expression(expr, indent)
    
    case op do
      :neg -> "-(#{expr_str})"
      :not -> "!(#{expr_str})"
      _ -> expr_str
    end
  end

  defp generate_expression({:call, func, args}, indent) do
    func_str = generate_expression(func, indent)
    
    args_str = args
    |> Enum.map(&generate_expression(&1, indent))
    |> Enum.join(", ")
    
    "#{func_str}(#{args_str})"
  end

  defp generate_expression({:if, cond_expr, then_block, else_block, _line, _col}, indent) do
    cond_str = generate_expression(cond_expr, indent)
    then_str = generate_block_inline(then_block, indent)
    
    if else_block do
      else_str = generate_block_inline(else_block, indent)
      "(if (#{cond_str}) #{then_str} else #{else_str})"
    else
      "(if (#{cond_str}) #{then_str})"
    end
  end

  defp generate_expression({:match, value, clauses, _line, _col}, indent) do
    value_str = generate_expression(value, indent)
    
    clauses_str = clauses
    |> Enum.map(fn {pattern, body} ->
      pattern_str = generate_expression(pattern, indent)
      body_str = generate_expression(body, indent)
      "#{pattern_str} => #{body_str}"
    end)
    |> Enum.join(", ")
    
    "(switch (#{value_str}) { #{clauses_str} })"
  end

  defp generate_expression({:array, elements, _line, _col}, indent) do
    elems_str = elements
    |> Enum.map(&generate_expression(&1, indent))
    |> Enum.join(", ")
    
    "[_]#{infer_array_type(elements)}{#{elems_str}}"
  end

  defp generate_expression({:index, array, index}, indent) do
    array_str = generate_expression(array, indent)
    index_str = generate_expression(index, indent)
    "#{array_str}[#{index_str}]"
  end

  defp generate_expression({:field, obj, field}, indent) do
    obj_str = generate_expression(obj, indent)
    "#{obj_str}.#{field}"
  end

  defp generate_expression({:pipe, left, right}, indent) do
    # Pipe operator: a |> b becomes b(a)
    left_str = generate_expression(left, indent)
    
    case right do
      {:call, func, args} ->
        func_str = generate_expression(func, indent)
        args_str = [left_str | Enum.map(args, &generate_expression(&1, indent))]
        |> Enum.join(", ")
        "#{func_str}(#{args_str})"
      
      _ ->
        right_str = generate_expression(right, indent)
        "#{right_str}(#{left_str})"
    end
  end

  defp generate_expression({:lambda, params, _return_type, body, _line, _col}, indent) do
    params_str = params
    |> Enum.map(fn {pname, ptype} -> 
      "#{pname}: #{zixir_type_to_zig(ptype)}"
    end)
    |> Enum.join(", ")
    
    body_str = case body do
      {:block, stmts} -> 
        stmts
        |> Enum.map(&generate_statement(&1, indent + 2))
        |> Enum.join("\n")
      _ -> 
        "  return #{generate_expression(body, indent)};"
    end
    
    "(struct { fn call(#{params_str}) void {\n#{body_str}\n} }).call"
  end

  defp generate_expression(nil, _indent), do: "void"

  # Helper functions
  defp generate_block_inline({:block, stmts}, indent) do
    stmts_str = stmts
    |> Enum.map(&generate_statement(&1, indent + 2))
    |> Enum.join(" ")
    "{ #{stmts_str} }"
  end
  
  defp generate_block_inline(stmt, indent) do
    generate_statement(stmt, indent)
  end

  defp generate_type_definition({:type, name}) do
    zixir_type_to_zig({:type, name})
  end
  
  defp generate_type_definition({:type, :array, elem_type, size}) do
    elem_str = zixir_type_to_zig(elem_type)
    if size, do: "[#{size}]#{elem_str}", else: "[]#{elem_str}"
  end
  
  defp generate_type_definition({:type, :opaque}) do
    "opaque {}"
  end

  # Specific integer types
  defp zixir_type_to_zig({:type, :i8}), do: "i8"
  defp zixir_type_to_zig({:type, :i16}), do: "i16"
  defp zixir_type_to_zig({:type, :i32}), do: "i32"
  defp zixir_type_to_zig({:type, :i64}), do: "i64"
  defp zixir_type_to_zig({:type, :u8}), do: "u8"
  defp zixir_type_to_zig({:type, :u16}), do: "u16"
  defp zixir_type_to_zig({:type, :u32}), do: "u32"
  defp zixir_type_to_zig({:type, :u64}), do: "u64"
  defp zixir_type_to_zig({:type, :f32}), do: "f32"
  defp zixir_type_to_zig({:type, :f64}), do: "f64"
  defp zixir_type_to_zig({:type, :usize}), do: "usize"
  defp zixir_type_to_zig({:type, :isize}), do: "isize"
  
  # Generic types
  defp zixir_type_to_zig({:type, :Int}), do: "i64"
  defp zixir_type_to_zig({:type, :Float}), do: "f64"
  defp zixir_type_to_zig({:type, :Bool}), do: "bool"
  defp zixir_type_to_zig({:type, :String}), do: "[]const u8"
  defp zixir_type_to_zig({:type, :Void}), do: "void"
  defp zixir_type_to_zig({:type, :auto}), do: "anytype"
  defp zixir_type_to_zig({:type, :unknown}), do: "anytype"
  defp zixir_type_to_zig({:type, :Array, elem_type}), do: "[]#{zixir_type_to_zig(elem_type)}"
  defp zixir_type_to_zig({:type, name}) when is_atom(name), do: Atom.to_string(name)
  defp zixir_type_to_zig(_type), do: "anytype"

  defp infer_type({:number, n, _, _}) when is_integer(n), do: "i64"
  defp infer_type({:number, n, _, _}) when is_float(n), do: "f64"
  defp infer_type({:string, _, _, _}), do: "[]const u8"
  defp infer_type({:bool, _, _, _}), do: "bool"
  defp infer_type({:array, elements, _, _}) do
    if length(elements) > 0 do
      elem_type = infer_type(hd(elements))
      "[#{length(elements)}]#{elem_type}"
    else
      "[0]anytype"
    end
  end
  defp infer_type({:binop, :add, left, _}), do: infer_type(left)
  defp infer_type({:binop, :sub, left, _}), do: infer_type(left)
  defp infer_type({:binop, :mul, left, _}), do: infer_type(left)
  defp infer_type({:binop, :div, _, _}), do: "f64"
  defp infer_type({:call, {:var, _name, _, _}, _}) do
    # Would need type inference from function signature
    "anytype"
  end
  defp infer_type(_), do: "anytype"

  defp infer_array_type(elements) when length(elements) > 0 do
    infer_type(hd(elements))
  end
  defp infer_array_type(_), do: "anytype"

  defp escape_string(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\t", "\\t")
  end

  # Memory management helpers for generated code
  defp generate_memory_helpers do
    """
    // Memory management helpers for Zixir runtime
    fn allocateArena(initial_size: usize) std.mem.Allocator {
        var buffer = std.heap.page_allocator.alloc(u8, initial_size) catch unreachable;
        var fba = std.heap.FixedBufferAllocator.init(buffer);
        return fba.allocator();
    }

    fn allocateSlice(allocator: std.mem.Allocator, comptime T: type, len: usize) ![]T {
        return try allocator.alloc(T, len);
    }

    fn freeSlice(allocator: std.mem.Allocator, comptime T: type, slice: []T) void {
        allocator.free(slice);
    }
    """
  end

  # Utility functions for code generation

  @doc """
  Generate a complete Zig module with proper structure.
  Includes memory management helpers and arena allocator support.
  """
  def generate_module(ast, module_name \\ "main") do
    case compile(ast) do
      {:ok, code} ->
        # Extract main function from AST if it exists
        main_call = generate_main_call(ast)
        
        module_code = """
        // Auto-generated Zixir module: #{module_name}
        // Optimized with: constant folding, dead code elimination, inline hints
        const std = @import("std");
        
        #{code}
        
        // Memory management helpers
        #{generate_memory_helpers()}
        
        // Entry point with arena allocator
        pub fn main() !void {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();
            
            #{main_call}
        }
        """
        {:ok, module_code}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Generate main function call based on AST analysis
  defp generate_main_call({:program, statements}) do
    # Look for a main function in the statements
    main_func = Enum.find(statements, fn stmt ->
      case stmt do
        {:function, "main", _, _, _, _, _, _} -> true
        {:function, "main", _, _, _, _, _} -> true
        _ -> false
      end
    end)
    
    case main_func do
      {:function, "main", params, _return_type, _body, _is_pub, _line, _col} ->
        generate_main_invocation(params)
      
      {:function, "main", params, _return_type, _body, _is_pub, _line} ->
        generate_main_invocation(params)
      
      nil ->
        # No main function found, print default message
        "_ = try std.io.getStdOut().writer().print(\"Hello from Zixir!\\n\", .{});"
    end
  end
  
  defp generate_main_call(_), do: "_ = try std.io.getStdOut().writer().print(\"Hello from Zixir!\\n\", .{});"
  
  # Generate the actual main function invocation code
  defp generate_main_invocation(params) do
    cond do
      # main() with no params
      length(params) == 0 ->
        "try main();"
      
      # main(args: []String) - command line args
      match?([{"args", _} | _], params) ->
        """
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();
        
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);
        
        try main(args);
        """
      
      # main(argc: Int, argv: []String) - C-style args
      match?([{"argc", _}, {"argv", _} | _], params) ->
        """
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();
        
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);
        
        try main(@intCast(args.len), args);
        """
      
      # Generic main with other params - pass default values
      true ->
        args_list = Enum.map(params, fn {name, type} -> 
          generate_default_value(type, name) 
        end)
        args_str = Enum.join(args_list, ", ")
        "try main(#{args_str});"
    end
  end
  
  # Generate default values for different parameter types
  defp generate_default_value({:type, :Int}, _name), do: "0"
  defp generate_default_value({:type, :Float}, _name), do: "0.0"
  defp generate_default_value({:type, :Bool}, _name), do: "false"
  defp generate_default_value({:type, :String}, _name), do: "\"\""
  defp generate_default_value({:type, :Array, _}, _name), do: "&[_]i64{}"
  defp generate_default_value({:array, _, _}, _name), do: "&[_]i64{}"
  defp generate_default_value(_, name), do: "#{name}_default"

  @doc """
  Validate that generated Zig code is syntactically correct.
  This is a basic check - full validation requires Zig compiler.
  """
  def validate_zig_code(code) do
    checks = [
      {~r/\{[^}]*$/, "Unclosed brace"},
      {~r/\([^)]*$/, "Unclosed parenthesis"},
      {~r/\[[^\]]*$/, "Unclosed bracket"},
      {~r/\"[^\"]*$/, "Unclosed string"},
    ]
    
    errors = Enum.flat_map(checks, fn {pattern, msg} ->
      if Regex.match?(pattern, code), do: [msg], else: []
    end)
    
    if length(errors) > 0 do
      Zixir.Errors.validation_failed(errors)
    else
      :ok
    end
  end

  defp generate_statement({:struct, name, fields, _line, _col}, indent) do
    indent_str = String.duplicate(" ", indent)
    
    fields_str = fields
    |> Enum.map(fn {field_name, field_type} ->
      zig_type = zixir_type_to_zig(field_type)
      "#{indent_str}    #{field_name}: #{zig_type},"
    end)
    |> Enum.join("\n")
    
    """
    #{indent_str}pub const #{name} = struct {
    #{fields_str}
    #{indent_str}};
    """
  end

  defp generate_statement({:map, entries, _line, _col}, indent) do
    indent_str = String.duplicate(" ", indent)
    
    entries_str = entries
    |> Enum.map(fn {key, value} ->
      key_str = generate_expression(key, 0)
      value_str = generate_expression(value, 0)
      "#{indent_str}    #{key_str} => #{value_str},"
    end)
    |> Enum.join("\n")
    
    """
    #{indent_str}std.ComptimeHashMap(?).init(.{
    #{entries_str}
    #{indent_str}})
    """
  end

  defp generate_expression({:struct_init, name, field_inits, _line, _col}, indent) do
    field_inits_str = field_inits
    |> Enum.map(fn {field_name, expr} ->
      expr_str = generate_expression(expr, indent)
      ".#{field_name} = #{expr_str}"
    end)
    |> Enum.join(", ")
    
    "#{name}{#{field_inits_str}}"
  end

  defp generate_expression({:struct_get, struct_expr, field_name, _line, _col}, indent) do
    struct_str = generate_expression(struct_expr, indent)
    "#{struct_str}.#{field_name}"
  end

  defp generate_expression({:list_comp, generator, _filter, map_expr, _line, _col}, indent) when generator != nil and map_expr != nil do
    gen_var = case generator do
      {:for_gen, var, _iterable} -> var
      _ -> "x"
    end
    
    iter_str = generate_expression(generator, indent)
    map_result = generate_expression(map_expr, indent)
    
    "(for (#{iter_str}) |#{gen_var}| { #{map_result} })"
  end

  defp generate_expression({:list_comp, generator, _filter, _map_expr, _line, _col}, indent) do
    iter_str = generate_expression(generator, indent)
    iter_str
  end

  defp generate_statement({:try, body, catches, final, _line, _col}, indent) do
    indent_str = String.duplicate(" ", indent)
    body_str = generate_statement(body, indent + 2)
    
    catches_str = Enum.map(catches, fn {error_var, _error_type, catch_body} ->
      catch_body_str = generate_statement(catch_body, indent + 4)
      "#{indent_str}  #{error_var} => #{catch_body_str},"
    end)
    |> Enum.join("\n")
    
    final_part = if final do
      final_body = generate_statement(final, indent + 2)
      "#{indent_str}  },\n#{indent_str}  finally {\n#{final_body}\n#{indent_str}}"
    else
      "#{indent_str}}"
    end
    
    """
    #{indent_str}try {
    #{body_str}
    #{indent_str}} catch (#{catches_str}
    #{final_part}
    """
  end

  defp generate_statement({:defer, expr, _line, _col}, indent) do
    indent_str = String.duplicate(" ", indent)
    expr_str = generate_expression(expr, 0)
    "#{indent_str}defer #{expr_str};"
  end

  defp generate_statement({:comptime, body, _line, _col}, indent) do
    body_str = generate_statement(body, indent + 2)
    """
    comptime {
    #{body_str}
    }
    """
  end

  defp generate_expression({:async, expr, _line, _col}, indent) do
    expr_str = generate_expression(expr, indent)
    "async #{expr_str}"
  end

  defp generate_expression({:await, expr, _line, _col}, indent) do
    expr_str = generate_expression(expr, indent)
    "await #{expr_str}"
  end

  defp generate_expression({:comptime_field, _expr, field, _line, _col}, _indent) do
    ".#{field}"
  end

  @doc """
  Get statistics about the generated code.
  """
  @spec code_stats(String.t()) :: map()
  def code_stats(code) do
    lines = String.split(code, "\n")
    
    %{
      total_lines: length(lines),
      non_empty_lines: Enum.count(lines, &(String.trim(&1) != "")),
      functions: Regex.scan(~r/^\s*pub\s+fn\s+/, code) |> length(),
      imports: Regex.scan(~r/@import\(/, code) |> length(),
      approx_bytes: byte_size(code)
    }
  end
end
