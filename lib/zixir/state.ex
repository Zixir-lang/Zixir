defmodule Zixir.State do
  @moduledoc """
  State Persistence for Workflows and AI Automation.

  Provides automatic checkpointing and recovery for workflows:
  - Multiple storage backends (disk, S3, database)
  - Automatic state serialization
  - Workflow recovery from checkpoints
  - Dead letter handling for failed states

  ## Storage Backends

  | Backend | Description | Best For |
  |---------|-------------|---------|
  | `:disk` | Local filesystem | Development, single-node |
  | `:s3` | AWS S3 | Distributed systems, cloud |
  | `:database` | SQL database | Enterprise with existing DB |

  ## Quick Start

      # Save workflow state
      :ok = Zixir.State.save("workflow_123", %{
        step: "process_order",
        data: %{order_id: "ORD-001", items: [...]},
        created_at: DateTime.utc_now()
      })

      # Load latest state
      {:ok, state} = Zixir.State.load("workflow_123")

      # Create checkpoint
      {:ok, checkpoint_id} = Zixir.State.checkpoint("workflow_123", "step_5")

      # Restore from checkpoint
      {:ok, state} = Zixir.State.restore("workflow_123", checkpoint_id)

  ## Automatic Checkpointing in Workflows

  Workflows automatically checkpoint state at each step:

      workflow = Zixir.Workflow.new("my_workflow")
      |> Zixir.Workflow.add_step("step1", fn -> ... end)
      |> Zixir.Workflow.add_step("step2", fn -> ... end)

      # Checkpoints saved automatically between steps
      Zixir.Workflow.execute(workflow, checkpoint: true)

  ## Configuration

      config :zixir, :state,
        storage: :disk,           # Storage backend
        checkpoint_dir: "_zixir_checkpoints",  # Disk path
        s3_bucket: "my-bucket",   # S3 bucket
        max_checkpoints: 50,      # Keep last N checkpoints
        compression: true         # Compress state files

  """

  require Logger

  alias Zixir.Observability

  @type storage :: :memory | :disk | :s3 | :database
  @type state :: map()
  @type checkpoint_id :: String.t()
  @type checkpoint :: %{
          id: checkpoint_id(),
          workflow_id: String.t(),
          step_name: String.t(),
          state: state(),
          timestamp: DateTime.t(),
          metadata: map()
        }

  @default_storage :disk
  @default_checkpoint_dir "_zixir_checkpoints"
  @default_max_checkpoints 50
  @default_compression true

  @doc """
  Save workflow state to persistent storage.

  ## Parameters

  - `workflow_id` - Unique workflow identifier
  - `state` - State data to persist
  - `storage` - Storage backend (default: :disk)
  - `opts` - Additional options

  ## Options

  - `:step` - Current step name
  - `:metadata` - Additional metadata
  - `:compress` - Compress state (default: true)

  ## Examples

      # Basic save
      :ok = Zixir.State.save("workflow_123", %{data: "value"})

      # With step info
      :ok = Zixir.State.save("workflow_123", state, step: "processing")

      # To S3
      :ok = Zixir.State.save("workflow_123", state, :s3, bucket: "my-bucket")

      # To database
      :ok = Zixir.State.save("workflow_123", state, :database, table: "workflow_states")

  """
  @spec save(String.t(), state(), storage(), keyword()) :: :ok | {:error, term()}
  def save(workflow_id, state, storage, opts) when is_nil(state) do
    {:error, :invalid_state}
  end

  def save(workflow_id, state, storage \\ @default_storage, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    step = Keyword.get(opts, :step, "unknown")
    metadata = Keyword.get(opts, :metadata, %{})
    compress = Keyword.get(opts, :compress, @default_compression)

    checkpoint_id = generate_checkpoint_id()

    checkpoint_data = %{
      id: checkpoint_id,
      workflow_id: workflow_id,
      step_name: step,
      state: state,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      compressed: compress
    }

    serialized = serialize(checkpoint_data, compress)

    result =
      case storage do
        :memory -> save_to_memory(workflow_id, checkpoint_id, checkpoint_data, opts)
        :disk -> save_to_disk(workflow_id, checkpoint_id, serialized, opts)
        :s3 -> save_to_s3(workflow_id, checkpoint_id, serialized, opts)
        :database -> save_to_database(workflow_id, checkpoint_id, serialized, opts)
        _ -> {:error, "Storage backend not supported: #{storage}"}
      end

    duration = System.monotonic_time(:millisecond) - start_time
    if(Process.whereis(Zixir.Observability), do: Zixir.Observability.record_metric("state.save.duration", duration, unit: :millisecond), else: :ok)

    case result do
      :ok ->
        if(Process.whereis(Zixir.Observability), do: Zixir.Observability.info("State saved", workflow_id: workflow_id, step: step, storage: storage), else: :ok)
        cleanup_old_checkpoints(workflow_id, storage, opts)
        :ok

      {:error, reason} ->
        if(Process.whereis(Zixir.Observability), do: Zixir.Observability.record_metric("state.save.failure", 1), else: :ok)
        Logger.error("State save failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Load latest state for a workflow.

  Returns the most recent state or checkpoint.

  ## Parameters

  - `workflow_id` - Workflow identifier
  - `storage` - Storage backend (default: disk)

  ## Examples

      {:ok, state} = Zixir.State.load("workflow_123")

      # From S3
      {:ok, state} = Zixir.State.load("workflow_123", :s3)

  """
  @spec load(String.t(), storage(), keyword()) :: {:ok, state()} | {:error, term()}
  def load(workflow_id, storage \\ @default_storage, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    case find_latest_checkpoint(workflow_id, storage, opts) do
      {:ok, checkpoint_id} ->
        load_checkpoint(workflow_id, checkpoint_id, storage, opts)
        |> case do
          {:ok, %{state: state} = _checkpoint} ->
            duration = System.monotonic_time(:millisecond) - start_time
            if(Process.whereis(Zixir.Observability), do: Zixir.Observability.record_metric("state.load.duration", duration, unit: :millisecond), else: :ok)
            {:ok, state}

          {:ok, data} when is_map(data) and not is_struct(data) ->
            duration = System.monotonic_time(:millisecond) - start_time
            if(Process.whereis(Zixir.Observability), do: Zixir.Observability.record_metric("state.load.duration", duration, unit: :millisecond), else: :ok)
            {:ok, data}

          {:ok, data} ->
            duration = System.monotonic_time(:millisecond) - start_time
            if(Process.whereis(Zixir.Observability), do: Zixir.Observability.record_metric("state.load.duration", duration, unit: :millisecond), else: :ok)
            {:ok, data}

          error ->
            duration = System.monotonic_time(:millisecond) - start_time
            if(Process.whereis(Zixir.Observability), do: Zixir.Observability.record_metric("state.load.failure", 1), else: :ok)
            error
        end

      {:error, :not_found} ->
        {:error, :not_found}

      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        if(Process.whereis(Zixir.Observability), do: Zixir.Observability.record_metric("state.load.failure", 1), else: :ok)
        error
    end
  end

  @doc """
  Create a named checkpoint at current step.

  Useful for manual checkpointing within workflows.

  ## Parameters

  - `workflow_id` - Workflow identifier
  - `step_name` - Current step name
  - `storage` - Storage backend
  - `opts` - Additional options

  ## Returns

  `{:ok, checkpoint_id}`

  ## Examples

      {:ok, checkpoint_id} = Zixir.State.checkpoint("workflow_123", "step_5")

      # Later restore
      {:ok, state} = Zixir.State.restore("workflow_123", checkpoint_id)

  """
  @spec checkpoint(String.t(), String.t(), storage(), keyword()) ::
          {:ok, checkpoint_id()} | {:error, term()}
  def checkpoint(workflow_id, step_name, storage \\ @default_storage, opts \\ []) do
    state = Keyword.get(opts, :state, %{})
    metadata = Keyword.get(opts, :metadata, %{})

    # Error if state is explicitly nil in opts
    if Keyword.has_key?(opts, :state) and is_nil(state) do
      {:error, :invalid_state}
    else
      case save(workflow_id, state, storage, step: step_name, metadata: metadata) do
        :ok -> {:ok, generate_checkpoint_id()}
        error -> error
      end
    end
  end

  @doc """
  Restore workflow from a specific checkpoint.

  ## Parameters

  - `workflow_id` - Workflow identifier
  - `checkpoint_id` - Checkpoint to restore from
  - `storage` - Storage backend

  ## Examples

      {:ok, state} = Zixir.State.restore("workflow_123", "chk_abc123")

  """
  @spec restore(String.t(), checkpoint_id(), storage(), keyword()) ::
          {:ok, state()} | {:error, term()}
  def restore(workflow_id, checkpoint_id, storage \\ @default_storage, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    case load_checkpoint(workflow_id, checkpoint_id, storage, opts) do
      {:ok, data} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("state.restore.duration", duration, unit: :millisecond)

        Observability.info("State restored",
          workflow_id: workflow_id,
          checkpoint_id: checkpoint_id
        )

        {:ok, data}

      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        Observability.record_metric("state.restore.failure", 1)
        error
    end
  end

  @doc """
  List all checkpoints for a workflow.

  ## Parameters

  - `workflow_id` - Workflow identifier
  - `storage` - Storage backend

  ## Examples

      {:ok, checkpoints} = Zixir.State.checkpoints("workflow_123")
      # => [%{id: "...", step_name: "step_1", timestamp: ...}, ...]

  """
  @spec checkpoints(String.t(), storage(), keyword()) :: {:ok, [map()]}
  def checkpoints(workflow_id, storage \\ @default_storage, opts \\ []) do
    case list_checkpoints(workflow_id, storage, opts) do
      {:ok, checkpoints} ->
        # Sort by checkpoint ID descending (ID contains timestamp)
        sorted = Enum.sort(checkpoints, fn a, b ->
          a.id >= b.id
        end)
        {:ok, sorted}

      error ->
        error
    end
  end

  @doc """
  Get the latest checkpoint ID for a workflow.

  ## Examples

      {:ok, checkpoint_id} = Zixir.State.latest_checkpoint("workflow_123")

  """
  @spec latest_checkpoint(String.t(), storage(), keyword()) ::
          {:ok, checkpoint_id()} | {:error, term()}
  def latest_checkpoint(workflow_id, storage \\ @default_storage, opts \\ []) do
    find_latest_checkpoint(workflow_id, storage, opts)
  end

  @doc """
  Delete state and all checkpoints for a workflow.

  ## Parameters

  - `workflow_id` - Workflow identifier
  - `storage` - Storage backend
  - `opts` - Additional options

  ## Examples

      :ok = Zixir.State.delete("workflow_123")

  """
  @spec delete(String.t(), storage(), keyword()) :: :ok | {:error, term()}
  def delete(workflow_id, storage \\ @default_storage, opts \\ []) do
    case delete_all_checkpoints(workflow_id, storage, opts) do
      :ok ->
        Observability.info("State deleted", workflow_id: workflow_id)
        :ok

      error ->
        error
    end
  end

  @doc """
  Get state storage statistics.

  ## Examples

      stats = Zixir.State.stats("workflow_123")
      # => %{checkpoints: 10, latest: ~U[2024-01-15...], storage: :disk}

  """
  @spec stats(String.t(), storage(), keyword()) :: map()
  def stats(workflow_id, storage \\ @default_storage, opts \\ []) do
    case checkpoints(workflow_id, storage, opts) do
      {:ok, checkpoints} ->
        case checkpoints do
          [] ->
            %{checkpoints: 0, latest: nil, storage: storage, workflow_id: workflow_id}

          [latest | _] ->
            %{
              checkpoints: length(checkpoints),
              latest: latest.timestamp,
              latest_step: latest.step_name,
              storage: storage,
              workflow_id: workflow_id
            }
        end

      _ ->
        %{checkpoints: 0, storage: storage, workflow_id: workflow_id}
    end
  end

  # Private functions

  defp generate_checkpoint_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    uuid = :crypto.strong_rand_bytes(8) |> Base.encode16()
    "chk_#{timestamp}_#{uuid}"
  end

  defp serialize(data, compress) do
    serialized = :erlang.term_to_binary(data)

    if compress do
      compressed = :zlib.compress(serialized)
      %{data: compressed, compressed: true}
    else
      %{data: serialized, compressed: false}
    end
  end

  defp deserialize(%{data: data, compressed: true}) do
    decompressed = :zlib.uncompress(data)
    :erlang.binary_to_term(decompressed)
  end

  defp deserialize(%{data: data, compressed: false}) do
    :erlang.binary_to_term(data)
  end

  defp get_checkpoint_dir(workflow_id, opts) do
    base_dir = Keyword.get(opts, :checkpoint_dir, @default_checkpoint_dir)
    Path.join([base_dir, workflow_id, "checkpoints"])
  end

  @zixir_state_table :zixir_state_table

  defp ensure_memory_table do
    case :ets.whereis(@zixir_state_table) do
      :undefined ->
        :ets.new(@zixir_state_table, [:set, :public, :named_table])
      _ ->
        :ok
    end
  end

  defp save_to_memory(workflow_id, checkpoint_id, checkpoint_data, _opts) do
    ensure_memory_table()
    key = {workflow_id, checkpoint_id}
    :ets.insert(@zixir_state_table, {key, checkpoint_data, System.monotonic_time(:millisecond)})
    :ok
  end

  defp load_from_memory(workflow_id, checkpoint_id, _opts) do
    ensure_memory_table()
    key = {workflow_id, checkpoint_id}
    case :ets.lookup(@zixir_state_table, key) do
      [{^key, data, _timestamp}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  defp save_to_disk(workflow_id, checkpoint_id, serialized, opts) do
    dir = get_checkpoint_dir(workflow_id, opts)

    with :ok <- File.mkdir_p(dir) do
      file = Path.join(dir, "#{checkpoint_id}.chk")
      # Write binary format directly
      binary_data = :erlang.term_to_binary(serialized)
      File.write(file, binary_data)
    end
  end

  defp load_checkpoint(workflow_id, checkpoint_id, :disk, opts) do
    dir = get_checkpoint_dir(workflow_id, opts)
    file = Path.join(dir, "#{checkpoint_id}.chk")

    with {:ok, data} <- File.read(file) do
      serialized = :erlang.binary_to_term(data)
      {:ok, deserialize(serialized)}
    end
  end

  defp save_to_s3(workflow_id, checkpoint_id, serialized, opts) do
    bucket = Keyword.get(opts, :s3_bucket)
    key = "#{workflow_id}/checkpoints/#{checkpoint_id}.chk"

    data = Jason.encode!(serialized)

    case S3.put_object(bucket, key, data) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, "S3 not configured"}
  end

  defp save_to_database(workflow_id, checkpoint_id, serialized, opts) do
    table = Keyword.get(opts, :table, "zixir_state")

    data = Jason.encode!(serialized)

    query = """
    INSERT INTO #{table} (workflow_id, checkpoint_id, data, created_at)
    VALUES ($1, $2, $3, NOW())
    ON CONFLICT (workflow_id, checkpoint_id) DO UPDATE SET data = $3
    """

    case Zixir.ODBC.execute(Zixir.ODBC.connect(opts), query, [workflow_id, checkpoint_id, data]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_latest_checkpoint(workflow_id, storage, opts) do
    case list_checkpoints(workflow_id, storage, opts) do
      {:ok, [%{id: id} | _]} -> {:ok, id}
      {:ok, []} -> {:error, :not_found}
      error -> error
    end
  end

  defp list_checkpoints(workflow_id, :disk, opts) do
    dir = get_checkpoint_dir(workflow_id, opts)

    with {:ok, files} <- File.ls(dir) do
      checkpoints =
        Enum.flat_map(files, fn file ->
          if String.ends_with?(file, ".chk") do
            checkpoint_id = String.replace(file, ".chk", "")

            case File.stat(Path.join(dir, file)) do
              {:ok, stat} ->
                # Convert file time to DateTime for sorting
                timestamp =
                  case stat.mtime do
                    {{y, m, d}, {h, min, s}} ->
                      DateTime.new!(Date.new!(y, m, d), Time.new!(h, min, s))

                    other ->
                      other
                  end

                [
                  %{
                    id: checkpoint_id,
                    workflow_id: workflow_id,
                    timestamp: timestamp,
                    size: stat.size
                  }
                ]

              _ ->
                []
            end
          else
            []
          end
        end)

      {:ok, checkpoints}
    end
  end

  defp list_checkpoints(workflow_id, :memory, _opts) do
    ensure_memory_table()
    checkpoints =
      :ets.foldl(fn
        {{^workflow_id, _cp_id}, data, ts}, acc ->
          # Return full checkpoint data with timestamp
          checkpoint = Map.put(data, :timestamp, ts)
          [checkpoint | acc]
        _, acc ->
          acc
      end, [], @zixir_state_table)
    {:ok, checkpoints}
  end

  defp list_checkpoints(_, storage, _) do
    {:error, "Storage backend not supported: #{storage}"}
  end

  defp load_checkpoint(workflow_id, checkpoint_id, :memory, _opts) do
    load_from_memory(workflow_id, checkpoint_id, [])
  end

  defp load_checkpoint(workflow_id, checkpoint_id, :s3, opts) do
    bucket = Keyword.get(opts, :s3_bucket)
    key = "#{workflow_id}/checkpoints/#{checkpoint_id}.chk"

    case S3.get_object(bucket, key) do
      {:ok, data} ->
        # Check for header byte
        case data do
          <<0x01::8, rest::binary>> ->
            serialized = :erlang.binary_to_term(rest)
            {:ok, deserialize(serialized)}

          <<0x00::8, rest::binary>> ->
            serialized = :erlang.binary_to_term(rest)
            {:ok, deserialize(serialized)}

          _ ->
            # Try legacy JSON format
            try do
              serialized = Jason.decode!(data)
              {:ok, deserialize(serialized)}
            rescue
              _ ->
                serialized = :erlang.binary_to_term(data)
                {:ok, deserialize(serialized)}
            end
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:error, "S3 not configured"}
  end

  defp load_checkpoint(workflow_id, checkpoint_id, :database, opts) do
    table = Keyword.get(opts, :table, "zixir_state")

    query = "SELECT data FROM #{table} WHERE workflow_id = $1 AND checkpoint_id = $2"

    with {:ok, conn} <- Zixir.ODBC.connect(opts),
         {:ok, rows} <- Zixir.ODBC.query(conn, query, [workflow_id, checkpoint_id]),
         [%{"data" => data} | _] <- rows do
      # Check for header byte
      case data do
        <<0x01::8, rest::binary>> ->
          serialized = :erlang.binary_to_term(rest)
          {:ok, deserialize(serialized)}

        <<0x00::8, rest::binary>> ->
          serialized = :erlang.binary_to_term(rest)
          {:ok, deserialize(serialized)}

        _ ->
          # Try legacy JSON format
          try do
            serialized = Jason.decode!(data)
            {:ok, deserialize(serialized)}
          rescue
            _ ->
              serialized = :erlang.binary_to_term(data)
              {:ok, deserialize(serialized)}
          end
      end
    else
      [] -> {:error, :not_found}
      error -> error
    end
  end

  defp delete_all_checkpoints(workflow_id, :memory, _opts) do
    ensure_memory_table()
    :ets.match_delete(@zixir_state_table, {{workflow_id, :_}, :_, :_})
    :ok
  end

  defp delete_all_checkpoints(workflow_id, :disk, opts) do
    dir = get_checkpoint_dir(workflow_id, opts)
    File.rm_rf(dir)
  end

  defp delete_all_checkpoints(_, storage, _) do
    {:error, "Storage backend not supported: #{storage}"}
  end

  defp cleanup_old_checkpoints(workflow_id, storage, opts) do
    max_checkpoints = Keyword.get(opts, :max_checkpoints, @default_max_checkpoints)

    case checkpoints(workflow_id, storage, opts) do
      {:ok, checkpoints} when length(checkpoints) > max_checkpoints ->
        to_delete = Enum.drop(checkpoints, max_checkpoints)

        for %{id: id} <- to_delete do
          delete_checkpoint(workflow_id, id, storage, opts)
        end

        :ok

      _ ->
        :ok
    end
  end

  defp delete_checkpoint(workflow_id, checkpoint_id, :disk, opts) do
    dir = get_checkpoint_dir(workflow_id, opts)
    file = Path.join(dir, "#{checkpoint_id}.chk")
    File.rm(file)
  end

  defp delete_checkpoint(workflow_id, checkpoint_id, :memory, _opts) do
    ensure_memory_table()
    :ets.delete(@zixir_state_table, {workflow_id, checkpoint_id})
    :ok
  end

  defp delete_checkpoint(_, _, _, _), do: :ok
end
