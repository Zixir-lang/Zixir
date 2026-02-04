defmodule Zixir.Compiler.Parser do
  @moduledoc """
  Phase 1: New recursive descent parser for Zixir.
   
  Simpler and more powerful than NimbleParsec version.
  Generates Zixir AST that compiles directly to Zig.
  """

  # Suppress warnings for features not yet integrated
  @compile {:nowarn_unused_function, [
    :parse_list_comp, :parse_map_literal, :parse_struct, :parse_try,
    :parse_async, :parse_await, :parse_range, :parse_defer, :parse_comptime,
    :parse_map_entries, :parse_map_entries_impl, :parse_struct_fields,
    :parse_struct_fields_impl, :parse_catches, :parse_catches_impl,
    :parse_list_comp_impl, :parse_type_expression
  ]}

  defmodule ParseError do
    defexception [:message, :line, :column]
  end

  @doc """
  Parse Zixir source into AST.
  Returns {:ok, ast} or {:error, ParseError}
  """
  def parse(source) when is_binary(source) do
    try do
      tokens = tokenize(source)
      {ast, _remaining, errors} = parse_program_with_recovery(tokens)
      
      if length(errors) > 0 do
        # Return first error but include all in the exception
        first_error = hd(errors)
        {:error, %{first_error | message: first_error.message <> " (and #{length(errors) - 1} more errors)"}}
      else
        {:ok, ast}
      end
    rescue
      e in ParseError -> {:error, e}
    end
  end

  @doc """
  Parse with detailed error recovery. Returns all errors found.
  """
  def parse_with_errors(source) when is_binary(source) do
    try do
      tokens = tokenize(source)
      {ast, _remaining, errors} = parse_program_with_recovery(tokens)
      {:ok, ast, errors}
    rescue
      e in ParseError -> {:error, e}
    end
  end

  # Tokenizer - simpler than parser combinators
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
    {rest_after_comment, new_line, new_col} = skip_comment(rest, line, col)
    tokenize_impl(rest_after_comment, new_line, new_col, acc)
  end
  
  defp tokenize_impl(["\"" | rest], line, col, acc) do
    {str, rest, new_line, new_col} = read_string(rest, line, col + 1, "")
    tokenize_impl(rest, new_line, new_col, [{:string, str, line, col} | acc])
  end
  
  defp tokenize_impl([c | rest], line, col, acc) when c in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    {num, rest, new_col} = read_number([c | rest], col, false)
    tokenize_impl(rest, line, new_col, [{:number, num, line, col} | acc])
  end
  
  defp tokenize_impl([c | rest], line, col, acc) when c >= "a" and c <= "z" or c >= "A" and c <= "Z" or c == "_" do
    {ident, rest, new_col} = read_identifier([c | rest], col)
    token = keyword_or_identifier(ident, line, col)
    tokenize_impl(rest, line, new_col, [token | acc])
  end
  
  defp tokenize_impl([c | rest], line, col, acc) when c in ["+", "-", "*", "/", "=", "(", ")", "[", "]", "{", "}", ",", ":", "<", ">", "|", "&", "!", "."] do
    tokenize_impl(rest, line, col + 1, [{:op, c, line, col} | acc])
  end
  
  defp tokenize_impl([_c | rest], line, col, acc) do
    # Skip unknown characters
    tokenize_impl(rest, line, col + 1, acc)
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

  defp read_number(["." | rest], col, false) do
    {rest, new_col} = read_digits(rest, col + 1)
    num_str = "." <> String.slice(List.to_string(rest), 0, new_col - col - 1)
    {String.to_float("0" <> num_str), rest, new_col}
  end
  defp read_number(chars, col, seen_dot) do
    {digits, rest, new_col} = read_digits(chars, col)
    num_str = List.to_string(digits)
    
    cond do
      seen_dot ->
        {String.to_float(num_str), rest, new_col}
      
      match?(["." | _], rest) ->
        # Float with digits before and after decimal point
        ["." | rest_after_dot] = rest
        {frac_digits, rest_after_frac, final_col} = read_digits(rest_after_dot, new_col + 1)
        frac_str = List.to_string(frac_digits)
        full_num_str = num_str <> "." <> frac_str
        {String.to_float(full_num_str), rest_after_frac, final_col}
      
      true ->
        {String.to_integer(num_str), rest, new_col}
    end
  end

  defp read_digits(chars, col), do: read_digits_impl(chars, col, [])
  
  defp read_digits_impl([], col, acc), do: {Enum.reverse(acc), [], col}
  defp read_digits_impl([c | rest], col, acc) when c in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    read_digits_impl(rest, col + 1, [c | acc])
  end
  defp read_digits_impl(rest, col, acc), do: {Enum.reverse(acc), rest, col}

  defp read_identifier(chars, col), do: read_identifier_impl(chars, col, [])
  
  defp read_identifier_impl([], col, acc), do: {List.to_string(Enum.reverse(acc)), [], col}
  defp read_identifier_impl([c | rest], col, acc) when c >= "a" and c <= "z" or c >= "A" and c <= "Z" or c >= "0" and c <= "9" or c == "_" do
    read_identifier_impl(rest, col + 1, [c | acc])
  end
  defp read_identifier_impl(rest, col, acc), do: {List.to_string(Enum.reverse(acc)), rest, col}

  defp keyword_or_identifier("fn", line, col), do: {:fn, line, col}
  defp keyword_or_identifier("let", line, col), do: {:let, line, col}
  defp keyword_or_identifier("if", line, col), do: {:if, line, col}
  defp keyword_or_identifier("else", line, col), do: {:else, line, col}
  defp keyword_or_identifier("return", line, col), do: {:return, line, col}
  defp keyword_or_identifier("true", line, col), do: {:bool, true, line, col}
  defp keyword_or_identifier("false", line, col), do: {:bool, false, line, col}
  defp keyword_or_identifier("match", line, col), do: {:match, line, col}
  defp keyword_or_identifier("type", line, col), do: {:type, line, col}
  defp keyword_or_identifier("pub", line, col), do: {:pub, line, col}
  defp keyword_or_identifier("import", line, col), do: {:import, line, col}
  defp keyword_or_identifier("extern", line, col), do: {:extern, line, col}
  defp keyword_or_identifier("while", line, col), do: {:while, line, col}
  defp keyword_or_identifier("for", line, col), do: {:for, line, col}
  defp keyword_or_identifier("in", line, col), do: {:in, line, col}
  defp keyword_or_identifier(name, line, col), do: {:ident, name, line, col}

  defp parse_program_with_recovery(tokens) do
    parse_statements_with_recovery(tokens, [], [])
  end

  defp parse_statements_with_recovery([], acc, errors), do: {{:program, Enum.reverse(acc)}, [], errors}
  
  defp parse_statements_with_recovery(tokens, acc, errors) do
    case parse_statement_with_recovery(tokens, errors) do
      {nil, [], new_errors} -> 
        # Empty rest means we're done, no more tokens to parse
        {{:program, Enum.reverse(acc)}, [], new_errors}
      {nil, rest, new_errors} when rest == tokens -> 
        # No progress made - skip one token to avoid infinite loop
        [_ | rest_after_skip] = tokens
        parse_statements_with_recovery(rest_after_skip, acc, new_errors)
      {nil, rest, new_errors} -> 
        # Made progress, continue parsing
        parse_statements_with_recovery(rest, acc, new_errors)
      {{:error, err}, rest, new_errors} -> 
        # Skip to next statement boundary and continue
        rest_after_skip = skip_to_statement_boundary(rest)
        parse_statements_with_recovery(rest_after_skip, acc, [err | new_errors])
      {stmt, rest, new_errors} -> parse_statements_with_recovery(rest, [stmt | acc], new_errors)
    end
  end

  defp parse_statement_with_recovery(tokens, errors) do
    try do
      case parse_statement(tokens) do
        {nil, rest} -> {nil, rest, errors}
        {{:error, msg}, rest} -> 
          e = %ParseError{message: msg, line: 0, column: 0}
          {{:error, e}, rest, errors}
        {stmt, rest} -> {stmt, rest, errors}
      end
    rescue
      e in ParseError -> {{:error, e}, tokens, errors}
    end
  end

  defp skip_to_statement_boundary(tokens) do
    # Skip tokens until we find a good place to resume parsing
    # Look for semicolons, newlines, or statement-starting keywords
    case tokens do
      [] -> []
      [{:op, ";", _, _} | rest] -> rest
      [{:op, "}", _, _} | _] = t -> t  # Stop at block end
      [{:fn, _, _} | _] = t -> t
      [{:let, _, _} | _] = t -> t
      [{:type, _, _} | _] = t -> t
      [{:import, _, _} | _] = t -> t
      [{:pub, _, _} | _] = t -> t
      [_ | rest] -> skip_to_statement_boundary(rest)
    end
  end

  defp parse_statement([{:let, line, col} | rest]) do
    case rest do
      [{:ident, name, _, _} | [{:op, "=", _, _} | expr_tokens]] ->
        {expr, remaining} = parse_expression(expr_tokens)
        
        if is_nil(expr) do
          # Return error tuple instead of raising, so recovery can skip properly
          {{:error, "Expected expression after 'let #{name} = '"}, expr_tokens}
        else
          {{:let, name, expr, line, col}, remaining}
        end
      
      [{:ident, name, _, _} | _rest_without_eq] ->
        # Missing equals sign
        raise ParseError, 
          message: "Expected '=' after 'let #{name}'", 
          line: line, 
          column: col
      
      [{:op, op, op_line, op_col} | _] ->
        raise ParseError, 
          message: "Expected identifier after 'let', found operator '#{op}'", 
          line: op_line, 
          column: op_col
      
      [] ->
        raise ParseError, 
          message: "Unexpected end of input after 'let'", 
          line: line, 
          column: col
      
      _ ->
        raise ParseError, 
          message: "Expected identifier after 'let'", 
          line: line, 
          column: col
    end
  end

  defp parse_statement([{:fn, line, col} | rest]) do
    parse_function(rest, line, col, false)
  end

  defp parse_statement([{:pub, line, col} | [{:fn, _, _} | rest]]) do
    parse_function(rest, line, col, true)
  end

  defp parse_statement([{:type, line, col} | rest]) do
    parse_type_definition(rest, line, col)
  end

  defp parse_statement([{:import, line, col} | rest]) do
    parse_import(rest, line, col)
  end

  defp parse_statement([{:while, line, col} | rest]) do
    parse_while(rest, line, col)
  end

  defp parse_statement([{:for, line, col} | rest]) do
    parse_for(rest, line, col)
  end

  defp parse_statement(tokens) do
    parse_expression(tokens)
  end

  defp parse_function([{:ident, name, _, _} | rest], line, col, is_pub) do
    # Parse parameters: (name: Type, ...)
    {params, rest} = parse_params(rest)
    
    # Parse return type: -> Type
    {return_type, rest} = parse_return_type(rest)
    
    # Parse body
    {body, rest} = parse_block(rest)
    
    func = {:function, name, params, return_type, body, is_pub, line, col}
    {func, rest}
  end

  defp parse_function([{:op, "(", _, _} | _] = tokens, line, col, _is_pub) do
    # Anonymous function (is_pub is always false for lambdas)
    {params, rest} = parse_params(tokens)
    {return_type, rest} = parse_return_type(rest)
    {body, rest} = parse_block(rest)
    {{:lambda, params, return_type, body, line, col}, rest}
  end

  defp parse_params([{:op, "(", _, _} | rest]) do
    parse_param_list(rest, [])
  end
  defp parse_params(tokens), do: {[], tokens}

  defp parse_param_list([{:op, ")", _, _} | rest], acc), do: {Enum.reverse(acc), rest}
  
  defp parse_param_list([{:ident, name, _, _}, {:op, ":", _, _} | rest], acc) do
    {type, rest} = parse_type(rest)
    param = {name, type}
    
    case rest do
      [{:op, ",", _, _} | after_comma] -> parse_param_list(after_comma, [param | acc])
      [{:op, ")", _, _} | after_paren] -> {Enum.reverse([param | acc]), after_paren}
      _ -> {Enum.reverse([param | acc]), rest}
    end
  end
  
  defp parse_param_list(tokens, acc), do: {Enum.reverse(acc), tokens}

  defp parse_return_type([{:op, "-", _, _}, {:op, ">", _, _} | rest]) do
    parse_type(rest)
  end
  defp parse_return_type(tokens), do: {{:type, :auto}, tokens}

  defp parse_type([{:ident, type_name, _, _} | rest]) do
    {{:type, String.to_atom(type_name)}, rest}
  end
  defp parse_type([{:op, "[", _, _} | rest]) do
    # Array type: [Type; N]
    {elem_type, rest} = parse_type(rest)
    rest = case rest do
      [{:op, ";", _, _} | r] -> r
      _ -> rest
    end
    {size_tokens, rest} = case rest do
      [{:number, n, _, _} | r] -> {n, r}
      _ -> {nil, rest}
    end
    rest = case rest do
      [{:op, "]", _, _} | r] -> r
      _ -> rest
    end
    {{:type, :array, elem_type, size_tokens}, rest}
  end
  defp parse_type(tokens), do: {{:type, :unknown}, tokens}

  defp parse_block([{:op, "{", _, _} | rest]) do
    parse_block_contents(rest, [])
  end
  defp parse_block([{:op, ":", _, _} | rest]) do
    # Colon syntax: if x: y else: z
    {expr, remaining} = parse_expression(rest)
    {expr, remaining}
  end
  defp parse_block(tokens), do: {nil, tokens}

  defp parse_block_contents([{:op, "}", _, _} | rest], acc), do: {{:block, Enum.reverse(acc)}, rest}
  
  defp parse_block_contents(tokens, acc) do
    case parse_statement(tokens) do
      {nil, rest} -> parse_block_contents(rest, acc)
      {stmt, rest} -> parse_block_contents(rest, [stmt | acc])
    end
  end

  defp parse_type_definition(tokens, line, col) do
    case tokens do
      [{:ident, name, _, _} | rest] ->
        {definition, rest} = case rest do
          [{:op, "=", _, _} | r] -> 
            {type, r2} = parse_type(r)
            {type, r2}
          _ -> 
            {{:type, :opaque}, rest}
        end
        {{:type_def, name, definition, line, col}, rest}
      _ ->
        raise ParseError, message: "Expected type name after 'type'", line: line, column: col
    end
  end

  defp parse_import(tokens, line, col) do
    case tokens do
      [{:string, path, _, _} | rest] ->
        {{:import, path, line, col}, rest}
      [{:ident, name, _, _} | rest] ->
        {{:import, name, line, col}, rest}
      _ ->
        raise ParseError, message: "Expected module name/path after 'import'", line: line, column: col
    end
  end

  defp parse_while(tokens, line, col) do
    # Parse condition
    {cond_expr, rest} = parse_expression(tokens)
    # Parse body (using colon syntax)
    {body, rest} = parse_block(rest)
    {{:while, cond_expr, body, line, col}, rest}
  end

  defp parse_for(tokens, line, col) do
    # Parse: for var in iterable: body
    case tokens do
      [{:ident, var_name, _, _} | rest] ->
        case rest do
          [{:in, _, _} | rest2] ->
            {iterable, rest3} = parse_expression(rest2)
            {body, rest4} = parse_block(rest3)
            {{:for, var_name, iterable, body, line, col}, rest4}
          _ ->
            raise ParseError, message: "Expected 'in' after for variable", line: line, column: col
        end
      _ ->
        raise ParseError, message: "Expected variable name after 'for'", line: line, column: col
    end
  end

  # Expression parsing with operator precedence
  defp parse_expression([]), do: {nil, []}
  defp parse_expression(tokens) do
    parse_or(tokens)
  end

  defp parse_or(tokens) do
    {left, rest} = parse_and(tokens)
    case rest do
      [{:op, "|", _, _}, {:op, "|", _, _} | rest2] ->
        {right, rest3} = parse_or(rest2)
        {{:binop, :or, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_and(tokens) do
    {left, rest} = parse_comparison(tokens)
    case rest do
      [{:op, "&", _, _}, {:op, "&", _, _} | rest2] ->
        {right, rest3} = parse_and(rest2)
        {{:binop, :and, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_comparison(tokens) do
    {left, rest} = parse_additive(tokens)
    case rest do
      # Multi-character operators: ==, !=, <=, >=
      [{:op, "=", _, _}, {:op, "=", _, _} | rest2] ->
        {right, rest3} = parse_comparison(rest2)
        {{:binop, :==, left, right}, rest3}
      [{:op, "!", _, _}, {:op, "=", _, _} | rest2] ->
        {right, rest3} = parse_comparison(rest2)
        {{:binop, :!=, left, right}, rest3}
      [{:op, "<", _, _}, {:op, "=", _, _} | rest2] ->
        {right, rest3} = parse_comparison(rest2)
        {{:binop, :<=, left, right}, rest3}
      [{:op, ">", _, _}, {:op, "=", _, _} | rest2] ->
        {right, rest3} = parse_comparison(rest2)
        {{:binop, :>=, left, right}, rest3}
      # Single-character operators: <, >
      [{:op, "<", _, _} | rest2] ->
        {right, rest3} = parse_comparison(rest2)
        {{:binop, :<, left, right}, rest3}
      [{:op, ">", _, _} | rest2] ->
        {right, rest3} = parse_comparison(rest2)
        {{:binop, :>, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_additive(tokens) do
    {left, rest} = parse_multiplicative(tokens)
    case rest do
      [{:op, "+", _, _} | rest2] ->
        {right, rest3} = parse_additive(rest2)
        {{:binop, :add, left, right}, rest3}
      [{:op, "-", _, _} | rest2] ->
        {right, rest3} = parse_additive(rest2)
        {{:binop, :sub, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_multiplicative(tokens) do
    {left, rest} = parse_unary(tokens)
    case rest do
      [{:op, "*", _, _} | rest2] ->
        {right, rest3} = parse_multiplicative(rest2)
        {{:binop, :mul, left, right}, rest3}
      [{:op, "/", _, _} | rest2] ->
        {right, rest3} = parse_multiplicative(rest2)
        {{:binop, :div, left, right}, rest3}
      _ -> {left, rest}
    end
  end

  defp parse_unary([{:op, "-", line, col} | rest]) do
    {expr, rest2} = parse_unary(rest)
    {{:unary, :neg, expr, line, col}, rest2}
  end
  defp parse_unary([{:op, "!", line, col} | rest]) do
    {expr, rest2} = parse_unary(rest)
    {{:unary, :not, expr, line, col}, rest2}
  end
  defp parse_unary(tokens), do: parse_primary(tokens)

  defp parse_primary([{:number, n, line, col} | rest]), do: {{:number, n, line, col}, rest}
  defp parse_primary([{:string, s, line, col} | rest]), do: {{:string, s, line, col}, rest}
  defp parse_primary([{:bool, b, line, col} | rest]), do: {{:bool, b, line, col}, rest}
  
  defp parse_primary([{:ident, name, line, col} | rest]) do
    parse_identifier_suffix({:var, name, line, col}, rest)
  end
  
  defp parse_primary([{:op, "(", _, _} | rest]) do
    {expr, rest} = parse_expression(rest)
    case rest do
      [{:op, ")", _, _} | rest2] -> {expr, rest2}
      _ -> raise ParseError, message: "Expected closing parenthesis", line: 0, column: 0
    end
  end
  
  defp parse_primary([{:op, "[", line, col} | rest]) do
    parse_array_literal(rest, line, col)
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
    {clauses, rest} = parse_match_clauses(rest)
    {{:match, value, clauses, line, col}, rest}
  end

  defp parse_primary([{:fn, line, col} | rest]) do
    parse_function(rest, line, col, false)
  end

  defp parse_primary(tokens) do
    {nil, tokens}
  end

  defp parse_identifier_suffix(expr, [{:op, "(", _, _} | rest]) do
    {args, rest} = parse_arg_list(rest)
    parse_identifier_suffix({:call, expr, args}, rest)
  end
  
  defp parse_identifier_suffix(expr, [{:op, "[", _, _} | rest]) do
    {index, rest} = parse_expression(rest)
    rest = case rest do
      [{:op, "]", _, _} | r] -> r
      _ -> rest
    end
    parse_identifier_suffix({:index, expr, index}, rest)
  end
  
  defp parse_identifier_suffix(expr, [{:op, ".", _, _}, {:ident, field, _, _} | rest]) do
    parse_identifier_suffix({:field, expr, field}, rest)
  end
  
  defp parse_identifier_suffix(expr, [{:op, "|>", _, _} | rest]) do
    {right, rest2} = parse_unary(rest)
    parse_identifier_suffix({:pipe, expr, right}, rest2)
  end
  
  defp parse_identifier_suffix(expr, rest), do: {expr, rest}

  defp parse_arg_list(tokens), do: parse_arg_list_impl(tokens, [])
  
  defp parse_arg_list_impl([{:op, ")", _, _} | rest], acc), do: {Enum.reverse(acc), rest}
  
  defp parse_arg_list_impl(tokens, acc) do
    {arg, rest} = parse_expression(tokens)
    case rest do
      [{:op, ",", _, _} | after_comma] -> parse_arg_list_impl(after_comma, [arg | acc])
      [{:op, ")", _, _} | after_paren] -> {Enum.reverse([arg | acc]), after_paren}
      _ -> {Enum.reverse([arg | acc]), rest}
    end
  end

  defp parse_array_literal(tokens, line, col) do
    {elements, rest} = parse_array_elements(tokens)
    rest = case rest do
      [{:op, "]", _, _} | r] -> r
      _ -> rest
    end
    {{:array, elements, line, col}, rest}
  end

  defp parse_array_elements(tokens), do: parse_array_elements_impl(tokens, [])
  
  defp parse_array_elements_impl([{:op, "]", _, _} | _] = tokens, acc), do: {Enum.reverse(acc), tokens}
  
  defp parse_array_elements_impl(tokens, acc) do
    {elem, rest} = parse_expression(tokens)
    case rest do
      [{:op, ",", _, _} | after_comma] -> parse_array_elements_impl(after_comma, [elem | acc])
      [{:op, "]", _, _} | _] -> {Enum.reverse([elem | acc]), rest}
      _ -> {Enum.reverse([elem | acc]), rest}
    end
  end

  defp parse_match_clauses(tokens) do
    case tokens do
      [{:op, "{", _, _} | rest] -> parse_match_clause_list(rest, [])
      _ -> {[], tokens}
    end
  end

  defp parse_match_clause_list([{:op, "}", _, _} | rest], acc), do: {Enum.reverse(acc), rest}
  
  defp parse_match_clause_list(tokens, acc) do
    {pattern, rest} = parse_expression(tokens)
    rest = case rest do
      [{:op, "=", _, _}, {:op, ">", _, _} | r] -> r
      _ -> rest
    end
    {body, rest} = parse_block_or_expr(rest)
    
    case rest do
      [{:op, ",", _, _} | after_comma] -> parse_match_clause_list(after_comma, [{pattern, body} | acc])
      [{:op, "}", _, _} | _] -> {Enum.reverse([{pattern, body} | acc]), rest}
      _ -> {Enum.reverse([{pattern, body} | acc]), rest}
    end
  end

  defp parse_block_or_expr([{:op, "{", _, _} | _] = tokens) do
    parse_block(tokens)
  end
  
  defp parse_block_or_expr(tokens) do
    parse_expression(tokens)
  end

  defp parse_list_comp([{:for, line, col} | rest]) do
    parse_list_comp_impl(rest, line, col, nil, nil)
  end

  defp parse_list_comp(tokens) do
    {nil, tokens}
  end

  defp parse_list_comp_impl([{:ident, var_name, _, _} | [{:in, _, _} | rest]], line, col, _generator, _filter) do
    {iterable, rest2} = parse_expression(rest)
    
    case rest2 do
      [{:if, _if_line, _if_col} | rest_after_if] ->
        {filter, rest_final} = parse_expression(rest_after_if)
        {{:list_comp, {:for_gen, var_name, iterable}, filter, nil, line, col}, rest_final}
      
      _ ->
        {{:list_comp, {:for_gen, var_name, iterable}, nil, nil, line, col}, rest2}
    end
  end

  defp parse_list_comp_impl(tokens, line, col, generator, filter) do
    {map_expr, rest} = parse_expression(tokens)
    {{:list_comp, generator, filter, map_expr, line, col}, rest}
  end

  defp parse_map_literal([{:op, "{", line, col} | rest]) do
    {entries, rest2} = parse_map_entries(rest)
    rest = case rest2 do
      [{:op, "}", _, _} | r] -> r
      _ -> rest2
    end
    {{:map, entries, line, col}, rest}
  end

  defp parse_map_literal(tokens), do: {nil, tokens}

  defp parse_map_entries(tokens), do: parse_map_entries_impl(tokens, [])

  defp parse_map_entries_impl([{:op, "}", _, _} | _] = tokens, acc), do: {Enum.reverse(acc), tokens}

  defp parse_map_entries_impl(tokens, acc) do
    {key, rest} = parse_expression(tokens)
    rest = case rest do
      [{:op, "=", _, _}, {:op, ">", _, _} | r] -> r
      _ -> rest
    end
    {value, rest2} = parse_expression(rest)
    
    case rest2 do
      [{:op, ",", _, _} | after_comma] -> parse_map_entries_impl(after_comma, [{key, value} | acc])
      [{:op, "}", _, _} | _] -> {Enum.reverse([{key, value} | acc]), rest2}
      _ -> {Enum.reverse([{key, value} | acc]), rest2}
    end
  end

  defp parse_struct([{:ident, name, _, _} | [{:op, "{", line, col} | rest]]) do
    {fields, rest2} = parse_struct_fields(rest)
    rest = case rest2 do
      [{:op, "}", _, _} | r] -> r
      _ -> rest2
    end
    {{:struct, name, fields, line, col}, rest}
  end

  defp parse_struct(tokens), do: {nil, tokens}

  defp parse_struct_fields(tokens), do: parse_struct_fields_impl(tokens, [])

  defp parse_struct_fields_impl([{:op, "}", _, _} | _] = tokens, acc), do: {Enum.reverse(acc), tokens}

  defp parse_struct_fields_impl(tokens, acc) do
    case tokens do
      [{:ident, fname, _, _} | [{:op, ":", _, _} | rest_after_colon]] ->
        {ftype, rest} = parse_type_expression(rest_after_colon)
        
        case rest do
          [{:op, ",", _, _} | after_comma] -> parse_struct_fields_impl(after_comma, [{fname, ftype} | acc])
          [{:op, "}", _, _} | _] -> {Enum.reverse([{fname, ftype} | acc]), rest}
          _ -> {Enum.reverse([{fname, ftype} | acc]), rest}
        end
      
      _ -> {Enum.reverse(acc), tokens}
    end
  end

  defp parse_type_expression([{:ident, type_name, _, _} | rest]) do
    {{:type, type_name}, rest}
  end

  defp parse_type_expression([{:op, "[", _, _} | [{:op, "]", _, _} | rest]]) do
    {{:type, :array, {:type, :auto}}, rest}
  end

  defp parse_type_expression([{:op, "[", _, _} | rest]) do
    {elem_type, rest2} = parse_type_expression(rest)
    rest = case rest2 do
      [{:op, "]", _, _} | r] -> r
      _ -> rest2
    end
    {{:type, :array, elem_type}, rest}
  end

  defp parse_type_expression(tokens), do: {{:type, :auto}, tokens}

  defp parse_try([{:op, "{", line, col} | rest]) do
    {body, rest2} = parse_block(rest)
    
    case rest2 do
      [{:catch, _catch_line, _catch_col} | rest_after_catch] ->
        {catches, rest_final} = parse_catches(rest_after_catch)
        {{:try, body, catches, line, col}, rest_final}
      
      _ ->
        {{:try, body, [], line, col}, rest2}
    end
  end

  defp parse_try(tokens), do: {nil, tokens}

  defp parse_catches(tokens), do: parse_catches_impl(tokens, [])

  defp parse_catches_impl([{:op, "}", _, _} | _] = tokens, acc), do: {Enum.reverse(acc), tokens}

  defp parse_catches_impl(tokens, acc) do
    case tokens do
      [{:ident, error_var, _, _} | [{:op, ":", _, _} | rest_after_colon]] ->
        {error_type, rest} = parse_type_expression(rest_after_colon)
        {catch_body, rest2} = parse_block(rest)
        
        case rest2 do
          [{:op, ",", _, _} | after_comma] -> parse_catches_impl(after_comma, [{error_var, error_type, catch_body} | acc])
          [{:op, "}", _, _} | _] -> {Enum.reverse([{error_var, error_type, catch_body} | acc]), rest2}
          _ -> {Enum.reverse([{error_var, error_type, catch_body} | acc]), rest2}
        end
      
      _ -> {Enum.reverse(acc), tokens}
    end
  end

  defp parse_async([{:ident, name, line, col} | [{:op, "(", _, _} | _] = rest]) do
    case parse_expression([{:ident, name, line, col} | rest]) do
      {{:call, _, _} = call_expr, rest2} ->
        {{:async, call_expr, line, col}, rest2}
      {expr, rest2} ->
        {expr, rest2}
    end
  end

  defp parse_async(tokens), do: {nil, tokens}

  defp parse_await([{:ident, name, line, col} | [{:op, "(", _, _} | _] = rest]) do
    case parse_expression([{:ident, name, line, col} | rest]) do
      {{:call, _, _} = call_expr, rest2} ->
        {{:await, call_expr, line, col}, rest2}
      {expr, rest2} ->
        {expr, rest2}
    end
  end

  defp parse_await(tokens), do: {nil, tokens}

  @doc """
  Parse range expression: start..end
  """
  defp parse_range([{:number, n1, l1, c1} | [{:op, ".", _, _}, {:op, ".", _, _} | rest]]) do
    {n2, rest2, new_col} = read_number(rest, c1 + 2, false)
    {{:range, {:number, n1, l1, c1}, {:number, n2, l1, new_col}, l1, c1}, rest2}
  end

  defp parse_range([{:ident, name, line, col} | [{:op, ".", _, _}, {:op, ".", _, _} | rest]]) do
    {end_expr, rest2} = parse_expression(rest)
    {{:range, {:var, name, line, col}, end_expr, line, col}, rest2}
  end

  defp parse_range(tokens), do: {nil, tokens}

  defp parse_defer([{:op, "{", line, col} | rest]) do
    {expr, rest2} = parse_expression(rest)
    rest = case rest2 do
      [{:op, "}", _, _} | r] -> r
      _ -> rest2
    end
    {{:defer, expr, line, col}, rest}
  end

  defp parse_defer(tokens), do: {nil, tokens}

  defp parse_comptime([{:op, "{", line, col} | rest]) do
    {body, rest2} = parse_block(rest)
    {{:comptime, body, line, col}, rest2}
  end

  defp parse_comptime(tokens), do: {nil, tokens}
end
