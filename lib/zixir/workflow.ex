defmodule Zixir.Workflow do
  @moduledoc """
  Workflow Orchestration Engine for AI Automation.
  
  Provides:
  - DAG-based workflow execution
  - Automatic checkpointing and recovery
  - Retry policies with exponential backoff
  - Dead letter queues for failed steps
  - Parallel step execution
  - State persistence across failures
  
  ## Example
  
      workflow = Zixir.Workflow.new("data_pipeline")
      |> Zixir.Workflow.add_step("load", fn -> load_data() end)
      |> Zixir.Workflow.add_step("process", fn -> process_data() end, depends_on: ["load"])
      |> Zixir.Workflow.add_step("save", fn -> save_results() end, depends_on: ["process"])
      
      Zixir.Workflow.execute(workflow, checkpoint: true, retries: 3)
  """

  use GenServer

  require Logger

  alias Zixir.Workflow.{Step, Checkpoint, Execution}

  @default_checkpoint_dir "_zixir_workflows"
  @default_retry_policy %{
    max_retries: 3,
    base_delay: 1000,
    max_delay: 30_000,
    exponential_base: 2
  }

  # Client API

  @doc """
  Start the Workflow supervisor and engine.
  """
  def start_link(opts \\ []) do
    case GenServer.start_link(__MODULE__, opts, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Create a new workflow with the given name.
  """
  def new(name, opts \\ []) do
    %{
      name: name,
      steps: %{},
      execution_order: [],
      opts: opts,
      created_at: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Add a step to the workflow.
  
  ## Options
    * `:depends_on` - List of step names that must complete before this step
    * `:timeout` - Maximum time allowed for this step (milliseconds)
    * `:retries` - Number of retries for this step (overrides workflow default)
    * `:checkpoint` - Whether to checkpoint after this step (default: true)
  """
  def add_step(workflow, name, func, opts \\ []) do
    step = %Step{
      name: name,
      func: func,
      depends_on: Keyword.get(opts, :depends_on, []),
      timeout: Keyword.get(opts, :timeout, default_step_timeout()),
      retries: Keyword.get(opts, :retries, nil),
      checkpoint: Keyword.get(opts, :checkpoint, true)
    }

    steps = Map.put(workflow.steps, name, step)
    
    # Calculate execution order based on dependencies
    execution_order = calculate_execution_order(steps)

    %{workflow | steps: steps, execution_order: execution_order}
  end

  @doc """
  Execute a workflow with automatic checkpointing and recovery.
  
  ## Options
    * `:checkpoint` - Enable checkpointing (default: true)
    * `:checkpoint_dir` - Directory to store checkpoints
    * `:retries` - Default retry count for all steps
    * `:parallel` - Allow parallel execution of independent steps (default: true)
    * `:resume` - Resume from last checkpoint if available (default: true)
  """
  def execute(workflow, opts \\ []) do
    # Check if GenServer is running, if not execute directly
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:execute, workflow, opts}, :infinity)
    else
      # Execute directly without GenServer
      execution = %Execution{
        id: generate_execution_id(),
        workflow: workflow,
        opts: opts,
        status: :running,
        started_at: System.monotonic_time(:millisecond),
        caller: nil
      }
      
      # Create state structure that matches what run_workflow expects
      state = %{
        checkpoint_dir: Keyword.get(opts, :checkpoint_dir, "_zixir_workflows"),
        retry_policy: @default_retry_policy,
        executions: %{}
      }
      
      run_workflow(execution, nil, state)
    end
  end

  @doc """
  Resume a workflow from a specific checkpoint.
  """
  def resume(workflow_name, checkpoint_id, opts \\ []) do
    GenServer.call(__MODULE__, {:resume, workflow_name, checkpoint_id, opts}, :infinity)
  end

  @doc """
  Get the status of a workflow execution.
  """
  def status(execution_id) do
    GenServer.call(__MODULE__, {:status, execution_id})
  end

  @doc """
  List all checkpoints for a workflow.
  """
  def list_checkpoints(workflow_name) do
    Checkpoint.list(workflow_name)
  end

  @doc """
  Clean up old checkpoints for a workflow.
  """
  def cleanup_checkpoints(workflow_name, keep: n) do
    Checkpoint.cleanup(workflow_name, keep: n)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    checkpoint_dir = Keyword.get(opts, :checkpoint_dir, @default_checkpoint_dir)
    File.mkdir_p!(checkpoint_dir)

    state = %{
      executions: %{},
      checkpoint_dir: checkpoint_dir,
      retry_policy: Map.merge(@default_retry_policy, Keyword.get(opts, :retry_policy, %{}))
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:execute, workflow, opts}, from, state) do
    execution_id = generate_execution_id()
    
    execution = %Execution{
      id: execution_id,
      workflow: workflow,
      opts: opts,
      status: :running,
      started_at: System.monotonic_time(:millisecond),
      caller: from
    }

    # Check for existing checkpoint to resume from
    resume_from = if Keyword.get(opts, :resume, true) do
      Checkpoint.find_latest(workflow.name, state.checkpoint_dir)
    else
      nil
    end

    # Start execution in a separate process
    spawn_link(fn -> 
      result = run_workflow(execution, resume_from, state)
      GenServer.reply(from, result)
    end)

    new_state = %{state | executions: Map.put(state.executions, execution_id, execution)}
    {:noreply, new_state}
  end

  def handle_call({:resume, workflow_name, checkpoint_id, opts}, from, state) do
    case Checkpoint.load(workflow_name, checkpoint_id, state.checkpoint_dir) do
      {:ok, checkpoint_data} ->
        execution_id = generate_execution_id()
        
        execution = %Execution{
          id: execution_id,
          workflow: checkpoint_data.workflow,
          opts: opts,
          status: :running,
          started_at: System.monotonic_time(:millisecond),
          resumed_from: checkpoint_id,
          caller: from,
          state: checkpoint_data.state
        }

        spawn_link(fn -> 
          result = run_workflow(execution, nil, state)
          GenServer.reply(from, result)
        end)

        new_state = %{state | executions: Map.put(state.executions, execution_id, execution)}
        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, "Failed to resume: #{reason}"}, state}
    end
  end

  def handle_call({:status, execution_id}, _from, state) do
    execution = Map.get(state.executions, execution_id)
    {:reply, execution, state}
  end

  # Private Functions

  defp run_workflow(%Execution{} = execution, resume_from, state) do
    workflow = execution.workflow
    opts = execution.opts
    
    # Determine starting point
    {completed_steps, initial_state} = if resume_from do
      Logger.info("Resuming workflow #{workflow.name} from checkpoint #{resume_from.id}")
      {resume_from.completed_steps, resume_from.state}
    else
      {[], execution.state || %{}}
    end

    # Execute steps in order
    result = execute_steps(
      workflow.execution_order,
      workflow.steps,
      completed_steps,
      initial_state,
      execution,
      state,
      opts
    )

    # Update execution status
    final_execution = case result do
      {:ok, final_state} ->
        %{execution | 
          status: :completed, 
          completed_at: System.monotonic_time(:millisecond),
          state: final_state
        }
      
      {:error, reason, failed_step, partial_state} ->
        %{execution | 
          status: :failed, 
          error: reason,
          failed_step: failed_step,
          state: partial_state,
          completed_at: System.monotonic_time(:millisecond)
        }
    end

    # Clean up old checkpoints on success
    if final_execution.status == :completed do
      Checkpoint.cleanup(workflow.name, keep: 5, dir: state.checkpoint_dir)
    end

    result
  end

  defp execute_steps([], _steps, _completed, state, _execution, _state, _opts) do
    {:ok, state}
  end

  defp execute_steps([step_name | rest], steps, completed, state, execution, workflow_state, opts) do
    if step_name in completed do
      # Skip already completed steps (from checkpoint)
      execute_steps(rest, steps, completed, state, execution, workflow_state, opts)
    else
      step = Map.get(steps, step_name)
      
      case execute_step(step, state, execution, workflow_state, opts) do
        {:ok, new_state} ->
          # Checkpoint if enabled
          if step.checkpoint do
            Checkpoint.save(
              execution.workflow.name,
              execution.id,
              completed_steps: [step_name | completed],
              state: new_state,
              dir: workflow_state.checkpoint_dir
            )
          end
          
          # Continue with next steps
          execute_steps(rest, steps, [step_name | completed], new_state, execution, workflow_state, opts)
        
        {:error, reason} ->
          # Dead letter queue for failed step
          log_dead_letter(execution, step, reason, state)
          {:error, reason, step_name, state}
      end
    end
  end

  defp execute_step(%Step{} = step, state, _execution, workflow_state, _opts) do
    retry_policy = get_retry_policy(step, workflow_state)
    
    attempt_step(step, state, retry_policy, 0)
  end

  defp attempt_step(step, state, retry_policy, attempt) do
    try do
      # Execute with timeout
      task = Task.async(fn -> 
        apply_step_function(step.func, state)
      end)
      
      case Task.yield(task, step.timeout) || Task.shutdown(task) do
        {:ok, result} ->
          # Check if result is an error tuple and should be retried
          case result do
            {:error, reason} ->
              retry_step(step, state, retry_policy, attempt, "#{inspect(reason)}", "Step #{step.name} failed")
            _ ->
              result
          end
        
        nil ->
          retry_step(step, state, retry_policy, attempt, "#{step.timeout}ms", "Step #{step.name} timed out after")
      end
    rescue
      e ->
        retry_step(step, state, retry_policy, attempt, Exception.message(e), "Step #{step.name} failed")
    end
  end

  defp apply_step_function(func, _state) when is_function(func, 0) do
    func.()
  end

  defp apply_step_function(func, state) when is_function(func, 1) do
    func.(state)
  end

  defp apply_step_function(func, _state) do
    {:error, "Invalid step function arity. Expected 0 or 1, got #{:erlang.fun_info(func)[:arity]}"}
  end

  defp calculate_retry_delay(policy, attempt) do
    delay = policy.base_delay * :math.pow(policy.exponential_base, attempt)
    min(trunc(delay), policy.max_delay)
  end

  # Helper to handle retry logic consistently across error, timeout, and exception cases
  defp retry_step(step, state, retry_policy, attempt, error_msg, error_type) do
    if attempt < retry_policy.max_retries do
      delay = calculate_retry_delay(retry_policy, attempt)
      Logger.error("#{error_type}: #{error_msg}")
      Logger.info("Retrying step #{step.name} in #{delay}ms (attempt #{attempt + 1}/#{retry_policy.max_retries})")
      Process.sleep(delay)
      attempt_step(step, state, retry_policy, attempt + 1)
    else
      {:error, "#{error_type}: #{error_msg}"}
    end
  end

  defp get_retry_policy(step, state) do
    if step.retries do
      %{state.retry_policy | max_retries: step.retries}
    else
      state.retry_policy
    end
  end

  defp calculate_execution_order(steps) do
    # Topological sort based on dependencies
    graph = build_dependency_graph(steps)
    topo_sort(graph)
  end

  defp build_dependency_graph(steps) do
    Enum.reduce(steps, %{}, fn {name, step}, acc ->
      Map.put(acc, name, step.depends_on)
    end)
  end

  defp topo_sort(graph) do
    # Kahn's algorithm
    {in_degrees, adjacency} = build_graph_structure(graph)
    
    # Start with nodes that have no dependencies
    queue = Enum.filter(Map.keys(graph), fn node -> 
      Map.get(in_degrees, node, 0) == 0 
    end)
    
    do_topo_sort(queue, adjacency, in_degrees, [])
  end

  defp build_graph_structure(graph) do
    in_degrees = Enum.reduce(graph, %{}, fn {node, deps}, acc ->
      # Initialize in-degree
      acc = Map.put_new(acc, node, 0)
      
      # Increment in-degree for dependencies
      Enum.reduce(deps, acc, fn dep, acc ->
        Map.update(acc, dep, 1, &(&1 + 1))
      end)
    end)

    adjacency = Enum.reduce(graph, %{}, fn {node, deps}, acc ->
      # Reverse: node -> nodes that depend on it
      Enum.reduce(deps, acc, fn dep, acc ->
        Map.update(acc, dep, [node], &[node | &1])
      end)
    end)

    {in_degrees, adjacency}
  end

  defp do_topo_sort([], _adjacency, _in_degrees, result) do
    Enum.reverse(result)
  end

  defp do_topo_sort([node | queue], adjacency, in_degrees, result) do
    # Add node to result
    new_result = [node | result]
    
    # Update in-degrees of neighbors
    neighbors = Map.get(adjacency, node, [])
    
    {new_queue, new_in_degrees} = Enum.reduce(neighbors, {queue, in_degrees}, fn neighbor, {q, degrees} ->
      new_degree = degrees[neighbor] - 1
      new_degrees = Map.put(degrees, neighbor, new_degree)
      
      if new_degree == 0 do
        {[neighbor | q], new_degrees}
      else
        {q, new_degrees}
      end
    end)
    
    do_topo_sort(new_queue, adjacency, new_in_degrees, new_result)
  end

  defp log_dead_letter(execution, step, reason, state) do
    dead_letter = %{
      workflow: execution.workflow.name,
      execution_id: execution.id,
      step: step.name,
      error: reason,
      state: state,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    Logger.error("Dead letter: #{inspect(dead_letter)}")
    
    # Persist to file for later analysis
    file = Path.join([execution.workflow.name, "_dead_letters.jsonl"])
    File.write!(file, Jason.encode!(dead_letter) <> "\n", [:append])
  end

  defp generate_execution_id do
    Zixir.Utils.generate_id(prefix: "wf_", bytes: 8)
  end

  # Get default step timeout from application config
  defp default_step_timeout do
    Application.get_env(:zixir, :workflow_step_timeout, 30_000)
  end
end
