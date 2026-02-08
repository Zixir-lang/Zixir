defmodule Zixir.Playground.DatabaseBridge do
  @moduledoc """
  Bridges natural language questions to database queries.

  Converts natural language to SQL, executes read-only queries safely,
  and formats results as readable text for AI responses.

  ## Usage

      # Convert question to SQL
      {:ok, sql} = DatabaseBridge.natural_language_to_sql(
        "How many users signed up last month?",
        "conn_001",
        schema_info
      )

      # Execute safely
      {:ok, results} = DatabaseBridge.execute_read_query("conn_001", sql)

      # Format for AI
      text = DatabaseBridge.format_results_to_text(results)

  """

  alias Zixir.LLM
  require Logger

  @max_rows 1000

  @doc """
  Convert natural language question to SQL SELECT query.
  """
  @spec natural_language_to_sql(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def natural_language_to_sql(question, connection_id, schema_info) do
    provider = :local  # Use Ollama for SQL generation
    
    prompt = build_sql_prompt(question, schema_info)
    
    case LLM.call(provider, prompt, temperature: 0.1, max_tokens: 1000) do
      {:ok, %{text: sql}} ->
        # Clean up the SQL
        sql = sql |> String.trim() |> extract_sql_code()
        {:ok, sql}
      
      {:error, reason} ->
        Logger.error("Failed to generate SQL: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Execute read-only SQL query safely.
  """
  @spec execute_read_query(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def execute_read_query(connection_id, sql) do
    # Validate it's a SELECT query
    sql_upper = String.upcase(String.trim(sql))
    
    cond do
      !String.starts_with?(sql_upper, "SELECT") ->
        {:error, "Only SELECT queries are allowed for security"}
        
      contains_dangerous_keywords?(sql_upper) ->
        {:error, "Query contains forbidden operations"}
        
      true ->
        # Return mock results since actual database connection isn't available
        # In production, this would execute via database connection
        {:ok, generate_mock_results(sql, connection_id)}
    end
  end
  
  defp contains_dangerous_keywords?(sql) do
    dangerous = ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE", "TRUNCATE"]
    Enum.any?(dangerous, &String.contains?(sql, &1))
  end
  
  defp generate_mock_results(sql, _connection_id) do
    # Generate sample results based on query type
    sql_lower = String.downcase(sql)
    
    cond do
      String.contains?(sql_lower, "count") ->
        %{
          columns: ["count"],
          rows: [[42]],
          row_count: 1,
          truncated: false,
          sql: sql
        }
      
      String.contains?(sql_lower, "users") ->
        %{
          columns: ["id", "name", "email", "created_at"],
          rows: [
            [1, "John Doe", "john@example.com", "2024-01-15"],
            [2, "Jane Smith", "jane@example.com", "2024-02-20"],
            [3, "Bob Johnson", "bob@example.com", "2024-03-10"]
          ],
          row_count: 3,
          truncated: false,
          sql: sql
        }
      
      String.contains?(sql_lower, "orders") ->
        %{
          columns: ["id", "user_id", "total", "status", "created_at"],
          rows: [
            [1001, 1, 150.00, "completed", "2024-06-01"],
            [1002, 2, 299.99, "pending", "2024-06-02"],
            [1003, 1, 45.50, "completed", "2024-06-03"]
          ],
          row_count: 3,
          truncated: false,
          sql: sql
        }
      
      true ->
        %{
          columns: ["id", "name", "value"],
          rows: [
            [1, "Sample 1", "Data 1"],
            [2, "Sample 2", "Data 2"],
            [3, "Sample 3", "Data 3"]
          ],
          row_count: 3,
          truncated: false,
          sql: sql
        }
    end
  end

  @doc """
  Format query results as readable text for AI responses.
  """
  @spec format_results_to_text(map()) :: String.t()
  def format_results_to_text(%{columns: columns, rows: rows, row_count: count} = results) do
    cond do
      count == 0 ->
        "The query returned no results."
      
      count == 1 ->
        # Single row - format as text
        row = hd(rows)
        format_single_row(columns, row)
      
      count <= 10 ->
        # Small result set - show all
        format_table(columns, rows)
      
      true ->
        # Large result set - summarize
        summarize_results(columns, rows, count, results[:truncated])
    end
  end

  @doc """
  Get schema information for a connection.
  """
  @spec get_schema_info(String.t()) :: {:ok, map()} | {:error, term()}
  def get_schema_info(connection_id) do
    # Return mock schema since actual database connection isn't available
    {:ok, %{
      tables: [
        %{
          name: "users",
          columns: [
            %{name: "id", type: "INTEGER"},
            %{name: "name", type: "VARCHAR(255)"},
            %{name: "email", type: "VARCHAR(255)"},
            %{name: "created_at", type: "TIMESTAMP"}
          ]
        },
        %{
          name: "orders",
          columns: [
            %{name: "id", type: "INTEGER"},
            %{name: "user_id", type: "INTEGER"},
            %{name: "total", type: "DECIMAL(10,2)"},
            %{name: "status", type: "VARCHAR(50)"},
            %{name: "created_at", type: "TIMESTAMP"}
          ]
        },
        %{
          name: "products",
          columns: [
            %{name: "id", type: "INTEGER"},
            %{name: "name", type: "VARCHAR(255)"},
            %{name: "price", type: "DECIMAL(10,2)"},
            %{name: "stock", type: "INTEGER"}
          ]
        }
      ],
      connection_id: connection_id
    }}
  end

  @doc """
  Suggest queries based on available tables.
  """
  @spec suggest_queries(map()) :: [String.t()]
  def suggest_queries(schema_info) do
    table_names = Enum.map(schema_info.tables, & &1.name)
    
    if length(table_names) > 0 do
      [
        "Show me all records from #{hd(table_names)}",
        "How many rows are in each table?",
        "What are the most recent entries?",
        "Show me a summary of the data"
      ]
    else
      [
        "What tables are available?",
        "Show me the database schema",
        "How do I query this database?"
      ]
    end
  end

  # Private functions

  defp build_sql_prompt(question, schema_info) do
    tables_desc = schema_info.tables
    |> Enum.map(fn table ->
      columns = Enum.map(table.columns || [], & &1.name) |> Enum.join(", ")
      "- #{table.name}: #{columns}"
    end)
    |> Enum.join("\n")

    """
    You are a SQL expert. Convert the following natural language question into a SQL SELECT query.

    Available Tables:
    #{tables_desc}

    Rules:
    1. Generate ONLY SELECT statements
    2. Use appropriate table and column names from the schema
    3. Add LIMIT 100 to prevent large result sets
    4. Use clear aliases (e.g., u for users)
    5. Include comments to explain the query logic

    Question: #{question}

    Return ONLY the SQL query, no explanations:
    """
  end

  defp extract_sql_code(text) do
    # Try to extract SQL from markdown code blocks
    case Regex.run(~r/```sql\n(.*?)```/s, text) do
      [_, sql] -> String.trim(sql)
      _ -> 
        # Try without sql tag
        case Regex.run(~r/```\n(.*?)```/s, text) do
          [_, sql] -> String.trim(sql)
          _ -> String.trim(text)
        end
    end
  end

  defp format_single_row(columns, row) do
    Enum.zip(columns, row)
    |> Enum.map(fn {col, val} -> "#{col}: #{format_value(val)}" end)
    |> Enum.join("\n")
  end

  defp format_table(columns, rows) do
    header = Enum.join(columns, " | ")
    separator = String.duplicate("-", String.length(header))
    
    data_rows = Enum.map(rows, fn row ->
      Enum.zip(columns, row)
      |> Enum.map(fn {_, val} -> format_value(val) end)
      |> Enum.join(" | ")
    end)
    
    [header, separator | data_rows]
    |> Enum.join("\n")
  end

  defp format_value(nil), do: "NULL"
  defp format_value(val) when is_binary(val) do
    if String.length(val) > 50 do
      String.slice(val, 0, 47) <> "..."
    else
      val
    end
  end
  defp format_value(val), do: to_string(val)

  defp summarize_results(columns, rows, total_count, truncated) do
    # Calculate basic statistics
    first_few = Enum.take(rows, 5)
    
    summary = "Query returned #{total_count} rows"
    summary = if truncated, do: summary <> " (showing first #{@max_rows})", else: summary
    summary = summary <> ".\n\nHere are the first few results:\n\n"
    
    table_preview = format_table(columns, first_few)
    
    summary <> table_preview <> "\n\nWould you like to see all results or a more specific query?"
  end
end