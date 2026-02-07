defmodule Zixir.Observability do
  @moduledoc """
  Structured Observability for AI Automation.
  
  Provides:
  - Structured JSON logging
  - Execution tracing with spans
  - Metrics collection
  - Automatic error reporting
  - Performance monitoring
  
  ## Example
  
      # Structured logging
      Zixir.Observability.info("Processing batch", batch_id: id, size: length(data))
      
      # Execution tracing
      Zixir.Observability.trace("data_pipeline", fn ->
        process_data()
      end)
      
      # Metrics
      Zixir.Observability.record_metric("predictions_per_second", 100)
  """

  use GenServer

  require Logger

  @default_config %{
    log_format: :json,
    log_level: :info,
    trace_enabled: true,
    metrics_enabled: true,
    log_file: nil,
    max_log_size: 100 * 1024 * 1024,  # 100MB
    max_log_files: 5
  }

  # Client API

  @doc """
  Start the Observability service.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case GenServer.start_link(__MODULE__, opts, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  # Logging Functions

  @doc """
  Log at debug level with structured data.
  """
  @spec debug(String.t(), keyword()) :: :ok
  def debug(message, metadata \\ []) do
    log(:debug, message, metadata)
  end

  @doc """
  Log at info level with structured data.
  """
  @spec info(String.t(), keyword()) :: :ok
  def info(message, metadata \\ []) do
    log(:info, message, metadata)
  end

  @doc """
  Log at warning level with structured data.
  """
  @spec warning(String.t(), keyword()) :: :ok
  def warning(message, metadata \\ []) do
    log(:warning, message, metadata)
  end

  @doc """
  Log at error level with structured data.
  """
  @spec error(String.t(), keyword()) :: :ok
  def error(message, metadata \\ []) do
    log(:error, message, metadata)
  end

  @doc """
  Send an alert for critical events.
  """
  @spec alert(String.t(), keyword()) :: :ok
  def alert(message, metadata \\ []) do
    log(:error, "ALERT: #{message}", metadata)
    
    # Also increment alert counter metric
    increment_counter("alerts_total", 1, [alert_type: message])
  end

  @doc """
  Log workflow step execution.
  """
  @spec log_step(String.t(), String.t(), atom(), keyword()) :: :ok
  def log_step(workflow_name, step_name, status, metadata \\ []) do
    log(:info, "Workflow step #{status}", [
      workflow: workflow_name,
      step: step_name,
      status: status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    ] ++ metadata)
  end

  # Tracing Functions

  @doc """
  Start a trace span.
  """
  def start_span(name, parent_id \\ nil, metadata \\ []) do
    GenServer.call(__MODULE__, {:start_span, name, parent_id, metadata})
  end

  @doc """
  End a trace span.
  """
  def end_span(span_id, result \\ nil) do
    GenServer.call(__MODULE__, {:end_span, span_id, result})
  end

  @doc """
  Execute a function within a trace span.
  
  Alias for trace/3 for backward compatibility.
  """
  def span(name, metadata, func) when is_function(func) do
    trace(name, func, metadata)
  end

  @doc """
  Execute a function within a trace span.
  """
  def trace(name, func, metadata \\ []) when is_function(func) do
    # Fallback if GenServer not started
    unless Process.whereis(__MODULE__) do
      try do
        result = func.()
        result
      rescue
        e ->
          raise e
      end
    else
      span_id = start_span(name, nil, metadata)

      try do
        result = func.()
        end_span(span_id, %{status: :success, result: inspect(result)})
        result
      rescue
        e ->
          end_span(span_id, %{status: :error, error: Exception.message(e)})
          raise e
      end
    end
  end

  # Metrics Functions

  @doc """
  Record a metric value.
  """
  def record_metric(name, value, metadata \\ []) do
    # Fallback if GenServer not started
    unless Process.whereis(__MODULE__) do
      :ok
    else
      GenServer.cast(__MODULE__, {:record_metric, name, value, metadata})
    end
  end

  @doc """
  Increment a counter metric.
  """
  def increment_counter(name, amount \\ 1, metadata \\ []) do
    record_metric(name, amount, [type: :counter] ++ metadata)
  end

  @doc """
  Record timing for an operation.
  """
  def record_timing(name, duration_ms, metadata \\ []) do
    record_metric(name, duration_ms, [type: :timing, unit: :ms] ++ metadata)
  end

  @doc """
  Time a function and record the duration.
  """
  def time(name, func, metadata \\ []) when is_function(func) do
    start = System.monotonic_time(:millisecond)
    result = func.()
    duration = System.monotonic_time(:millisecond) - start
    record_timing(name, duration, metadata)
    result
  end

  @doc """
  Get all collected metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Export metrics in Prometheus format.
  """
  def export_metrics_prometheus do
    GenServer.call(__MODULE__, :export_prometheus)
  end

  @doc """
  Get active trace spans.
  """
  def get_active_spans do
    GenServer.call(__MODULE__, :get_active_spans)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))
    
    # Setup log file if configured
    log_file = setup_log_file(config.log_file)
    
    state = %{
      config: config,
      log_file: log_file,
      spans: %{},
      span_counter: 0,
      metrics: %{},
      traces: []
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:start_span, name, parent_id, metadata}, _from, state) do
    span_id = generate_span_id(state.span_counter)
    
    span = %{
      id: span_id,
      name: name,
      parent_id: parent_id,
      start_time: System.monotonic_time(:millisecond),
      metadata: metadata,
      status: :running,
      result: nil,
      end_time: nil,
      duration_ms: nil
    }
    
    new_state = %{state | 
      spans: Map.put(state.spans, span_id, span),
      span_counter: state.span_counter + 1
    }
    
    {:reply, span_id, new_state}
  end

  def handle_call({:end_span, span_id, result}, _from, state) do
    case Map.get(state.spans, span_id) do
      nil ->
        {:reply, {:error, :span_not_found}, state}
      
      span ->
        duration = System.monotonic_time(:millisecond) - span.start_time
        
        completed_span = %{span |
          end_time: System.monotonic_time(:millisecond),
          duration_ms: duration,
          result: result,
          status: :completed
        }
        
        # Log the span
        log_span(completed_span, state)
        
        new_state = %{state |
          spans: Map.delete(state.spans, span_id),
          traces: [completed_span | state.traces]
        }
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  def handle_call(:export_prometheus, _from, state) do
    prometheus_text = generate_prometheus_output(state.metrics)
    {:reply, prometheus_text, state}
  end

  def handle_call(:get_active_spans, _from, state) do
    {:reply, state.spans, state}
  end

  @impl true
  def handle_cast({:record_metric, name, value, metadata}, state) do
    metric_type = Keyword.get(metadata, :type, :gauge)
    
    metric_data = %{
      name: name,
      value: value,
      type: metric_type,
      timestamp: System.monotonic_time(:millisecond),
      metadata: metadata
    }
    
    # Update metric based on type
    new_metrics = case metric_type do
      :counter ->
        Map.update(state.metrics, name, value, &(&1 + value))
      
      :gauge ->
        Map.put(state.metrics, name, value)
      
      :timing ->
        # Store timing samples for histogram
        current = Map.get(state.metrics, name, [])
        Map.put(state.metrics, name, [value | current] |> Enum.take(1000))
      
      _ ->
        Map.put(state.metrics, name, value)
    end
    
    # Also log the metric
    log_metric(metric_data, state)
    
    {:noreply, %{state | metrics: new_metrics}}
  end

  # Private Functions

  defp log(level, message, metadata) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    log_entry = %{
      timestamp: timestamp,
      level: level,
      message: message,
      metadata: Enum.into(metadata, %{})
    }

    # Output as JSON
    json = Jason.encode!(log_entry)

    # Log to appropriate level
    case level do
      :debug -> Logger.debug(json)
      :info -> Logger.info(json)
      :warning -> Logger.warning(json)
      :error -> Logger.error(json)
    end
  end

  defp log_span(span, state) do
    log_entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      level: :info,
      message: "Trace span completed",
      metadata: %{
        span_id: span.id,
        span_name: span.name,
        duration_ms: span.duration_ms,
        parent_id: span.parent_id,
        result: span.result
      }
    }
    
    json = Jason.encode!(log_entry)
    Logger.info(json)
    
    # Also write to log file if configured
    if state.log_file do
      File.write!(state.log_file, json <> "\n", [:append])
    end
  end

  defp log_metric(metric, _state) do
    log_entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      level: :info,
      message: "Metric recorded",
      metadata: %{
        metric_name: metric.name,
        metric_value: metric.value,
        metric_type: metric.type
      }
    }
    
    json = Jason.encode!(log_entry)
    Logger.debug(json)
  end

  defp generate_span_id(counter) do
    "span_#{Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)}_#{counter}"
  end

  defp setup_log_file(nil), do: nil
  defp setup_log_file(path) do
    File.mkdir_p!(Path.dirname(path))
    path
  end

  defp generate_prometheus_output(metrics) do
    Enum.map(metrics, fn {name, value} ->
      case value do
        list when is_list(list) ->
          # Timing metric - generate histogram
          count = length(list)
          sum = Enum.sum(list)
          avg = if count > 0, do: sum / count, else: 0
          
          """
          # HELP #{name} Timing metric
          # TYPE #{name} histogram
          #{name}_count #{count}
          #{name}_sum #{sum}
          #{name}_avg #{avg}
          """
        
        _ ->
          # Simple gauge/counter
          """
          # HELP #{name} Metric
          # TYPE #{name} gauge
          #{name} #{value}
          """
      end
    end)
    |> Enum.join("\n")
  end
end
