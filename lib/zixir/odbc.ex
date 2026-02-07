defmodule Zixir.ODBC do
  @moduledoc """
  ODBC Database Connector for Zixir.

  Provides universal SQL database access via ODBC drivers with:
  - Connection pooling
  - Query execution
  - Transaction management
  - Automatic type conversion
  - Metadata extraction

  ## Supported Databases

  - Microsoft SQL Server
  - PostgreSQL (via ODBC)
  - MySQL / MariaDB
  - Oracle
  - SQLite (via ODBC)
  - Any database with ODBC driver

  ## Quick Start

  Connect to an ODBC data source and execute queries.

  ## Connection Options

  | Option | Description |
  |--------|-------------|
  | `:dsn` | ODBC DSN name |
  | `:connection_string` | Full connection string |
  | `:host` | Server hostname |
  | `:database` | Database name |
  | `:username` | Username |
  | `:password` | Password |
  | `:driver` | ODBC driver name |
  | `:port` | Port number |
  | `:autocommit` | Auto-commit mode (default: false) |
  | `:timeout` | Connection timeout (seconds) |
  | `:max_pool_size` | Connection pool size (default: 10) |

  ## Examples

      iex> {:ok, conn} = Zixir.ODBC.connect(dsn: "test_dsn")
      iex> is_map(conn)
      true

  """

  require Logger

  alias Zixir.Observability

  @type connection :: map()
  @type result :: {:ok, term()} | {:error, term()}
  @type query_result :: {:ok, [map()]} | {:error, term()}
  @type execution_result :: {:ok, non_neg_integer()} | {:error, term()}

  @default_timeout 30
  @default_pool_size 10

  @doc """
  Connect to an ODBC data source.

  ## Examples

      iex> {:ok, conn} = Zixir.ODBC.connect(dsn: "test")
      iex> is_map(conn)
      true

  """
  @spec connect(keyword()) :: {:ok, connection()} | {:error, term()}
  def connect(opts \\ []) when is_list(opts) do
    start_time = System.monotonic_time(:millisecond)
    config = build_config(opts)

    Observability.trace("odbc.connect", fn ->
      case Zixir.Python.call("odbc_bridge", "odbc_bridge.connect", [config]) do
        {:ok, %{"status" => "ok", "pool_id" => pool_id, "config" => conn_config}} ->
          conn = %{
            pool_id: pool_id,
            config: conn_config,
            ref: make_ref(),
            created_at: DateTime.utc_now()
          }

          duration = System.monotonic_time(:millisecond) - start_time
          Observability.record_metric("odbc.connection.duration", duration, unit: :millisecond)

          Observability.info("ODBC connected",
            database: conn_config["database"],
            host: conn_config["host"]
          )

          {:ok, conn}

        {:ok, %{"status" => "error", "message" => message}} ->
          _duration = System.monotonic_time(:millisecond) - start_time
          Observability.record_metric("odbc.connection.failure", 1)
          Logger.error("ODBC connection failed: #{message}")
          {:error, message}

        error ->
          _duration = System.monotonic_time(:millisecond) - start_time
          Observability.record_metric("odbc.connection.failure", 1)
          Logger.error("ODBC connection error: #{inspect(error)}")
          {:error, inspect(error)}
      end
    end)
  end

  @doc """
  Execute a SELECT query.

  Returns a list of maps with column names as keys.

  ## Parameters

  - `connection` - Connection from `Zixir.ODBC.connect/1`
  - `sql` - SQL query with ? placeholders
  - `params` - Parameters to bind to placeholders

  ## Examples

      iex> {:ok, rows} = Zixir.ODBC.query(conn, "SELECT 1 as id", [])
      iex> is_list(rows)
      true

  """
  @spec query(connection(), String.t(), [term()]) :: query_result()
  def query(%{pool_id: pool_id} = _conn, sql, params \\ [])
      when is_binary(sql) and is_list(params) do
    start_time = System.monotonic_time(:millisecond)

    Observability.trace("odbc.query", fn ->
      case Zixir.Python.call("odbc_bridge", "odbc_bridge.query", [pool_id, sql, params]) do
        {:ok, %{"status" => "ok", "columns" => columns, "rows" => rows, "row_count" => count}} ->
          duration = System.monotonic_time(:millisecond) - start_time
          Observability.record_metric("odbc.query.duration", duration, unit: :millisecond)
          Observability.record_metric("odbc.query.rows_returned", count)

          parsed_rows = parse_rows(columns, rows)
          {:ok, parsed_rows}

        {:ok, %{"status" => "error", "message" => message}} ->
          _duration = System.monotonic_time(:millisecond) - start_time
          Observability.record_metric("odbc.query.failure", 1)
          Logger.error("ODBC query failed: #{message}")
          {:error, message}

        error ->
          _duration = System.monotonic_time(:millisecond) - start_time
          Observability.record_metric("odbc.query.failure", 1)
          Logger.error("ODBC query error: #{inspect(error)}")
          {:error, inspect(error)}
      end
    end)
  end

  @doc """
  Execute INSERT, UPDATE, or DELETE query.

  Returns the number of affected rows.

  ## Examples

      iex> {:ok, affected} = Zixir.ODBC.execute(conn, "DELETE FROM test", [])
      iex> is_integer(affected)
      true

  """
  @spec execute(connection(), String.t(), [term()]) :: execution_result()
  def execute(%{pool_id: pool_id} = _conn, sql, params \\ [])
      when is_binary(sql) and is_list(params) do
    start_time = System.monotonic_time(:millisecond)

    case Zixir.Python.call("odbc_bridge", "odbc_bridge.execute", [pool_id, sql, params]) do
      {:ok, %{"status" => "ok", "affected_rows" => count}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.execute.duration", duration, unit: :millisecond)
        Observability.record_metric("odbc.execute.affected_rows", count)
        {:ok, count}

      {:ok, %{"status" => "error", "message" => message}} ->
        _duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.execute.failure", 1)
        Logger.error("ODBC execute failed: #{message}")
        {:error, message}

      error ->
        _duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.execute.failure", 1)
        Logger.error("ODBC execute error: #{inspect(error)}")
        {:error, inspect(error)}
    end
  end

  @doc """
  Execute the same query with multiple parameter sets (batch operation).

  ## Examples

      iex> {:ok, count} = Zixir.ODBC.execute_many(conn, "INSERT INTO test (id) VALUES (?)", [[1], [2], [3]])
      iex> is_integer(count)
      true

  """
  @spec execute_many(connection(), String.t(), [[term()]]) :: execution_result()
  def execute_many(%{pool_id: pool_id} = _conn, sql, params_list)
      when is_binary(sql) and is_list(params_list) do
    start_time = System.monotonic_time(:millisecond)
    batch_count = length(params_list)

    case Zixir.Python.call("odbc_bridge", "odbc_bridge.execute_many", [pool_id, sql, params_list]) do
      {:ok, %{"status" => "ok", "affected_rows" => count, "batches" => _batches}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.execute_many.duration", duration, unit: :millisecond)
        Observability.record_metric("odbc.execute_many.batches", batch_count)
        Observability.record_metric("odbc.execute_many.total_affected", count)
        {:ok, count}

      {:ok, %{"status" => "error", "message" => message}} ->
        _duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.execute_many.failure", 1)
        Logger.error("ODBC execute_many failed: #{message}")
        {:error, message}

      error ->
        _duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.execute_many.failure", 1)
        {:error, inspect(error)}
    end
  end

  @doc """
  Fetch results with pagination (LIMIT/OFFSET).

  ## Options

  - `:limit` - Maximum rows to fetch (default: 1000)
  - `:offset` - Starting offset (default: 0)

  ## Examples

      iex> {:ok, rows, has_more} = Zixir.ODBC.fetch(conn, "SELECT 1 as id", limit: 10)
      iex> is_list(rows)
      true

  """
  @spec fetch(connection(), String.t(), keyword()) :: {:ok, [map()], boolean()} | {:error, term()}
  def fetch(%{pool_id: pool_id} = _conn, sql, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    limit = Keyword.get(opts, :limit, 1000)
    offset = Keyword.get(opts, :offset, 0)

    case Zixir.Python.call("odbc_bridge", "odbc_bridge.fetch", [pool_id, sql, limit, offset]) do
      {:ok, %{"status" => "ok", "columns" => columns, "rows" => rows, "has_more" => more}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.fetch.duration", duration, unit: :millisecond)
        parsed_rows = parse_rows(columns, rows)
        {:ok, parsed_rows, more}

      {:ok, %{"status" => "error", "message" => message}} ->
        _duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.fetch.failure", 1)
        {:error, message}

      error ->
        _duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.fetch.failure", 1)
        {:error, inspect(error)}
    end
  end

  @doc """
  Execute multiple operations in a single transaction.

  If any operation fails, all changes are rolled back.

  ## Examples

      iex> {:ok, results} = Zixir.ODBC.transaction(conn, [%{sql: "SELECT 1", params: []}])
      iex> is_list(results)
      true

  """
  @spec transaction(connection(), [%{String.t() => term()}]) ::
          {:ok, [%{String.t() => term()}]} | {:error, term()}
  def transaction(%{pool_id: pool_id} = _conn, operations) when is_list(operations) do
    start_time = System.monotonic_time(:millisecond)

    case Zixir.Python.call("odbc_bridge", "odbc_bridge.transaction", [pool_id, operations]) do
      {:ok, %{"status" => "ok", "results" => results}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.transaction.duration", duration, unit: :millisecond)
        Observability.record_metric("odbc.transaction.operations", length(results))
        {:ok, results}

      {:ok, %{"status" => "error", "message" => message}} ->
        _duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.transaction.failure", 1)
        Logger.error("ODBC transaction failed: #{message}")
        {:error, message}

      error ->
        _duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("odbc.transaction.failure", 1)
        {:error, inspect(error)}
    end
  end

  @doc """
  Check if connection is still alive.
  """
  @spec ping(connection()) :: :ok | {:error, term()}
  def ping(%{pool_id: pool_id} = _conn) do
    case Zixir.Python.call("odbc_bridge", "odbc_bridge.ping", [pool_id]) do
      {:ok, %{"status" => "ok", "message" => _message}} ->
        :ok

      {:ok, %{"status" => "error", "message" => message}} ->
        {:error, message}

      error ->
        {:error, inspect(error)}
    end
  end

  @doc """
  Get connection pool health statistics.
  """
  @spec health(connection()) :: map()
  def health(%{pool_id: pool_id}) do
    case Zixir.Python.call("odbc_bridge", "odbc_bridge.health", [pool_id]) do
      {:ok, health_data} -> health_data
      _ -> %{status: "unknown"}
    end
  end

  @doc """
  List all tables in the database.

  ## Examples

      iex> {:ok, tables} = Zixir.ODBC.tables(conn)
      iex> is_list(tables)
      true

  """
  @spec tables(connection(), String.t() | nil) ::
          {:ok, [%{String.t() => term()}]} | {:error, term()}
  def tables(%{pool_id: pool_id}, schema \\ nil) do
    case Zixir.Python.call("odbc_bridge", "odbc_bridge.tables", [pool_id, schema]) do
      {:ok, %{"status" => "ok", "tables" => tables}} ->
        {:ok, tables}

      {:ok, %{"status" => "error", "message" => message}} ->
        {:error, message}

      error ->
        {:error, inspect(error)}
    end
  end

  @doc """
  Get column information for a table.

  ## Examples

      iex> {:ok, columns} = Zixir.ODBC.columns(conn, "test_table")
      iex> is_list(columns)
      true

  """
  @spec columns(connection(), String.t(), String.t() | nil) ::
          {:ok, [%{String.t() => term()}]} | {:error, term()}
  def columns(%{pool_id: pool_id}, table_name, schema \\ nil) do
    case Zixir.Python.call("odbc_bridge", "odbc_bridge.columns", [pool_id, table_name, schema]) do
      {:ok, %{"status" => "ok", "columns" => columns}} ->
        {:ok, columns}

      {:ok, %{"status" => "error", "message" => message}} ->
        {:error, message}

      error ->
        {:error, inspect(error)}
    end
  end

  @doc """
  Close connection pool and release all resources.
  """
  @spec disconnect(connection()) :: :ok
  def disconnect(%{pool_id: pool_id, config: config}) do
    case Zixir.Python.call("odbc_bridge", "odbc_bridge.disconnect", [pool_id]) do
      {:ok, %{"status" => "ok"}} ->
        Observability.info("ODBC disconnected",
          database: config["database"],
          host: config["host"]
        )

        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Get the module protocol version.
  """
  @spec protocol_version() :: String.t()
  def protocol_version, do: "1.0.0"

  defp build_config(opts) do
    %{
      dsn: Keyword.get(opts, :dsn),
      connection_string: Keyword.get(opts, :connection_string),
      host: Keyword.get(opts, :host),
      database: Keyword.get(opts, :database),
      username: Keyword.get(opts, :username),
      password: Keyword.get(opts, :password),
      driver: Keyword.get(opts, :driver),
      port: Keyword.get(opts, :port),
      autocommit: Keyword.get(opts, :autocommit, false),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      max_pool_size: Keyword.get(opts, :max_pool_size, @default_pool_size)
    }
  end

  defp parse_rows(columns, rows) when is_list(columns) and is_list(rows) do
    Enum.map(rows, fn row ->
      Enum.zip(columns, row) |> Map.new()
    end)
  end

  defp parse_rows(_, rows), do: rows
end
