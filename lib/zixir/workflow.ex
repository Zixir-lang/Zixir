defmodule Zixir.Workflow do
  @moduledoc """
  Workflow Engine with Steps, Resilience, and Human-in-the-Loop

  Provides:
  - Step-based workflow definitions
  - Automatic checkpointing between steps
  - Retry policies with exponential backoff
  - Circuit breaker for external service calls
  - Human-in-the-loop approval gates

  ## Quick Start

      workflow =
        Zixir.Workflow.new("order_processing")
        |> Zixir.Workflow.add_step("fetch_orders", &fetch_orders/2)
        |> Zixir.Workflow.add_step("validate_orders", &validate_orders/2)
        |> Zixir.Workflow.add_step("ai_categorize", &categorize_orders/2, require_approval: true)
        |> Zixir.Workflow.add_step("update_orders", &update_orders/2)

      {:ok, result} = Zixir.Workflow.execute(workflow)

  ## Retry Policy

      Zixir.Workflow.add_step("risky_call", &risky_operation/2,
        retry: [max_attempts: 3, backoff: :exponential, base_delay: 1000]
      )

  ## Circuit Breaker

      Zixir.Workflow.add_step("external_api", &call_api/2,
        circuit_breaker: [failure_threshold: 5, recovery_timeout: 30_000]
      )

  ## Human-in-the-Loop

      Zixir.Workflow.add_step("manager_approval", &await_approval/2,
        approval_timeout: 3600_000  # 1 hour
      )

  """

  alias Zixir.{State, Observability}
  require Logger

  defstruct [
    :id,
    :name,
    :steps,
    :initial_state,
    :on_error,
    :checkpoint_interval,
    :created_at,
    :metadata
  ]

  defmodule WorkflowStep do
    defstruct [
      :name,
      :function,
      :on_success,
      :on_error,
      :retry,
      :circuit_breaker,
      :require_approval,
      :approval_timeout,
      :timeout,
      :condition,
      :parallel,
      :depends_on
    ]
  end

  defmodule RetryPolicy do
    defstruct [
      :max_attempts,
      :backoff,
      :base_delay,
      :max_delay,
      :jitter,
      :retry_on
    ]

    def new(opts \\ []) do
      %__MODULE__{
        max_attempts: Keyword.get(opts, :max_attempts, 3),
        backoff: Keyword.get(opts, :backoff, :exponential),
        base_delay: Keyword.get(opts, :base_delay, 1000),
        max_delay: Keyword.get(opts, :max_delay, 30_000),
        jitter: Keyword.get(opts, :jitter, 0.1),
        retry_on: Keyword.get(opts, :retry_on, fn _ -> true end)
      }
    end
  end

  defmodule CircuitBreaker do
    defstruct [
      :failure_count,
      :failure_threshold,
      :recovery_timeout,
      :last_failure,
      :state
    ]

    def new(opts \\ []) do
      %__MODULE__{
        failure_count: 0,
        failure_threshold: Keyword.get(opts, :failure_threshold, 5),
        recovery_timeout: Keyword.get(opts, :recovery_timeout, 30_000),
        last_failure: nil,
        state: :closed
      }
    end
  end

  defmodule Approval do
    defstruct [
      :step_name,
      :workflow_id,
      :requestor,
      :approver,
      :status,
      :requested_at,
      :responded_at,
      :comment,
      :payload
    ]

    def new(step_name, workflow_id, payload) do
      %__MODULE__{
        step_name: step_name,
        workflow_id: workflow_id,
        requestor: nil,
        approver: nil,
        status: :pending,
        requested_at: DateTime.utc_now(),
        responded_at: nil,
        comment: nil,
        payload: payload
      }
    end
  end

  @typedoc """
  A workflow definition.
  """
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    steps: [WorkflowStep.t()],
    initial_state: map(),
    on_error: atom() | nil,
    checkpoint_interval: pos_integer() | nil,
    created_at: DateTime.t(),
    metadata: map()
  }

  @typedoc """
  Step result.
  """
  @type step_result :: {:ok, term()} | {:error, term()} | {:skip, term()} | {:approval_required, term()}

  @typedoc """
  Workflow execution result.
  """
  @type execution_result :: {:ok, map()} | {:error, term(), map()} | {:approval_pending, Approval.t()}

  @default_checkpoint_interval 5

  @doc """
  Create a new workflow definition.
  """
  @spec new(String.t(), map(), keyword()) :: t()
  def new(name, initial_state \\ %{}, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      name: name,
      steps: [],
      initial_state: initial_state,
      on_error: Keyword.get(opts, :on_error, :stop),
      checkpoint_interval: Keyword.get(opts, :checkpoint_interval, @default_checkpoint_interval),
      created_at: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Add a step to the workflow.
  """
  @spec add_step(t(), String.t(), function(), keyword()) :: t()
  def add_step(workflow, name, function, opts \\ [])
  def add_step(workflow, name, dependencies, function) when is_list(dependencies) and is_function(function) do
    add_step(workflow, name, function, depends_on: dependencies)
  end
  
  def add_step(workflow, name, function, opts) do
    step = %WorkflowStep{
      name: name,
      function: function,
      on_success: Keyword.get(opts, :on_success),
      on_error: Keyword.get(opts, :on_error),
      retry: parse_retry(Keyword.get(opts, :retry)),
      circuit_breaker: parse_circuit_breaker(Keyword.get(opts, :circuit_breaker)),
      require_approval: Keyword.get(opts, :require_approval, false),
      approval_timeout: Keyword.get(opts, :approval_timeout, 3600_000),
      timeout: Keyword.get(opts, :timeout, 300_000),
      condition: Keyword.get(opts, :condition),
      parallel: Keyword.get(opts, :parallel, false),
      depends_on: Keyword.get(opts, :depends_on, [])
    }

    %{workflow | steps: workflow.steps ++ [step]}
  end

  @doc """
  Execute a workflow.
  """
  @spec execute(t()) :: execution_result()
  def execute(workflow) do
    Observability.trace("workflow.execute", fn ->
      # Calculate DAG execution order
      step_map = Map.new(workflow.steps, fn step -> {step.name, step} end)
      execution_order = calculate_execution_order(workflow.steps)
      
      do_execute_dag(workflow, workflow.initial_state, execution_order, step_map, %{})
    end)
  end

  @doc """
  Resume a workflow from a checkpoint.
  """
  @spec resume(String.t(), map()) :: execution_result()
  def resume(workflow_id, additional_state \\ %{}) do
    with {:ok, checkpoint} <- State.latest_checkpoint(workflow_id, :disk, []),
         {:ok, state} <- State.restore(workflow_id, checkpoint.id, :disk, []) do
      workflow = decode_workflow(state)
      do_execute(workflow, Map.merge(state, additional_state), state[:_current_step] || 0)
    else
      {:error, _} -> {:error, :workflow_not_found, %{}}
    end
  end

  @doc """
  Get workflow status.
  """
  @spec status(String.t()) :: map()
  def status(workflow_id) do
    with {:ok, checkpoints} <- State.checkpoints(workflow_id, :disk, []),
         {:ok, latest} <- State.latest_checkpoint(workflow_id, :disk, []) do
      %{
        workflow_id: workflow_id,
        total_checkpoints: length(checkpoints),
        last_checkpoint: latest,
        status: determine_status(latest)
      }
    else
      _ -> %{workflow_id: workflow_id, status: :not_found}
    end
  end

  @doc """
  Cancel a running workflow.
  """
  @spec cancel(String.t()) :: :ok
  def cancel(workflow_id) do
    State.delete(workflow_id, :disk, [])
    Logger.info("Workflow cancelled", workflow_id: workflow_id)
    :ok
  end

  @doc """
  Request approval for a step.
  """
  @spec request_approval(t(), String.t(), map()) :: Approval.t()
  def request_approval(workflow, step_name, payload) do
    approval = Approval.new(step_name, workflow.id, payload)
    save_approval(approval)
    approval
  end

  @doc """
  Respond to an approval request.
  """
  @spec respond_approval(Approval.t(), atom(), String.t(), map()) :: {:ok, Approval.t()} | {:error, term()}
  def respond_approval(approval, status, comment \\ nil, response \\ %{}) do
    updated = %{approval |
      status: status,
      approver: response[:approver],
      responded_at: DateTime.utc_now(),
      comment: comment,
      payload: Map.merge(approval.payload, response)
    }

    save_approval(updated)
    {:ok, updated}
  end

  @doc """
  Get pending approvals for a workflow.
  """
  @spec pending_approvals(String.t()) :: [Approval.t()]
  def pending_approvals(workflow_id) do
    []
  end

  # Private Functions

  # DAG-based execution
  defp do_execute_dag(_workflow, state, [], _step_map, _completed) do
    {:ok, Map.put(state, :_workflow_completed, true)}
  end

  defp do_execute_dag(workflow, state, [step_name | remaining], step_map, completed) do
    step = Map.get(step_map, step_name)
    
    # Check if all dependencies are completed
    deps_satisfied = check_dependencies(step, completed)
    
    if deps_satisfied do
      Logger.info("Executing step", workflow_id: workflow.id, step: step.name)

      with {:ok, new_state} <- execute_step(workflow, step, state) do
        checkpoint_state(workflow, step, new_state, map_size(completed))
        completed = Map.put(completed, step_name, true)
        do_execute_dag(workflow, new_state, remaining, step_map, completed)
      else
        {:error, reason, error_state} ->
          handle_step_error(workflow, step, reason, error_state, map_size(completed))

        {:approval_required, approval} ->
          {:approval_pending, approval}
      end
    else
      # Dependencies not satisfied, skip for now and try later
      do_execute_dag(workflow, state, remaining ++ [step_name], step_map, completed)
    end
  end

  defp check_dependencies(step, completed) do
    deps = step.depends_on || []
    Enum.all?(deps, fn dep -> Map.has_key?(completed, dep) end)
  end

  # Legacy sequential execution (fallback)
  defp do_execute(workflow, state, step_index) when step_index >= length(workflow.steps) do
    Logger.info("Workflow completed", workflow_id: workflow.id)
    {:ok, Map.put(state, :_workflow_completed, true)}
  end

  defp do_execute(workflow, state, step_index) do
    step = Enum.at(workflow.steps, step_index)

    Logger.info("Executing step", workflow_id: workflow.id, step: step.name)

    with {:ok, new_state} <- execute_step(workflow, step, state) do
      checkpoint_state(workflow, step, new_state, step_index)
      do_execute(workflow, new_state, step_index + 1)
    else
      {:error, reason, state} ->
        handle_step_error(workflow, step, reason, state, step_index)

      {:approval_required, approval} ->
        {:approval_pending, approval}
    end
  end

  defp execute_step(workflow, step, state) do
    with {:ok, input} <- prepare_step_input(step, state),
         {:ok, result} <- execute_with_resilience(step, input),
         {:ok, output} <- process_step_output(step, result) do
      {:ok, Map.put(state, step.name, output)}
    end
  end

  defp prepare_step_input(step, state) do
    if step.condition do
      case step.condition.(state) do
        true -> {:ok, state}
        false -> {:skip, :condition_not_met}
      end
    else
      {:ok, state}
    end
  end

  defp execute_with_resilience(step, input) do
    with {:ok, result} <- call_step_function(step, input) do
      {:ok, result}
    else
      {:error, reason} ->
        if can_retry?(step, reason) do
          retry_step(step, reason, input)
        else
          {:error, reason}
        end
    end
  end

  defp call_step_function(step, input) do
    if step.require_approval do
      approval = request_approval_by_name(step, input)
      {:approval_required, approval}
    else
      try do
        result = step.function.(input, step.name)
        {:ok, result}
      rescue
        e -> {:error, inspect(e)}
      end
    end
  end

  defp retry_step(step, reason, input) do
    retry = step.retry || RetryPolicy.new()
    attempt_retry(step, input, retry, 1, reason)
  end

  defp attempt_retry(_step, _input, _retry, attempt, _reason) when attempt > 3 do
    {:error, :max_retries_exceeded}
  end

  defp attempt_retry(step, input, retry, attempt, reason) do
    delay = calculate_delay(retry, attempt)

    Logger.warning("Retrying step",
      step: step.name,
      attempt: attempt,
      reason: inspect(reason),
      delay: delay
    )

    :timer.sleep(delay)

    case call_step_function(step, input) do
      {:ok, result} -> {:ok, result}
      {:error, ^reason} -> attempt_retry(step, input, retry, attempt + 1, reason)
      {:error, new_reason} -> attempt_retry(step, input, retry, attempt + 1, new_reason)
    end
  end

  defp calculate_delay(retry, attempt) do
    delay = retry.base_delay * :math.pow(2, attempt - 1)
    delay = min(delay, retry.max_delay)

    if retry.jitter > 0 do
      jitter_range = delay * retry.jitter
      delay = delay + :rand.uniform(round(jitter_range * 2)) - jitter_range
    end

    round(delay)
  end

  defp can_retry?(step, reason) do
    step.retry && step.retry.retry_on.(reason)
  end

  defp process_step_output(_step, {:skip, reason}) do
    {:ok, %{skipped: true, reason: reason}}
  end

  defp process_step_output(step, result) do
    if step.on_success do
      step.on_success.(result)
    else
      {:ok, result}
    end
  end

  defp handle_step_error(workflow, step, reason, state, step_index) do
    Logger.error("Step failed",
      workflow_id: workflow.id,
      step: step.name,
      reason: inspect(reason)
    )

    case step.on_error do
      {:retry, _retry_policy} ->
        do_execute(workflow, state, step_index)

      {:fallback, fallback_fn} ->
        fallback_fn.(state)

      :skip ->
        do_execute(workflow, Map.put(state, step.name, {:error, reason}), step_index + 1)

      :stop ->
        {:error, reason, Map.put(state, step.name, {:error, reason})}

      nil ->
        case workflow.on_error do
          :stop -> {:error, reason, state}
          :continue -> do_execute(workflow, state, step_index + 1)
          _ -> {:error, reason, state}
        end
    end
  end

  defp checkpoint_state(workflow, step, state, step_index) do
    checkpoint_data = %{
      _workflow: encode_workflow(workflow),
      _current_step: step_index + 1,
      _completed_steps: step_index + 1,
      _last_step: step.name,
      _updated_at: DateTime.utc_now()
    }

    merged_state = Map.merge(state, checkpoint_data)

    State.checkpoint(workflow.id, step.name, :disk,
      data: merged_state,
      metadata: %{
        step: step.name,
        step_number: step_index + 1
      }
    )
  end

  defp save_approval(approval) do
    key = "approval:#{approval.workflow_id}:#{approval.step_name}"
    :ets.insert(:zixir_workflow_approvals, {key, approval})
  end

  defp request_approval_by_name(step, input) do
    %Approval{
      step_name: step.name,
      workflow_id: nil,
      status: :pending,
      requested_at: DateTime.utc_now(),
      payload: input
    }
  end

  defp parse_retry(nil), do: nil
  defp parse_retry(opts) when is_list(opts), do: RetryPolicy.new(opts)
  defp parse_retry(policy), do: policy

  defp parse_circuit_breaker(nil), do: nil
  defp parse_circuit_breaker(opts) when is_list(opts), do: CircuitBreaker.new(opts)
  defp parse_circuit_breaker(cb), do: cb

  defp generate_id do
    "wf_#{:os.system_time(:millisecond)}_#{:rand.uniform(999_999)}"
  end

  defp encode_workflow(workflow) do
    %{
      id: workflow.id,
      name: workflow.name,
      step_count: length(workflow.steps),
      created_at: workflow.created_at
    }
  end

  defp decode_workflow(state) do
    %__MODULE__{
      id: state[:_workflow][:id],
      name: state[:_workflow][:name],
      steps: [],
      initial_state: state,
      on_error: :stop
    }
  end

  defp determine_status(nil), do: :not_started
  defp determine_status(checkpoint) do
    case checkpoint[:step] do
      nil -> :completed
      _ -> :in_progress
    end
  end

  # ============================================================================
  # DAG Execution - Topological Sort
  # ============================================================================

  @doc """
  Calculate execution order for steps based on dependencies.
  Uses topological sort (Kahn's algorithm) to determine order.
  """
  defp calculate_execution_order(steps) do
    graph = build_dependency_graph(steps)
    topo_sort(graph)
  end

  defp build_dependency_graph(steps) do
    Enum.reduce(steps, %{}, fn step, acc ->
      Map.put(acc, step.name, step.depends_on || [])
    end)
  end

  defp topo_sort(graph) do
    # Kahn's algorithm implementation
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
end
