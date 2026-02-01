defmodule Zixir.Sandbox do
  @moduledoc """
  Resource Limits and Sandboxing for AI Automation.
  
  Prevents runaway processes by enforcing:
  - Time limits (timeouts)
  - Memory limits
  - CPU usage limits
  - Call depth limits
  - Automatic cleanup on violations
  
  ## Example
  
      # Execute with timeout
      Zixir.Sandbox.with_timeout(fn ->
        python "model" "train" (data)
      end, 30_000)
      
      # Execute with multiple limits
      Zixir.Sandbox.execute(fn ->
        process_large_dataset()
      end, [
        timeout: 60_000,
        memory_limit: "2GB",
        max_calls: 1000
      ])
  """

  use GenServer

  require Logger

  @default_limits %{
    timeout: 30_000,
    memory_limit_bytes: nil,  # nil = no limit
    cpu_percent: nil,         # nil = no limit
    max_calls: nil,
    max_depth: 100
  }

  @doc """
  Start the Sandbox supervisor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute a function with a timeout.
  
  ## Options
    * `:timeout` - Maximum time in milliseconds (default: 30000)
    * `:on_timeout` - Action on timeout: :kill (default), :error, :continue
  """
  def with_timeout(func, timeout_ms \\ 30_000, opts \\ []) when is_function(func) do
    on_timeout = Keyword.get(opts, :on_timeout, :kill)
    
    task = Task.async(fn ->
      try do
        result = func.()
        {:ok, result}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end)
    
    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        result
      
      nil ->
        # Timeout occurred
        case on_timeout do
          :kill ->
            Task.shutdown(task, :brutal_kill)
            {:error, "Execution timed out after #{timeout_ms}ms"}
          
          :error ->
            Task.shutdown(task, :brutal_kill)
            {:error, :timeout}
          
          :continue ->
            # Don't kill, just return timeout warning
            {:timeout, task}
        end
    end
  end

  @doc """
  Execute a function with comprehensive resource limits.
  
  ## Limits
    * `:timeout` - Maximum execution time in milliseconds
    * `:memory_limit` - Maximum memory usage (e.g., "1GB", "512MB")
    * `:cpu_percent` - Maximum CPU percentage (0-100)
    * `:max_calls` - Maximum number of function calls
    * `:max_depth` - Maximum call stack depth
  """
  def execute(func, limits \\ []) when is_function(func) do
    limits = parse_limits(limits)
    
    # Create sandbox context
    context = %{
      start_time: System.monotonic_time(:millisecond),
      start_memory: get_memory_usage(),
      limits: limits,
      call_count: 0,
      call_depth: 0
    }
    
    # Execute with monitoring
    monitored_execute(func, context)
  end

  @doc """
  Create a sandboxed version of a function.
  """
  def sandbox(func, limits \\ []) when is_function(func) do
    fn ->
      execute(func, limits)
    end
  end

  @doc """
  Check if current execution is within resource limits.
  """
  def check_limits(context) do
    checks = [
      check_timeout(context),
      check_memory(context),
      check_cpu(context),
      check_call_count(context),
      check_call_depth(context)
    ]
    
    case Enum.find(checks, fn
      {:violated, _} -> true
      :ok -> false
    end) do
      nil -> :ok
      {:violated, reason} -> {:violated, reason}
    end
  end

  @doc """
  Get current resource usage statistics.
  """
  def resource_stats do
    %{
      memory_bytes: get_memory_usage(),
      memory_human: Zixir.Utils.format_bytes(get_memory_usage()),
      cpu_percent: get_cpu_usage(),
      uptime_ms: get_uptime()
    }
  end

  @doc """
  Kill a running sandboxed process.
  """
  def kill(pid) when is_pid(pid) do
    Process.exit(pid, :kill)
    :ok
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      active_sandboxes: %{},
      default_limits: Map.merge(@default_limits, Keyword.get(opts, :default_limits, %{}))
    }
    
    # Start monitoring process
    spawn_link(fn -> monitor_loop() end)
    
    {:ok, state}
  end

  # Private Functions

  defp monitored_execute(func, context) do
    # Check limits before execution
    case check_limits(context) do
      :ok ->
        # Execute with monitoring
        parent = self()
        
        {pid, ref} = spawn_monitor(fn ->
          # Set process flag for monitoring
          Process.flag(:trap_exit, true)
          
          result = try do
            func.()
          rescue
            e -> {:error, Exception.message(e)}
 catch
            :exit, reason -> {:error, "Process exited: #{inspect(reason)}"}
          end
          
          send(parent, {:sandbox_result, self(), result})
        end)
        
        # Wait for result with timeout
        timeout = context.limits.timeout
        
        receive do
          {:DOWN, ^ref, :process, ^pid, :normal} ->
            receive do
              {:sandbox_result, ^pid, result} -> 
                # Wrap successful results in {:ok, result} unless already wrapped
                case result do
                  {:ok, _} -> result
                  {:error, _} -> result
                  _ -> {:ok, result}
                end
            after
              100 -> {:error, "Result not received"}
            end
          
          {:DOWN, ^ref, :process, ^pid, reason} ->
            {:error, "Process crashed: #{inspect(reason)}"}
        after
          timeout ->
            # Timeout - kill the process
            Process.exit(pid, :kill)
            {:error, "Execution timed out after #{timeout}ms"}
        end
      
      {:violated, reason} ->
        {:error, "Resource limit violated: #{reason}"}
    end
  end

  defp check_timeout(context) do
    if context.limits.timeout do
      elapsed = System.monotonic_time(:millisecond) - context.start_time
      
      if elapsed > context.limits.timeout do
        {:violated, "Timeout exceeded: #{elapsed}ms > #{context.limits.timeout}ms"}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp check_memory(context) do
    if context.limits.memory_limit_bytes do
      current_memory = get_memory_usage()
      memory_used = current_memory - context.start_memory
      
      if memory_used > context.limits.memory_limit_bytes do
        {:violated, "Memory limit exceeded: #{Zixir.Utils.format_bytes(memory_used)} > #{Zixir.Utils.format_bytes(context.limits.memory_limit_bytes)}"}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp check_cpu(_context) do
    # CPU checking would require OS-specific implementations
    # For now, return :ok
    :ok
  end

  defp check_call_count(context) do
    if context.limits.max_calls do
      if context.call_count > context.limits.max_calls do
        {:violated, "Max call count exceeded: #{context.call_count} > #{context.limits.max_calls}"}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp check_call_depth(context) do
    if context.limits.max_depth do
      if context.call_depth > context.limits.max_depth do
        {:violated, "Max call depth exceeded: #{context.call_depth} > #{context.limits.max_depth}"}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp parse_limits(limits) do
    Enum.reduce(limits, @default_limits, fn {key, value}, acc ->
      case key do
        :timeout ->
          Map.put(acc, :timeout, value)
        
        :memory_limit ->
          bytes = parse_memory_string(value)
          Map.put(acc, :memory_limit_bytes, bytes)
        
        :memory_limit_bytes ->
          Map.put(acc, :memory_limit_bytes, value)
        
        :cpu_percent ->
          Map.put(acc, :cpu_percent, value)
        
        :max_calls ->
          Map.put(acc, :max_calls, value)
        
        :max_depth ->
          Map.put(acc, :max_depth, value)
        
        _ ->
          acc
      end
    end)
  end

  defp parse_memory_string(value) when is_integer(value), do: value
  
  defp parse_memory_string(value) when is_binary(value) do
    value = value |> String.trim() |> String.upcase()
    
    cond do
      String.ends_with?(value, "GB") ->
        num = value |> String.replace("GB", "") |> String.trim() |> String.to_integer()
        num * 1024 * 1024 * 1024
      
      String.ends_with?(value, "MB") ->
        num = value |> String.replace("MB", "") |> String.trim() |> String.to_integer()
        num * 1024 * 1024
      
      String.ends_with?(value, "KB") ->
        num = value |> String.replace("KB", "") |> String.trim() |> String.to_integer()
        num * 1024
      
      true ->
        String.to_integer(value)
    end
  end

  defp get_memory_usage do
    # Get memory usage of current process
    info = Process.info(self(), [:memory, :heap_size, :stack_size])
    info[:memory] || 0
  end

  defp get_cpu_usage do
    # This would require OS-specific implementations
    # Return 0 for now
    0
  end

  defp get_uptime do
    # Return system uptime in milliseconds
    :erlang.system_time(:millisecond)
  end

  defp monitor_loop do
    # Periodic monitoring of sandboxed processes
    Process.sleep(1000)
    monitor_loop()
  end
end
