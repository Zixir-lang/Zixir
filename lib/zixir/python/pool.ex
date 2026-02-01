defmodule Zixir.Python.Pool do
  @moduledoc """
  Enhanced pool of Python port workers with load balancing and health monitoring.
  """

  require Logger

  @doc """
  Call Python with automatic load balancing across workers.
  Supports kwargs for Python functions.
  """
  def call(module, function, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, default_timeout())
    kwargs = Keyword.get(opts, :kwargs, [])
    
    case Zixir.Python.CircuitBreaker.allow?() do
      :ok ->
        case get_healthy_worker() do
          {:ok, pid} ->
            result = Zixir.Python.Worker.call(pid, module, function, args, 
              timeout: timeout, 
              kwargs: kwargs,
              retries: 2
            )
            
            case result do
              {:ok, _} -> Zixir.Python.CircuitBreaker.record_success()
              {:error, reason} -> 
                Logger.warning("Python call failed: #{inspect(reason)}")
                Zixir.Python.CircuitBreaker.record_failure()
            end
            
            result
          
          {:error, :no_healthy_workers} ->
            # Try any worker as fallback
            case get_any_worker() do
              {:ok, pid} ->
                result = Zixir.Python.Worker.call(pid, module, function, args, 
                  timeout: timeout, 
                  kwargs: kwargs
                )
                
                case result do
                  {:ok, _} -> Zixir.Python.CircuitBreaker.record_success()
                  {:error, _} -> Zixir.Python.CircuitBreaker.record_failure()
                end
                
                result
              
              error ->
                Zixir.Python.CircuitBreaker.record_failure()
                error
            end
          
          error ->
            Zixir.Python.CircuitBreaker.record_failure()
            error
        end
      
      {:error, :circuit_open} ->
        {:error, :circuit_open}
    end
  end

  @doc """
  Call Python and automatically convert result to expected type.
  """
  def call_with_conversion(module, function, args, expected_type, opts \\ []) do
    case call(module, function, args, opts) do
      {:ok, result} ->
        case convert_type(result, expected_type) do
          {:ok, converted} -> {:ok, converted}
          {:error, reason} -> {:error, "Type conversion failed: #{reason}"}
        end
      
      error ->
        error
    end
  end

  @doc """
  Execute multiple Python calls in parallel.
  """
  def parallel_calls(calls, opts \\ []) when is_list(calls) do
    timeout = Keyword.get(opts, :timeout, default_timeout())
    
    tasks = Enum.map(calls, fn {module, function, args} ->
      Task.async(fn ->
        call(module, function, args, timeout: timeout)
      end)
    end)
    
    Task.await_many(tasks, timeout + 5_000)
  end

  @doc """
  Get pool statistics.
  """
  def stats() do
    workers = Registry.select(Zixir.Python.Registry, [{{:_, :"$1", :_}, [], [:"$1"]}])
    
    %{
      total_workers: length(workers),
      healthy_workers: count_healthy_workers(),
      circuit_state: get_circuit_state()
    }
  end

  # Private functions

  defp get_healthy_worker() do
    # Get all workers and check health
    workers = Registry.select(Zixir.Python.Registry, [{{:_, :"$1", :_}, [], [:"$1"]}])
    
    # Try workers in random order for load balancing
    workers
    |> Enum.shuffle()
    |> Enum.find_value({:error, :no_healthy_workers}, fn pid ->
      case Zixir.Python.Worker.health_check(pid) do
        {:ok, :healthy} -> {:ok, pid}
        _ -> nil
      end
    end)
  end

  defp get_any_worker() do
    workers = Registry.select(Zixir.Python.Registry, [{{:_, :"$1", :_}, [], [:"$1"]}])
    
    case workers do
      [] -> {:error, :no_workers}
      [pid | _] -> {:ok, pid}
    end
  end

  defp count_healthy_workers() do
    workers = Registry.select(Zixir.Python.Registry, [{{:_, :"$1", :_}, [], [:"$1"]}])
    
    Enum.count(workers, fn pid ->
      case Zixir.Python.Worker.health_check(pid) do
        {:ok, :healthy} -> true
        _ -> false
      end
    end)
  end

  defp get_circuit_state() do
    # This would need to be exposed from CircuitBreaker
    :unknown
  end

  defp convert_type(value, :list) when is_list(value), do: {:ok, value}
  defp convert_type(value, :number) when is_number(value), do: {:ok, value}
  defp convert_type(value, :string) when is_binary(value), do: {:ok, value}
  defp convert_type(value, :map) when is_map(value), do: {:ok, value}
  defp convert_type(value, :boolean) when is_boolean(value), do: {:ok, value}
  
  defp convert_type(value, :float) when is_number(value), do: {:ok, value / 1}
  defp convert_type(value, :int) when is_number(value), do: {:ok, trunc(value)}
  
  defp convert_type(value, :numpy_array) when is_list(value), do: {:ok, value}
  defp convert_type(%{"columns" => _, "data" => _} = value, :pandas_df), do: {:ok, value}
  
  defp convert_type(value, expected) do
    {:error, "Cannot convert #{inspect(value)} to #{expected}"}
  end

  # Get default timeout from application config
  defp default_timeout do
    Application.get_env(:zixir, :python_timeout, 30_000)
  end
end
