defmodule Zixir.Workflow.Step do
  @moduledoc """
  Represents a single step in a workflow.
  """
  
  defstruct [
    :name,
    :func,
    :depends_on,
    :timeout,
    :retries,
    :checkpoint
  ]
end

defmodule Zixir.Workflow.Execution do
  @moduledoc """
  Represents the execution state of a workflow.
  """
  
  defstruct [
    :id,
    :workflow,
    :opts,
    :status,
    :started_at,
    :completed_at,
    :caller,
    :state,
    :resumed_from,
    :error,
    :failed_step
  ]
end

defmodule Zixir.Workflow.Checkpoint do
  @moduledoc """
  Checkpoint management for workflow state persistence.
  """
  
  require Logger
  
  @doc """
  Save a checkpoint for a workflow.
  """
  def save(workflow_name, execution_id, data, opts \\ []) do
    dir = Keyword.get(opts, :dir, "_zixir_workflows")
    checkpoint_dir = Path.join([dir, workflow_name, "checkpoints"])
    File.mkdir_p!(checkpoint_dir)
    
    checkpoint_id = generate_checkpoint_id()
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    
    checkpoint = %{
      id: checkpoint_id,
      execution_id: execution_id,
      workflow_name: workflow_name,
      timestamp: timestamp,
      completed_steps: Keyword.get(data, :completed_steps, []),
      state: Keyword.get(data, :state, %{})
    }
    
    file = Path.join(checkpoint_dir, "#{checkpoint_id}.bin")
    
    # Use Erlang term_to_binary for serialization (handles all Elixir types including tuples)
    binary_data = :erlang.term_to_binary(checkpoint)
    
    case File.write(file, binary_data) do
      :ok ->
        Logger.debug("Checkpoint saved: #{file}")
        {:ok, checkpoint_id}
      
      {:error, reason} ->
        Logger.error("Failed to save checkpoint: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Load a specific checkpoint.
  """
  def load(workflow_name, checkpoint_id, dir \\ "_zixir_workflows") do
    file = Path.join([dir, workflow_name, "checkpoints", "#{checkpoint_id}.bin"])
    
    case File.read(file) do
      {:ok, content} ->
        try do
          checkpoint = :erlang.binary_to_term(content)
          {:ok, checkpoint}
        rescue
          _ -> {:error, "Invalid checkpoint format"}
        end
      
      {:error, reason} ->
        {:error, "Failed to load checkpoint: #{reason}"}
    end
  end
  
  @doc """
  Find the latest checkpoint for a workflow.
  """
  def find_latest(workflow_name, dir \\ "_zixir_workflows") do
    checkpoint_dir = Path.join([dir, workflow_name, "checkpoints"])
    
    case File.ls(checkpoint_dir) do
      {:ok, files} ->
        checkpoints = files
        |> Enum.filter(&String.ends_with?(&1, ".bin"))
        |> Enum.map(fn file ->
          case File.read(Path.join(checkpoint_dir, file)) do
            {:ok, content} -> 
              try do
                checkpoint = :erlang.binary_to_term(content)
                checkpoint
              rescue
                _ -> nil
              end
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.timestamp, :desc)
        
        case checkpoints do
          [latest | _] -> latest
          [] -> nil
        end
      
      {:error, _} ->
        nil
    end
  end
  
  @doc """
  List all checkpoints for a workflow.
  """
  def list(workflow_name, dir \\ "_zixir_workflows") do
    checkpoint_dir = Path.join([dir, workflow_name, "checkpoints"])
    
    case File.ls(checkpoint_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".bin"))
        |> Enum.map(fn file ->
          case File.read(Path.join(checkpoint_dir, file)) do
            {:ok, content} -> 
              try do
                checkpoint = :erlang.binary_to_term(content)
                checkpoint
              rescue
                _ -> nil
              end
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.timestamp, :desc)
      
      {:error, _} ->
        []
    end
  end
  
  @doc """
  Clean up old checkpoints, keeping only the most recent N.
  """
  def cleanup(workflow_name, opts \\ []) do
    keep = Keyword.get(opts, :keep, 5)
    dir = Keyword.get(opts, :dir, "_zixir_workflows")
    checkpoint_dir = Path.join([dir, workflow_name, "checkpoints"])
    
    checkpoints = list(workflow_name, dir)
    
    if length(checkpoints) > keep do
      to_delete = Enum.drop(checkpoints, keep)
      
      Enum.each(to_delete, fn checkpoint ->
        file = Path.join(checkpoint_dir, "#{checkpoint.id}.bin")
        File.rm(file)
        Logger.debug("Deleted old checkpoint: #{file}")
      end)
    end
    
    :ok
  end
  
  defp generate_checkpoint_id do
    Zixir.Utils.generate_id(prefix: "chk_", bytes: 8)
  end
end
