defmodule Zixir.Parser.Unified do
  @moduledoc """
  Unified canonical parser for Zixir language.
  
  This is the single source of truth for parsing Zixir source code.
  Combines features from all previous parser implementations with:
  - Complete language support (engine calls, Python FFI, functions, etc.)
  - Robust error handling with precise line/column tracking
  - Error recovery for better developer experience
  - Clean, maintainable recursive descent architecture
  
  ## Supported Syntax
  
  - Variable bindings: `let x = 5`
  - Functions: `fn add(a: Int, b: Int) -> Int { a + b }`
  - Engine calls: `engine.list_sum([1.0, 2.0])`
  - Python FFI: `python "math" "sqrt" (16.0)`
  - Pattern matching: `match x { 1 -> "one", _ -> "other" }`
  - Control flow: if/else, while, for loops
  - Data structures: arrays `[1, 2, 3]`, maps `{"key": "value"}`
  - Async/await: `async task()`, `await future`
  """

  defmodule ParseError do
    @moduledoc "Parse error with location information"
    defexception [:message, :line, :column]

    @impl true
    def exception(opts) do
      message = opts[:message] || "Parse error"
      line = opts[:line] || 0
      column = opts[:column] || 0
      
      formatted = if line > 0 do
        "#{message} at line #{line}, column #{column}"
      else
        message
      end
      
      %__MODULE__{message: formatted, line: line, column: column}
    end
  end

  @doc """
  Parse Zixir source code into an AST.
  
  ## Returns
    - `{:ok, ast}` - Successfully parsed AST
    - `{:error, %ParseError{}}` - Parse error with location info
  
  ## Examples
  
      iex> Zixir.Parser.Unified.parse("let x = 5")
      {:ok, {:program, [{:let, "x", {:number, 5, 1, 9}, 1, 1}]}}
  """
  @spec parse(String.t()) :: {:ok, term()} | {:error, ParseError.t()}
  def parse(source) when is_binary(source) do
    try do
      tokens = tokenize(source)
      {ast, _remaining} = parse_program(tokens)
      {:ok, ast}
    rescue
      e in ParseError -> {:error, e}
    end
  end

  # ============================================================================
  # Tokenizer
  # ============================================================================

  @keywords %{
    "let" => :let,
    "const" => :const,
    "fn" => :fn,
    "pub" => :pub,
    "if" => :if,
    "else" => :else,
    "while" => :while,
    "for" => :for,
    "in" => :in,
    "match" => :match,
    "type" => :type,
    "import" => :import,
    "extern" => :extern,
    "return" => :return,
    "async" => :async,
    "await" => :await,
    "try" => :try,
    "catch" => :catch,
    "defer" => :defer,
    "comptime" => :comptime,
    "true" => {:bool, true},
    "false" => {:bool, false}
  }

  @operators %{
    "==" => :eq,
    "!=" => :neq,
    "<=" => :lte,
    ">=" => :gte,
    "++" => :concat,
    "->" => :arrow,
    "=>" => :fat_arrow,
    ".." => :range_op,
    "|>" => :|>,
    "<" => :lt,
    ">" => :gt
  }

  defp tokenize(source) do
    source
    |> String.graphemes()
    |> tokenize_impl(1, 1, [])
    |> Enum.reverse()
  end

  defp tokenize_impl([], _line, _col, acc), do: acc

  defp tokenize_impl([c | rest], line, col, acc) when c in [" ", "\t"] do
    tokenize_impl(rest, line, col + 1, acc)
  end

  defp tokenize_impl(["\n" | rest], line, _col, acc) do
    tokenize_impl(rest, line + 1, 1, acc)
  end

  defp tokenize_impl(["#" | rest], line, col, acc) do
    {rest_after, new_line, new_col} = skip_comment(rest, line, col)
    tokenize_impl(rest_after, new_line, new_col, acc)
  end

  defp tokenize_impl(["\"" | rest], line, col, acc) do
    {str, rest_after, new_line, new_col} = read_string(rest, line, col + 1, "")
    tokenize_impl(rest_after, new_line, new_col, [{:string, str, line, col} | acc])
  end

  defp tokenize_impl([c | rest], line, col, acc) when c in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    {num, rest_after, new_col} = read_number([c | rest], col)
    tokenize_impl(rest_after, line, new_col, [{:number, num, line, col} | acc])
  end

  defp tokenize_impl([c | rest], line, col, acc) 
       when (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" do
    {ident, rest_after, new_col} = read_identifier([c | rest], col)
    token = tokenize_identifier(ident, line, col)
    tokenize_impl(rest_after, line, new_col, [token | acc])
  end

  # Multi-character operators
  defp tokenize_impl([c1, c2 | rest], line, col, acc) do
    op = c1 <> c2
    if Map.has_key?(@operators, op) do
      tokenize_impl(rest, line, col + 2, [{:op, @operators[op], line, col} | acc])
    else
      # Check if c1 is a single-character operator
      tokenize_single_char_op(c1, [c2 | rest], line, col, acc)
    end
  end

  defp tokenize_impl([c | rest], line, col, acc) do
    tokenize_single_char_op(c, rest, line, col, acc)
  end
  
  defp tokenize_single_char_op(c, rest, line, col, acc) do
    # Single character operators with their atom names
    op_atom = case c do
      "+" -> :+
      "-" -> :-
      "*" -> :*
      "/" -> :/
      "=" -> :=
      "(" -> :"("
      ")" -> :")"
      "[" -> :"["
      "]" -> :"]"
      "{" -> :"{"
      "}" -> :"}"
      "," -> :","
      ":" -> :":"
      "<" -> :lt
      ">" -> :gt
      "|" -> :|
      "&" -> :&
      "!" -> :!
      "." -> :.
      ";" -> :";"
      "%" -> :%
      _ -> nil
    end
    
    if op_atom do
      tokenize_impl(rest, line, col + 1, [{:op, op_atom, line, col} | acc])
    else
      tokenize_impl(rest, line, col + 1, acc)
    end
  end

  defp skip_comment(["\n" | rest], line, _col), do: {rest, line + 1, 1}
  defp skip_comment([], line, col), do: {[], line, col}
  defp skip_comment([_ | rest], line, col), do: skip_comment(rest, line, col + 1)

  defp read_string(["\"" | rest], line, col, acc), do: {acc, rest, line, col + 1}
  defp read_string(["\\", "n" | rest], line, col, acc), do: read_string(rest, line, col + 2, acc <> "\n")
  defp read_string(["\\", "t" | rest], line, col, acc), do: read_string(rest, line, col + 2, acc <> "\t")
  defp read_string(["\\", "\"" | rest], line, col, acc), do: read_string(rest, line, col + 2, acc <> "\"")
  defp read_string(["\n" | rest], line, _col, acc), do: read_string(rest, line + 1, 1, acc <> "\n")
  defp read_string([], line, col, _acc), do: raise(ParseError, message: "Unterminated string", line: line, column: col)
  defp read_string([c | rest], line, col, acc), do: read_string(rest, line, col + 1, acc <> c)

  defp read_number(chars, col), do: read_number_impl(chars, col, [], false)

  defp read_number_impl(["." | rest], col, acc, false) do
    read_number_impl(rest, col + 1, ["." | acc], true)
  end
  defp read_number_impl([c | rest], col, acc, seen_dot) when c in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    read_number_impl(rest, col + 1, [c | acc], seen_dot)
  end
  defp read_number_impl(rest, col, acc, seen_dot) do
    num_str = acc |> Enum.reverse() |> Enum.join("")
    num = if seen_dot do
      String.to_float(num_str)
    else
      String.to_integer(num_str)
    end
    {num, rest, col}
  end

  defp read_identifier(chars, col), do: read_identifier_impl(chars, col, [])

  defp read_identifier_impl([], col, acc) do
    {acc |> Enum.reverse() |> Enum.join(""), [], col}
  end
  defp read_identifier_impl([c | rest], col, acc) 
       when (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" do
    read_identifier_impl(rest, col + 1, [c | acc])
  end
  defp read_identifier_impl(rest, col, acc) do
    {acc |> Enum.reverse() |> Enum.join(""), rest, col}
  end

  defp tokenize_identifier(name, line, col) do
    case Map.get(@keywords, name) do
      nil -> {:ident, name, line, col}
      :let -> {:let, line, col}
      :const -> {:const, line, col}
      :fn -> {:fn, line, col}
      :pub -> {:pub, line, col}
      :if -> {:if, line, col}
      :else -> {:else, line, col}
      :while -> {:while, line, col}
      :for -> {:for, line, col}
      :in -> {:in, line, col}
      :match -> {:match, line, col}
      :type -> {:type, line, col}
      :import -> {:import, line, col}
      :extern -> {:extern, line, col}
      :return -> {:return, line, col}
      :async -> {:async, line, col}
      :await -> {:await, line, col}
      :try -> {:try, line, col}
      :catch -> {:catch, line, col}
      :defer -> {:defer, line, col}
      :comptime -> {:comptime, line, col}
      {:bool, val} -> {:bool, val, line, col}
    end
  end

  # ============================================================================
  # Parser - Program
  # ============================================================================

  defp parse_program(tokens) do
    {statements, rest} = parse_statements(tokens, [])
    {{:program, statements}, rest}
  end

  defp parse_statements([], acc), do: {Enum.reverse(acc), []}
  defp parse_statements([{:op, :";", _, _} | rest], acc), do: parse_statements(rest, acc)
  # Stop at closing braces (they belong to outer context like match or block)
  defp parse_statements([{:op, :"}", _, _} | _] = tokens, acc), do: {Enum.reverse(acc), tokens}
  
  defp parse_statements(tokens, acc) do
    case parse_statement(tokens) do
      {nil, rest} -> parse_statements(rest, acc)
      {stmt, rest} -> parse_statements(rest, [stmt | acc])
    end
  end

  # ============================================================================
  # Parser - Statements
  # ============================================================================

  defp parse_statement([{:let, line, col} | rest]), do: parse_let(rest, line, col, false)
  defp parse_statement([{:const, line, col} | rest]), do: parse_let(rest, line, col, true)
  defp parse_statement([{:fn, line, col} | rest]), do: parse_function(rest, line, col, false)
  defp parse_statement([{:pub, line, col} | [{:fn, _, _} | rest]]), do: parse_function(rest, line, col, true)
  defp parse_statement([{:type, line, col} | rest]), do: parse_type_definition(rest, line, col)
  defp parse_statement([{:import, line, col} | rest]), do: parse_import(rest, line, col)
  defp parse_statement([{:while, line, col} | rest]), do: parse_while(rest, line, col)
  defp parse_statement([{:for, line, col} | rest]), do: parse_for(rest, line, col)
  defp parse_statement([{:try, line, col} | rest]), do: parse_try(rest, line, col)
  defp parse_statement([{:defer, line, col} | rest]), do: parse_defer(rest, line, col)
  defp parse_statement([{:comptime, line, col} | rest]), do: parse_comptime(rest, line, col)
  defp parse_statement(tokens), do: parse_expression(tokens)

  defp parse_let([{:ident, name, _, _} | [{:op, :=, _, _} | expr_tokens]], line, col, _is_const) do
    case expr_tokens do
      [] -> 
        raise ParseError, message: "Expected expression after '='", line: line, column: col
      _ ->
        {expr, rest} = parse_expression(expr_tokens)
        if expr == nil do
          raise ParseError, message: "Expected expression after '='", line: line, column: col
        else
          {{:let, name, expr, line, col}, rest}
        end
    end
  end
  defp parse_let([{:ident, name, line, col} | _], _, _, _) do
    raise ParseError, message: "Expected '=' after variable name '#{name}'", line: line, column: col
  end
  defp parse_let([{token, line, col} | _], _, _, _) do
    raise ParseError, message: "Expected variable name after 'let', found: #{inspect(token)}", line: line, column: col
  end

  defp parse_function([{:ident, name, _, _} | rest], line, col, is_pub) do
    {params, rest} = parse_params(rest)
    {return_type, rest} = parse_return_type(rest)
    {body, rest} = parse_block(rest)
    {{:function, name, params, return_type, body, is_pub, line, col}, rest}
  end
  defp parse_function([{:op, :"(", _, _} | _] = tokens, line, col, _is_pub) do
    # Anonymous function / lambda
    {params, rest} = parse_params(tokens)
    {return_type, rest} = parse_return_type(rest)
    {body, rest} = parse_block(rest)
    {{:lambda, params, return_type, body, line, col}, rest}
  end
  defp parse_function([{_, line, col} | _], _, _, _) do
    raise ParseError, message: "Expected function name or parameters after 'fn'", line: line, column: col
  end

  defp parse_params([{:op, :"(", _, _} | rest]), do: parse_param_list(rest, [])
  defp parse_params(tokens), do: {[], tokens}

  defp parse_param_list([{:op, :")", _, _} | rest], acc), do: {Enum.reverse(acc), rest}
  
  defp parse_param_list([{:ident, name, _, _}, {:op, :":", _, _} | rest], acc) do
    {type, rest} = parse_type(rest)
    param = {name, type}
    
    case rest do
      [{:op, :",", _, _} | after_comma] -> parse_param_list(after_comma, [param | acc])
      [{:op, :")", _, _} | after_paren] -> {Enum.reverse([param | acc]), after_paren}
      _ -> {Enum.reverse([param | acc]), rest}
    end
  end
  
  defp parse_param_list([{:ident, name, _line, _col} | rest], acc) do
    # Parameter without type annotation
    param = {name, {:type, :auto}}
    
    case rest do
      [{:op, :",", _, _} | after_comma] -> parse_param_list(after_comma, [param | acc])
      [{:op, :")", _, _} | after_paren] -> {Enum.reverse([param | acc]), after_paren}
      _ -> {Enum.reverse([param | acc]), rest}
    end
  end
  
  defp parse_param_list(tokens, acc), do: {Enum.reverse(acc), tokens}

  defp parse_return_type([{:op, :arrow, _, _} | rest]) do
    parse_type(rest)
  end
  defp parse_return_type(tokens), do: {{:type, :auto}, tokens}

  defp parse_type([{:ident, type_name, _, _} | rest]) do
    {{:type, String.to_atom(type_name)}, rest}
  end
  defp parse_type([{:op, :"[", _, _} | rest]) do
    {elem_type, rest} = parse_type(rest)
    rest = case rest do
      [{:op, :";", _, _} | r] -> r
      _ -> rest
    end
    {size, rest} = case rest do
      [{:number, n, _, _} | r] -> {n, r}
      _ -> {nil, rest}
    end
    rest = case rest do
      [{:op, :"]", _, _} | r] -> r
      _ -> rest
    end
    {{:type, :array, elem_type, size}, rest}
  end
  defp parse_type(tokens), do: {{:type, :auto}, tokens}

  defp parse_block([{:op, :"{", _, _} | rest]), do: parse_block_contents(rest, [])
  defp parse_block([{:op, :":", _, _} | rest]) do
    {expr, remaining} = parse_expression(rest)
    {expr, remaining}
  end
  defp parse_block(tokens), do: {nil, tokens}

  defp parse_block_contents([{:op, :"}", _, _} | rest], acc), do: {{:block, Enum.reverse(acc)}, rest}

  defp parse_block_contents([], _acc) do
    raise ParseError, message: "Unexpected end of input, expected '}' to close block", line: 0, column: 0
  end

  defp parse_block_contents(tokens, acc) do
    case parse_statement(tokens) do
      {nil, []} ->
        raise ParseError, message: "Unexpected end of input, expected '}' to close block", line: 0, column: 0
      {nil, rest} -> parse_block_contents(rest, acc)
      {stmt, rest} -> parse_block_contents(rest, [stmt | acc])
    end
  end

  defp parse_type_definition([{:ident, name, _, _} | rest], line, col) do
    {definition, rest} = case rest do
      [{:op, :=, _, _} | r] -> 
        {type, r2} = parse_type(r)
        {type, r2}
      _ -> 
        {{:type, :opaque}, rest}
    end
    {{:type_def, name, definition, line, col}, rest}
  end
  defp parse_type_definition([{_, line, col} | _], _, _) do
    raise ParseError, message: "Expected type name after 'type'", line: line, column: col
  end

  defp parse_import([{:string, path, _, _} | rest], line, col) do
    {{:import, path, line, col}, rest}
  end
  defp parse_import([{:ident, name, _, _} | rest], line, col) do
    {{:import, name, line, col}, rest}
  end
  defp parse_import([{_, line, col} | _], _, _) do
    raise ParseError, message: "Expected module name or path after 'import'", line: line, column: col
  end

  defp parse_while(tokens, line, col) do
    {cond_expr, rest} = parse_expression(tokens)
    {body, rest} = parse_block(rest)
    {{:while, cond_expr, body, line, col}, rest}
  end

  defp parse_for([{:ident, var_name, _, _} | rest], line, col) do
    case rest do
      [{:in, _, _} | rest2] ->
        {iterable, rest3} = parse_expression(rest2)
        {body, rest4} = parse_block(rest3)
        {{:for, var_name, iterable, body, line, col}, rest4}
      _ ->
        raise ParseError, message: "Expected 'in' after for variable", line: line, column: col
    end
  end
  defp parse_for([{_, line, col} | _], _, _) do
    raise ParseError, message: "Expected variable name after 'for'", line: line, column: col
  end

  defp parse_try(tokens, line, col) do
    {body, rest} = parse_block(tokens)
    
    case rest do
      [{:catch, _, _} | rest_after_catch] ->
        {catches, rest_final} = parse_catches(rest_after_catch)
        {{:try, body, catches, line, col}, rest_final}
      _ ->
        {{:try, body, [], line, col}, rest}
    end
  end

  defp parse_catches(tokens), do: parse_catches_impl(tokens, [])

  defp parse_catches_impl([{:op, :"}", _, _} | _] = tokens, acc), do: {Enum.reverse(acc), tokens}

  defp parse_catches_impl(tokens, acc) do
    case tokens do
      [{:ident, error_var, _, _} | [{:op, :=, _, _}, {:op, :>, _, _} | rest_after_arrow]] ->
        {error_type, rest} = parse_type(rest_after_arrow)
        {catch_body, rest2} = parse_block(rest)
        
        case rest2 do
          [{:op, :",", _, _} | after_comma] -> parse_catches_impl(after_comma, [{error_var, error_type, catch_body} | acc])
          [{:op, :"}", _, _} | _] -> {Enum.reverse([{error_var, error_type, catch_body} | acc]), rest2}
          _ -> {Enum.reverse([{error_var, error_type, catch_body} | acc]), rest2}
        end
      
      _ -> {Enum.reverse(acc), tokens}
    end
  end

  defp parse_defer(tokens, line, col) do
    {expr, rest} = parse_expression(tokens)
    {{:defer, expr, line, col}, rest}
  end

  defp parse_comptime(tokens, line, col) do
    {body, rest} = parse_block(tokens)
    {{:comptime, body, line, col}, rest}
  end

  # ============================================================================
  # Parser - Expressions (with operator precedence)
  # ============================================================================

  defp parse_expression(tokens), do: parse_pipe(tokens)

  defp parse_pipe(tokens) do
    {left, rest} = parse_or(tokens)
    case rest do
      [{:op, :|>, _, _} | rest2] ->
        {right, rest3} = parse_or(rest2)
        parse_pipe_chain({:pipe, left, right}, rest3)
      _ -> {left, rest}
    end
  end

  defp parse_pipe_chain(left, [{:op, :|>, _, _} | rest]) do
    {right, rest2} = parse_or(rest)
    parse_pipe_chain({:pipe, left, right}, rest2)
  end
  defp parse_pipe_chain(left, rest), do: {left, rest}

  defp parse_or(tokens) do
    {left, rest} = parse_and(tokens)
    case rest do
      [{:op, :|, _, _}, {:op, :|, _, _} | rest2] ->
        {right, rest3} = parse_or(rest2)
        {{:binop, :or, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_and(tokens) do
    {left, rest} = parse_equality(tokens)
    case rest do
      [{:op, :&, _, _}, {:op, :&, _, _} | rest2] ->
        {right, rest3} = parse_and(rest2)
        {{:binop, :and, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_equality(tokens) do
    {left, rest} = parse_comparison(tokens)
    case rest do
      [{:op, :eq, _, _} | rest2] ->
        {right, rest3} = parse_equality(rest2)
        {{:binop, :==, left, right}, rest3}
      [{:op, :neq, _, _} | rest2] ->
        {right, rest3} = parse_equality(rest2)
        {{:binop, :!=, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_comparison(tokens) do
    {left, rest} = parse_concat(tokens)
    case rest do
      [{:op, :lt, _, _} | rest2] ->
        {right, rest3} = parse_comparison(rest2)
        {{:binop, :<, left, right}, rest3}
      [{:op, :gt, _, _} | rest2] ->
        {right, rest3} = parse_comparison(rest2)
        {{:binop, :>, left, right}, rest3}
      [{:op, :lte, _, _} | rest2] ->
        {right, rest3} = parse_comparison(rest2)
        {{:binop, :<=, left, right}, rest3}
      [{:op, :gte, _, _} | rest2] ->
        {right, rest3} = parse_comparison(rest2)
        {{:binop, :>=, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_concat(tokens) do
    {left, rest} = parse_additive(tokens)
    case rest do
      [{:op, :concat, _, _} | rest2] ->
        {right, rest3} = parse_concat(rest2)
        {{:binop, :++, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_additive(tokens) do
    {left, rest} = parse_multiplicative(tokens)
    case rest do
      [{:op, :+, _, _} | rest2] ->
        {right, rest3} = parse_additive(rest2)
        {{:binop, :add, left, right}, rest3}
      [{:op, :-, _, _} | rest2] ->
        {right, rest3} = parse_additive(rest2)
        {{:binop, :sub, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_multiplicative(tokens) do
    {left, rest} = parse_unary(tokens)
    case rest do
      [{:op, :*, _, _} | rest2] ->
        {right, rest3} = parse_multiplicative(rest2)
        {{:binop, :mul, left, right}, rest3}
      [{:op, :/, _, _} | rest2] ->
        {right, rest3} = parse_multiplicative(rest2)
        {{:binop, :div, left, right}, rest3}
      [{:op, :%, _, _} | rest2] ->
        {right, rest3} = parse_multiplicative(rest2)
        {{:binop, :mod, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_unary([{:op, :-, line, col} | rest]) do
    {expr, rest2} = parse_unary(rest)
    {{:unary, :neg, expr, line, col}, rest2}
  end
  defp parse_unary([{:op, :!, line, col} | rest]) do
    {expr, rest2} = parse_unary(rest)
    {{:unary, :not, expr, line, col}, rest2}
  end
  defp parse_unary(tokens), do: parse_primary(tokens)

  # ============================================================================
  # Parser - Primary Expressions
  # ============================================================================

  defp parse_primary([{:number, n, line, col} | rest]), do: {{:number, n, line, col}, rest}
  defp parse_primary([{:string, s, line, col} | rest]), do: {{:string, s, line, col}, rest}
  defp parse_primary([{:bool, b, line, col} | rest]), do: {{:bool, b, line, col}, rest}
  
  defp parse_primary([{:ident, "engine", line, col} | rest]) do
    # Engine call: engine.list_sum([...])
    parse_engine_call(rest, line, col)
  end

  defp parse_primary([{:ident, "python", line, col} | rest]) do
    # Python FFI call: python "module" "function" (args)
    parse_python_call(rest, line, col)
  end
  
  defp parse_primary([{:ident, name, line, col} | rest]) do
    parse_identifier_suffix({:var, name, line, col}, rest)
  end
  
  defp parse_primary([{:op, :"(", _, _} | rest]) do
    {expr, rest} = parse_expression(rest)
    case rest do
      [{:op, :")", _, _} | rest2] -> {expr, rest2}
      [{_, line, col} | _] -> raise ParseError, message: "Expected closing parenthesis", line: line, column: col
      [] -> raise ParseError, message: "Expected closing parenthesis, reached end of input"
    end
  end
  
  defp parse_primary([{:op, :"[", line, col} | rest]) do
    parse_array_literal(rest, line, col)
  end

  defp parse_primary([{:op, :"{", line, col} | rest]) do
    parse_map_literal(rest, line, col)
  end

  defp parse_primary([{:if, line, col} | rest]) do
    {cond_expr, rest} = parse_expression(rest)
    {then_block, rest} = parse_block(rest)
    
    case rest do
      [{:else, _, _} | rest2] ->
        {else_block, rest3} = parse_block(rest2)
        {{:if, cond_expr, then_block, else_block, line, col}, rest3}
      _ ->
        {{:if, cond_expr, then_block, nil, line, col}, rest}
    end
  end

  defp parse_primary([{:match, line, col} | rest]) do
    {value, rest} = parse_expression(rest)
    # After the match value, we expect { to start the match clauses
    # This must be handled specially to avoid parsing { as a map literal
    case rest do
      [{:op, :"{", _, _} | _] ->
        {clauses, rest} = parse_match_clauses(rest)
        {{:match, value, clauses, line, col}, rest}
      [{_, l, c} | _] ->
        raise ParseError, message: "Expected '{{' to start match clauses", line: l, column: c
      [] ->
        raise ParseError, message: "Expected '{{' to start match clauses, reached end of input", line: line, column: col
    end
  end

  defp parse_primary([{:fn, line, col} | rest]) do
    parse_function(rest, line, col, false)
  end

  defp parse_primary([{:async, line, col} | rest]) do
    {expr, rest2} = parse_expression(rest)
    {{:async, expr, line, col}, rest2}
  end

  defp parse_primary([{:await, line, col} | rest]) do
    {expr, rest2} = parse_expression(rest)
    {{:await, expr, line, col}, rest2}
  end

  defp parse_primary([]), do: {nil, []}
  defp parse_primary([{:op, op, line, col} | _]) do
    raise ParseError, message: "Unexpected operator '#{op}' in expression", line: line, column: col
  end
  defp parse_primary([{token, line, col} | _]) do
    raise ParseError, message: "Unexpected token: #{inspect(token)}", line: line, column: col
  end

  # ============================================================================
  # Parser - Engine Calls
  # ============================================================================

  defp parse_engine_call([{:op, :., _, _}, {:ident, op_name, _, _} | rest], line, col) do
    case rest do
      [{:op, :"(", _, _} | rest2] ->
        {args, rest3} = parse_arg_list(rest2)
        {{:engine_call, op_name, args, line, col}, rest3}
      _ ->
        raise ParseError, message: "Expected '(' after engine operation '#{op_name}'", line: line, column: col
    end
  end
  defp parse_engine_call([{:op, :., _, _} | [{_, line, col} | _]], _, _) do
    raise ParseError, message: "Expected engine operation name after 'engine.'", line: line, column: col
  end
  defp parse_engine_call([{_, line, col} | _], _, _) do
    raise ParseError, message: "Expected '.' after 'engine'", line: line, column: col
  end

  # ============================================================================
  # Parser - Python FFI Calls
  # ============================================================================

  defp parse_python_call([{:string, module, _, _}, {:string, function, _, _} | rest], line, col) do
    case rest do
      [{:op, :"(", _, _} | rest2] ->
        {args, rest3} = parse_arg_list(rest2)
        {{:python_call, module, function, args, line, col}, rest3}
      _ ->
        {{:python_call, module, function, [], line, col}, rest}
    end
  end
  defp parse_python_call([{:string, _, _, _} | [{_, line, col} | _]], _, _) do
    raise ParseError, message: "Expected function name string after module string in python call", line: line, column: col
  end
  defp parse_python_call([{_, line, col} | _], _, _) do
    raise ParseError, message: "Expected module string after 'python'", line: line, column: col
  end

  # ============================================================================
  # Parser - Suffix Operations (calls, indexing, field access, pipes)
  # ============================================================================

  defp parse_identifier_suffix(expr, [{:op, :"(", line, col} | rest]) do
    {args, rest} = parse_arg_list(rest)
    parse_identifier_suffix({:call, expr, args, line, col}, rest)
  end
  
  defp parse_identifier_suffix(expr, [{:op, :"[", _, _} | rest]) do
    {index, rest} = parse_expression(rest)
    rest = case rest do
      [{:op, :"]", _, _} | r] -> r
      [{_, line, col} | _] -> raise ParseError, message: "Expected closing bracket ']'", line: line, column: col
      [] -> raise ParseError, message: "Expected closing bracket ']', reached end of input"
    end
    parse_identifier_suffix({:index, expr, index}, rest)
  end
  
  defp parse_identifier_suffix(expr, [{:op, :., _, _}, {:ident, field, _, _} | rest]) do
    parse_identifier_suffix({:field, expr, field}, rest)
  end
  
  defp parse_identifier_suffix(expr, rest), do: {expr, rest}

  defp parse_arg_list(tokens), do: parse_arg_list_impl(tokens, [])
  
  defp parse_arg_list_impl([{:op, :")", _, _} | rest], acc), do: {Enum.reverse(acc), rest}
  
  defp parse_arg_list_impl(tokens, acc) do
    {arg, rest} = parse_expression(tokens)
    case rest do
      [{:op, :",", _, _} | after_comma] -> parse_arg_list_impl(after_comma, [arg | acc])
      [{:op, :")", _, _} | after_paren] -> {Enum.reverse([arg | acc]), after_paren}
      [{_, line, col} | _] -> raise ParseError, message: "Expected ',' or ')' in argument list", line: line, column: col
      [] -> raise ParseError, message: "Expected ',' or ')' in argument list, reached end of input"
    end
  end

  # ============================================================================
  # Parser - Array and Map Literals
  # ============================================================================

  defp parse_array_literal(tokens, line, col) do
    {elements, rest} = parse_array_elements(tokens)
    rest = case rest do
      [{:op, :"]", _, _} | r] -> r
      [{_, line2, col2} | _] -> raise ParseError, message: "Expected closing bracket ']'", line: line2, column: col2
      [] -> raise ParseError, message: "Expected closing bracket ']', reached end of input"
    end
    {{:array, elements, line, col}, rest}
  end

  defp parse_array_elements(tokens), do: parse_array_elements_impl(tokens, [])
  
  defp parse_array_elements_impl([{:op, :"]", _, _} | _] = tokens, acc), do: {Enum.reverse(acc), tokens}
  
  defp parse_array_elements_impl(tokens, acc) do
    {elem, rest} = parse_expression(tokens)
    case rest do
      [{:op, :",", _, _} | after_comma] -> parse_array_elements_impl(after_comma, [elem | acc])
      [{:op, :"]", _, _} | _] -> {Enum.reverse([elem | acc]), rest}
      [{_, line, col} | _] -> raise ParseError, message: "Expected ',' or ']' in array", line: line, column: col
      [] -> raise ParseError, message: "Expected ',' or ']' in array, reached end of input"
    end
  end

  defp parse_map_literal(tokens, line, col) do
    {entries, rest} = parse_map_entries(tokens)
    rest = case rest do
      [{:op, :"}", _, _} | r] -> r
      [{_, line2, col2} | _] -> raise ParseError, message: "Expected closing brace '}'", line: line2, column: col2
      [] -> raise ParseError, message: "Expected closing brace '}', reached end of input"
    end
    {{:map, entries, line, col}, rest}
  end

  defp parse_map_entries(tokens), do: parse_map_entries_impl(tokens, [])

  defp parse_map_entries_impl([{:op, :"}", _, _} | _] = tokens, acc), do: {Enum.reverse(acc), tokens}

  defp parse_map_entries_impl(tokens, acc) do
    {key, rest} = parse_expression(tokens)
    rest = case rest do
      [{:op, :":", _, _} | r] -> r
      [{:op, :=, _, _}, {:op, :>, _, _} | r] -> r
      [{_, line, col} | _] -> raise ParseError, message: "Expected ':' or '=>' after map key", line: line, column: col
      [] -> raise ParseError, message: "Expected ':' or '=>' after map key, reached end of input"
    end
    {value, rest2} = parse_expression(rest)
    
    case rest2 do
      [{:op, :",", _, _} | after_comma] -> parse_map_entries_impl(after_comma, [{key, value} | acc])
      [{:op, :"}", _, _} | _] -> {Enum.reverse([{key, value} | acc]), rest2}
      [{_, line, col} | _] -> raise ParseError, message: "Expected ',' or '}' in map", line: line, column: col
      [] -> raise ParseError, message: "Expected ',' or '}' in map, reached end of input"
    end
  end

  # ============================================================================
  # Parser - Match Clauses
  # ============================================================================

  defp parse_match_clauses(tokens) do
    case tokens do
      [{:op, :"{", _, _} | rest] -> parse_match_clause_list(rest, [])
      [{_, line, col} | _] -> raise ParseError, message: "Expected '{' to start match clauses", line: line, column: col
      [] -> raise ParseError, message: "Expected '{' to start match clauses, reached end of input"
    end
  end

  defp parse_match_clause_list([{:op, :"}", _, _} | rest], acc), do: {Enum.reverse(acc), rest}
  
  defp parse_match_clause_list(tokens, acc) do
    {pattern, rest} = parse_expression(tokens)
    rest = case rest do
      [{:op, :=, _, _}, {:op, :>, _, _} | r] -> r
      [{:op, :fat_arrow, _, _} | r] -> r
      [{_, line, col} | _] -> raise ParseError, message: "Expected '=>' after pattern in match clause", line: line, column: col
      [] -> raise ParseError, message: "Expected '=>' after pattern in match clause, reached end of input"
    end
    {body, rest} = parse_block_or_expr(rest)
    
    case rest do
      [{:op, :",", _, _} | after_comma] -> parse_match_clause_list(after_comma, [{pattern, body} | acc])
      [{:op, :"}", _, _} | _] -> {Enum.reverse([{pattern, body} | acc]), rest}
      [{_, line, col} | _] -> raise ParseError, message: "Expected ',' or '}' after match clause body", line: line, column: col
      [] -> raise ParseError, message: "Expected ',' or '}' after match clause body, reached end of input"
    end
  end

  defp parse_block_or_expr([{:op, :"{", _, _} | _] = tokens) do
    parse_block(tokens)
  end
  
  defp parse_block_or_expr(tokens) do
    parse_expression(tokens)
  end
end
