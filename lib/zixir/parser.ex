defmodule Zixir.Parser do
  @moduledoc """
  Parser for Zixir source. Produces AST (Zixir.AST.*). Uses NimbleParsec; tracks line/column for errors.
  """

  import NimbleParsec

  @doc "Parse Zixir source string. Returns {:ok, ast} or {:error, Zixir.CompileError}."
  def parse(source) when is_binary(source) do
    case parse_program(source) do
      {:ok, ast, _rest, _ctx, _line, _col} -> 
        # NimbleParsec reduce wraps result in a list, so unwrap it
        ast = if is_list(ast) and length(ast) == 1, do: hd(ast), else: ast
        {:ok, ast}
      {:error, rest, context, line, col, _} ->
        {:error,
         %Zixir.CompileError{
           message: "parse error",
           line: line,
           column: col,
           rest: rest,
           context: context
         }}
    end
  end

  # Whitespace and comments
  defcombinatorp :ws, repeat(choice([string(" "), string("\t"), string("\n"), string("\r")]))
  defcombinatorp :ws1, times(choice([string(" "), string("\t"), string("\n"), string("\r")]), min: 1)
  defcombinatorp :comment, ignore(string("#")) |> ignore(repeat(utf8_char([not: ?\n])))
  defcombinatorp :ws_comment, repeat(choice([parsec(:ws1), parsec(:comment)]))
  defcombinatorp :opt_ws, optional(parsec(:ws_comment))

  # Primitives (integer returns [value, base]; we need first element only)
  defcombinatorp :integer, integer(min: 1) |> map({__MODULE__, :map_integer, []})
  defcombinatorp :float,
    integer(min: 1) |> map({__MODULE__, :map_integer, []})
    |> string(".")
    |> integer(min: 1) |> map({__MODULE__, :map_integer, []})
    |> reduce({__MODULE__, :reduce_float, []})

  defcombinatorp :number,
    choice([parsec(:float), parsec(:integer)])
    |> reduce({__MODULE__, :reduce_number, []})

  defcombinatorp :string_content, repeat(choice([utf8_char([not: ?"]), string("\\\"")]))
  defcombinatorp :string_lit,
    ignore(string("\""))
    |> concat(parsec(:string_content))
    |> ignore(string("\""))
    |> reduce({List, :to_string, []})
    |> map({__MODULE__, :map_string, []})

  defcombinatorp :identifier,
    ascii_string([?a..?z, ?A..?Z, ?_], min: 1)
    |> optional(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1))
    |> reduce({List, :to_string, []})

  # Expressions (avoid left-recursion: term then binop chain)
  defcombinatorp :expr_list, parsec(:expr) |> repeat(ignore(string(",")) |> parsec(:opt_ws) |> parsec(:expr))

  defcombinatorp :list_lit,
    ignore(string("["))
    |> parsec(:opt_ws)
    |> optional(parsec(:expr_list))
    |> parsec(:opt_ws)
    |> ignore(string("]"))
    |> reduce({__MODULE__, :reduce_list_lit, []})

  defcombinatorp :map_pair,
    parsec(:string_lit)
    |> parsec(:opt_ws)
    |> ignore(string(":"))
    |> parsec(:opt_ws)
    |> parsec(:expr)
    |> reduce({__MODULE__, :reduce_map_pair, []})

  defcombinatorp :map_lit,
    ignore(string("{"))
    |> parsec(:opt_ws)
    |> optional(parsec(:map_pair) |> repeat(parsec(:opt_ws) |> ignore(string(",")) |> parsec(:opt_ws) |> parsec(:map_pair)))
    |> parsec(:opt_ws)
    |> ignore(string("}"))
    |> reduce({__MODULE__, :reduce_map_lit, []})

  defcombinatorp :term,
    choice([
      parsec(:number),
      parsec(:string_lit),
      parsec(:list_lit),
      parsec(:map_lit),
      # engine.op(args)
      ignore(string("engine"))
      |> parsec(:ws_comment)
      |> ignore(string("."))
      |> parsec(:opt_ws)
      |> parsec(:identifier)
      |> parsec(:opt_ws)
      |> ignore(string("("))
      |> parsec(:opt_ws)
      |> optional(parsec(:expr_list))
      |> parsec(:opt_ws)
      |> ignore(string(")"))
      |> reduce({__MODULE__, :reduce_engine_call, []}),
      # python "mod" "func" (args)
      ignore(string("python"))
      |> parsec(:ws_comment)
      |> parsec(:string_lit)
      |> parsec(:opt_ws)
      |> parsec(:string_lit)
      |> parsec(:opt_ws)
      |> ignore(string("("))
      |> parsec(:opt_ws)
      |> optional(parsec(:expr_list))
      |> parsec(:opt_ws)
      |> ignore(string(")"))
      |> reduce({__MODULE__, :reduce_python_call, []}),
      # ( expr )
      ignore(string("(")) |> parsec(:opt_ws) |> parsec(:expr) |> parsec(:opt_ws) |> ignore(string(")")),
      # identifier
      parsec(:identifier) |> map({__MODULE__, :map_var, []})
    ])

  defcombinatorp :binop,
    parsec(:opt_ws)
    |> choice([string("+"), string("-"), string("*"), string("/")])
    |> parsec(:opt_ws)
    |> reduce({__MODULE__, :reduce_binop, []})

  defcombinatorp :expr,
    parsec(:term)
    |> repeat(parsec(:binop) |> parsec(:term))
    |> reduce(:fold_binop)

  def reduce_binop(list) do
    # Extract the operator from [ws, op, ws]
    case filter_ws(list) do
      [op] when is_binary(op) -> op
      _ -> "+"  # default
    end
  end

  defp fold_binop([single]), do: single
  defp fold_binop([left, op, right | rest]) when is_binary(op) do
    fold_binop([{:binop, op, left, right} | rest])
  end

  # Statement: let id = expr  or  expr
  defcombinatorp :let_stmt,
    ignore(string("let"))
    |> parsec(:ws_comment)
    |> parsec(:identifier)
    |> parsec(:opt_ws)
    |> ignore(string("="))
    |> parsec(:opt_ws)
    |> parsec(:expr)
    |> reduce({__MODULE__, :reduce_let, []})

  defcombinatorp :stmt,
    choice([
      parsec(:let_stmt),
      parsec(:expr)
    ])

  defcombinatorp :program,
    parsec(:opt_ws)
    |> repeat(parsec(:stmt) |> parsec(:opt_ws) |> optional(ignore(string(";")) |> parsec(:opt_ws)))
    |> parsec(:opt_ws)
    |> eos()
    |> reduce({__MODULE__, :reduce_program, []})

  defparsec :parse_program, parsec(:program)

  # Public so NimbleParsec-generated code can call via MFA.
  def map_integer([n, _base]) when is_integer(n), do: n
  def map_integer(n) when is_integer(n), do: n

  # NimbleParsec map is per-element; float needs the full [a, ".", b] so we use reduce.
  # Use apply/3 so return type is not inferred as float() and cond branches are valid.
  def reduce_float([a, _dot, b]) when is_number(a) and is_number(b) do
    result = apply(String, :to_float, ["#{a}.#{b}"])
    cond do
      is_tuple(result) and tuple_size(result) == 2 -> elem(result, 0)
      result == :error -> a + b / 10
      true -> result
    end
  end
  def reduce_float([n]) when is_number(n), do: n
  def reduce_float(n) when is_number(n), do: n

  def reduce_number([n, _base]) when is_integer(n), do: {:number, n}
  def reduce_number([n]) when is_number(n), do: {:number, n}
  def map_string(s), do: {:string, s}

  # Helper to filter out whitespace strings from parser results
  defp filter_ws(list) when is_list(list) do
    Enum.reject(list, fn
      s when is_binary(s) -> String.trim(s) == ""
      _ -> false
    end)
  end
  defp filter_ws(nil), do: []
  defp filter_ws(other), do: [other]

  def reduce_list_lit(list) do
    case filter_ws(list) do
      [] -> []
      items -> items
    end
  end

  def reduce_map_pair(list) do
    case filter_ws(list) do
      [{:string, k}, v] -> {k, v}
      _ -> nil
    end
  end

  def reduce_map_lit(list) do
    pairs = filter_ws(list) |> Enum.reject(&is_nil/1)
    case pairs do
      [] -> %{}
      items -> Map.new(items)
    end
  end

  def reduce_engine_call(list) do
    case filter_ws(list) do
      [op | args] when args != [] -> {:engine_call, op, args}
      [op] -> {:engine_call, op, []}
    end
  end

  def reduce_python_call(list) do
    case filter_ws(list) do
      [{:string, m}, {:string, f}, args] -> {:python_call, m, f, args || []}
      [{:string, m}, {:string, f}] -> {:python_call, m, f, []}
    end
  end

  def map_var(id), do: {:var, id}

  def reduce_let(list) do
    case filter_ws(list) do
      [id, e] -> {:let, id, e}
      items when length(items) >= 2 -> 
        # Last item is the expression, everything before that filtered is the id
        e = List.last(items)
        id = Enum.at(items, length(items) - 2)
        {:let, id, e}
    end
  end

  def reduce_program(stmts) when is_list(stmts) do
    filtered = filter_ws(stmts) |> Enum.reject(&is_nil/1)
    {:program, filtered, {1, 1}}
  end
  def reduce_program(single) do
    {:program, [single], {1, 1}}
  end
end
