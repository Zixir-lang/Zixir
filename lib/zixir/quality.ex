defmodule Zixir.Quality do
  @moduledoc """
  Automatic data quality validation and anomaly detection.
  
  Detects bad input data before it reaches your AI model, preventing
  garbage-in-garbage-out scenarios. Automatically fixes common issues
  and alerts on critical violations.
  
  ## Validation Types
  
  - Type checking (integer, float, string, boolean, enum)
  - Range validation (min/max values)
  - Null/missing value detection
  - Outlier detection (z-score, IQR method)
  - Format validation (regex patterns)
  - Categorical validation (allowed values)
  - Schema validation (nested structures)
  
  ## Auto-Fix Capabilities
  
  - Impute missing values (mean, median, mode)
  - Cap outliers (winsorization)
  - Type coercion (safe conversions)
  - Default value substitution
  
  ## Example
  
      # Define validation schema
      schema = %{
        age: [type: :integer, range: 0..120, null_rate: 0.05],
        income: [type: :float, outliers: :z_score_3, null_rate: 0.01],
        category: [type: :enum, values: ["A", "B", "C"]],
        email: [type: :string, format: ~r/@/]
      }
      
      # Validate and auto-fix
      result = Zixir.Quality.validate(data, schema,
        auto_fix: true,
        alert_on_violation: true
      )
      
      if result.quality_score < 0.8 do
        Zixir.Observability.alert("Poor data quality", score: result.quality_score)
      end
      
      # Use cleaned data
      clean_data = result.data
  """

  use GenServer

  require Logger

  @default_config %{
    auto_fix: false,
    alert_on_violation: true,
    quality_threshold: 0.8,
    outlier_method: :z_score,
    outlier_threshold: 3.0,
    imputation_method: :mean
  }

  # Client API

  @doc """
  Start the Quality validation service.
  """
  def start_link(opts \\ []) do
    case GenServer.start_link(__MODULE__, opts, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Validate data against a schema.
  
  ## Options
    * `:auto_fix` - Automatically fix issues (default: false)
    * `:alert_on_violation` - Send alerts for violations (default: true)
    * `:quality_threshold` - Minimum quality score (0.0-1.0)
  
  ## Returns
    * `%{data: map, valid: boolean, quality_score: float, violations: list, fixes_applied: list}`
  """
  def validate(data, schema, opts \\ []) do
    # Pass config to validation module
    config = @default_config
    opts = Keyword.put(opts, :config, config)
    Zixir.Quality.Validation.validate(data, schema, opts)
  end

  @doc """
  Quick validation for common data issues.
  """
  def quick_check(data, opts \\ []) do
    # Auto-detect schema from data
    schema = Zixir.Quality.Schema.infer_schema(data)
    validate(data, schema, opts)
  end

  @doc """
  Detect anomalies in a dataset.
  
  Delegates to Zixir.Quality.Anomaly.detect_anomalies/2
  """
  def detect_anomalies(data, opts \\ []) do
    # Merge default config values
    opts = Keyword.merge(
      [method: @default_config.outlier_method, threshold: @default_config.outlier_threshold],
      opts
    )
    Zixir.Quality.Anomaly.detect_anomalies(data, opts)
  end

  @doc """
  Profile data to understand its characteristics.
  
  Delegates to Zixir.Quality.Profiler.profile/1
  """
  defdelegate profile(data), to: Zixir.Quality.Profiler

  @doc """
  Create a validation schema from sample data.
  
  Delegates to Zixir.Quality.Schema.create_schema/2
  """
  defdelegate create_schema(sample_data, opts \\ []), to: Zixir.Quality.Schema

  @doc """
  Get a stored schema.
  
  Delegates to Zixir.Quality.Schema.get_schema/1
  """
  defdelegate get_schema(name), to: Zixir.Quality.Schema

  @doc """
  Monitor a data stream for quality issues.
  """
  def monitor_stream(stream_pid, schema, opts \\ []) do
    GenServer.cast(__MODULE__, {:monitor_stream, stream_pid, schema, opts})
  end

  @doc """
  Get quality statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      config: Map.merge(@default_config, Map.new(opts)),
      monitors: %{},
      validation_count: 0,
      violation_count: 0,
      schemas: %{}
    }
    
    {:ok, state}
  end

  @impl true
  def handle_cast({:monitor_stream, stream_pid, schema, opts}, state) do
    monitor = %{
      stream_pid: stream_pid,
      schema: schema,
      opts: opts,
      samples: [],
      violations: [],
      started_at: DateTime.utc_now()
    }
    
    new_monitors = Map.put(state.monitors, stream_pid, monitor)
    
    # Start monitoring process
    spawn(fn -> monitor_stream_loop(stream_pid, schema, opts) end)
    
    {:noreply, %{state | monitors: new_monitors}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      active_monitors: map_size(state.monitors),
      total_validations: state.validation_count,
      total_violations: state.violation_count,
      violation_rate: if(state.validation_count > 0, 
        do: state.violation_count / state.validation_count, 
        else: 0),
      config: state.config
    }
    
    {:reply, stats, state}
  end

  # Private Functions

  defp monitor_stream_loop(stream_pid, schema, opts) do
    # In real implementation, would subscribe to stream
    # For now, placeholder
    Process.sleep(60_000)
    monitor_stream_loop(stream_pid, schema, opts)
  end
end
