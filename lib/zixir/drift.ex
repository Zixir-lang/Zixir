defmodule Zixir.Drift do
  @moduledoc """
  Automatic model drift detection for autonomous AI systems.
  
  Detects when model performance degrades over time due to:
  - Concept drift (relationship between inputs/outputs changes)
  - Data drift (input distribution changes)
  - Prediction drift (output distribution changes)
  
  ## Statistical Methods
  
  - Kolmogorov-Smirnov test (distribution comparison)
  - Population Stability Index (PSI)
  - Wasserstein distance
  - KL divergence
  - Chi-square test (for categorical)
  
  ## Example
  
      # Monitor for drift in real-time
      workflow ml_pipeline:
        let prediction = model.predict(input)
        
        # Check for drift
        let drift_result = Zixir.Drift.detect(
          current: prediction,
          baseline: Zixir.Cache.get("model_baseline"),
          method: :ks_test,
          threshold: 0.05
        )
        
        if drift_result.drift_detected:
          Zixir.Observability.alert("Model drift detected!", 
            score: drift_result.score,
            severity: drift_result.severity
          )
          # Trigger automatic retraining
          Zixir.Workflow.trigger("retrain_workflow")
        end
      end
  """

  use GenServer

  require Logger

  @default_config %{
    window_size: 1000,        # Number of predictions to compare
    check_interval: 3600,     # Check every hour (seconds)
    methods: [:ks_test, :psi], # Default detection methods
    auto_alert: true,
    auto_check: false,        # Disable auto checking by default
    severity_thresholds: %{
      low: 0.05,
      medium: 0.10,
      high: 0.20
    }
  }

  # Client API

  @doc """
  Start the Drift detection service.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case GenServer.start_link(__MODULE__, opts, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Detect drift between current predictions and baseline.
  
  ## Options
    * `:method` - Detection method (:ks_test, :psi, :wasserstein, :kl_divergence, :chi_square)
    * `:threshold` - P-value threshold for significance (default: 0.05)
    * `:window_size` - Number of samples to compare (default: 1000)
  
  ## Returns
    * `%{drift_detected: boolean, score: float, severity: atom, method: atom}`
  """
  @spec detect(list(), list(), keyword()) :: map()
  def detect(current, baseline, opts \\ []) do
    method = Keyword.get(opts, :method, :ks_test)
    threshold = Keyword.get(opts, :threshold, 0.05)
    
    # Calculate drift score
    score = calculate_drift(current, baseline, method)
    
    # Determine severity
    severity = get_severity(score)
    
    # Check if drift detected
    drift_detected = score > threshold
    
    result = %{
      drift_detected: drift_detected,
      score: score,
      severity: severity,
      method: method,
      threshold: threshold,
      timestamp: DateTime.utc_now()
    }
    
    # Log if drift detected
    if drift_detected do
      Logger.warning("Drift detected: score=#{Float.round(score, 4)}, severity=#{severity}, method=#{method}")
      
      if @default_config.auto_alert do
        Zixir.Observability.alert("Model drift detected",
          score: score,
          severity: severity,
          method: method,
          threshold: threshold
        )
      end
    end
    
    result
  end

  @doc """
  Create a baseline from historical predictions.
  """
  @spec create_baseline(list(), keyword()) :: {:ok, map()}
  def create_baseline(predictions, opts \\ []) do
    name = Keyword.get(opts, :name, "default_baseline")
    
    baseline = %{
      name: name,
      data: predictions,
      stats: calculate_stats(predictions),
      created_at: DateTime.utc_now(),
      sample_size: length(predictions)
    }
    
    # Store in cache
    Zixir.Cache.put("drift_baseline_#{name}", baseline, persistent: true)
    
    {:ok, baseline}
  end

  @doc """
  Get a stored baseline.
  """
  @spec get_baseline(String.t()) :: {:ok, map()} | {:error, :baseline_not_found}
  def get_baseline(name \\ "default_baseline") do
    case Zixir.Cache.get("drift_baseline_#{name}") do
      {:ok, baseline} -> {:ok, baseline}
      {:error, _} -> {:error, :baseline_not_found}
    end
  end

  @doc """
  Monitor a stream of predictions for drift.
  Automatically checks at regular intervals.
  """
  @spec monitor_stream(pid(), String.t(), keyword()) :: :ok
  def monitor_stream(stream_pid, baseline_name, opts \\ []) do
    GenServer.cast(__MODULE__, {:monitor_stream, stream_pid, baseline_name, opts})
  end

  @doc """
  Run drift detection on a sliding window of predictions.
  """
  @spec sliding_window_detect(list(), String.t(), keyword()) :: map() | {:error, :baseline_not_found}
  def sliding_window_detect(predictions, baseline_name, opts \\ []) do
    window_size = Keyword.get(opts, :window_size, @default_config.window_size)
    
    # Take last N predictions
    window = Enum.take(predictions, -window_size)
    
    case get_baseline(baseline_name) do
      {:ok, baseline} ->
        detect(window, baseline.data, opts)
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compare multiple features for drift (multivariate).
  """
  @spec detect_multivariate(list(list()), list(list()), keyword()) :: map()
  def detect_multivariate(current_features, baseline_features, opts \\ []) do
    # Detect drift for each feature
    results = Enum.zip(current_features, baseline_features)
    |> Enum.map(fn {current, baseline} ->
      detect(current, baseline, opts)
    end)
    
    # Aggregate results
    drift_count = Enum.count(results, & &1.drift_detected)
    avg_score = Enum.map(results, & &1.score) |> Zixir.Utils.average()
    max_severity = results |> Enum.map(& &1.severity) |> max_severity()
    
    %{
      drift_detected: drift_count > 0,
      drift_count: drift_count,
      total_features: length(results),
      avg_score: avg_score,
      max_severity: max_severity,
      feature_results: results,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Get drift detection statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))
    
    state = %{
      config: config,
      monitors: %{},
      detection_count: 0,
      last_check: nil
    }
    
    # Start periodic checking if auto_check enabled
    if config.auto_check do
      schedule_check(config.check_interval)
    end
    
    {:ok, state}
  end

  @impl true
  def handle_cast({:monitor_stream, stream_pid, baseline_name, opts}, state) do
    # Add to monitors
    monitor = %{
      stream_pid: stream_pid,
      baseline_name: baseline_name,
      opts: opts,
      predictions: [],
      started_at: DateTime.utc_now()
    }
    
    new_monitors = Map.put(state.monitors, stream_pid, monitor)
    
    {:noreply, %{state | monitors: new_monitors}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      active_monitors: map_size(state.monitors),
      total_detections: state.detection_count,
      last_check: state.last_check,
      config: state.config
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:check_drift, state) do
    # Check all monitored streams
    new_monitors = Enum.reduce(state.monitors, %{}, fn {pid, monitor}, acc ->
      # Get recent predictions from stream
      recent = get_recent_predictions(pid, monitor.predictions)
      
      case get_baseline(monitor.baseline_name) do
        {:ok, baseline} ->
          result = detect(recent, baseline.data, monitor.opts)
          
          if result.drift_detected do
            Logger.warning("Drift detected in monitored stream #{inspect(pid)}")
          end
          
          # Update monitor with new predictions
          updated_monitor = %{monitor | predictions: recent}
          Map.put(acc, pid, updated_monitor)
        
        {:error, _} ->
          acc
      end
    end)
    
    # Schedule next check
    schedule_check(state.config.check_interval)
    
    {:noreply, %{state | 
      monitors: new_monitors,
      last_check: DateTime.utc_now(),
      detection_count: state.detection_count + 1
    }}
  end

  # Private Functions

  defp calculate_drift(current, baseline, :ks_test) do
    # Kolmogorov-Smirnov test
    # Returns D statistic (0-1, higher = more different)
    ks_statistic(current, baseline)
  end

  defp calculate_drift(current, baseline, :psi) do
    # Population Stability Index
    psi_score(current, baseline)
  end

  defp calculate_drift(current, baseline, :wasserstein) do
    # Wasserstein distance (Earth Mover's Distance)
    wasserstein_distance(current, baseline)
  end

  defp calculate_drift(current, baseline, :kl_divergence) do
    # KL divergence
    kl_divergence(current, baseline)
  end

  defp calculate_drift(current, baseline, :chi_square) do
    # Chi-square test for categorical data
    chi_square_statistic(current, baseline)
  end

  defp calculate_drift(_, _, method) do
    Logger.error("Unknown drift detection method: #{method}")
    0.0
  end

  # Kolmogorov-Smirnov test implementation
  defp ks_statistic(sample1, sample2) do
    # Sort both samples
    sorted1 = Enum.sort(sample1)
    sorted2 = Enum.sort(sample2)
    
    # Get all unique values
    all_values = Enum.uniq(sorted1 ++ sorted2)
    
    # Calculate empirical CDFs and find max difference
    n1 = length(sorted1)
    n2 = length(sorted2)
    
    max_diff = Enum.reduce(all_values, 0.0, fn value, max_d ->
      cdf1 = empirical_cdf(sorted1, value, n1)
      cdf2 = empirical_cdf(sorted2, value, n2)
      diff = abs(cdf1 - cdf2)
      max(max_d, diff)
    end)
    
    max_diff
  end

  defp empirical_cdf(sorted_list, value, n) do
    count = Enum.count(sorted_list, &(&1 <= value))
    count / n
  end

  # Population Stability Index
  defp psi_score(current, baseline) do
    # Bin both distributions
    {bins_current, bins_baseline} = bin_distributions(current, baseline, 10)
    
    # Calculate PSI
    Enum.zip(bins_current, bins_baseline)
    |> Enum.reduce(0.0, fn {p_current, p_baseline}, sum ->
      # Avoid division by zero
      p_baseline = if p_baseline == 0, do: 0.0001, else: p_baseline
      p_current = if p_current == 0, do: 0.0001, else: p_current
      
      sum + (p_current - p_baseline) * :math.log(p_current / p_baseline)
    end)
  end

  defp bin_distributions(list1, list2, num_bins) do
    # Create bins based on combined range
    all_values = list1 ++ list2
    min_val = Enum.min(all_values)
    max_val = Enum.max(all_values)
    bin_width = (max_val - min_val) / num_bins
    
    # Count in each bin
    bins1 = count_in_bins(list1, min_val, bin_width, num_bins)
    bins2 = count_in_bins(list2, min_val, bin_width, num_bins)
    
    # Convert to probabilities
    total1 = length(list1)
    total2 = length(list2)
    
    probs1 = Enum.map(bins1, &(&1 / total1))
    probs2 = Enum.map(bins2, &(&1 / total2))
    
    {probs1, probs2}
  end

  defp count_in_bins(list, min_val, bin_width, num_bins) do
    for i <- 0..(num_bins-1) do
      bin_min = min_val + i * bin_width
      bin_max = min_val + (i + 1) * bin_width
      
      Enum.count(list, fn x -> 
        x >= bin_min && x < bin_max
      end)
    end
  end

  # Wasserstein distance (simplified)
  defp wasserstein_distance(sample1, sample2) do
    sorted1 = Enum.sort(sample1)
    sorted2 = Enum.sort(sample2)
    
    # Pad shorter list
    n1 = length(sorted1)
    n2 = length(sorted2)
    max_n = max(n1, n2)
    
    padded1 = pad_list(sorted1, max_n)
    padded2 = pad_list(sorted2, max_n)
    
    # Calculate average absolute difference
    Enum.zip(padded1, padded2)
    |> Enum.map(fn {a, b} -> abs(a - b) end)
    |> Zixir.Utils.average()
  end

  defp pad_list(list, target_length) do
    current_length = length(list)
    if current_length < target_length do
      # Repeat last element
      last = List.last(list) || 0
      list ++ List.duplicate(last, target_length - current_length)
    else
      list
    end
  end

  # KL divergence (simplified)
  defp kl_divergence(current, baseline) do
    {bins_current, bins_baseline} = bin_distributions(current, baseline, 10)
    
    Enum.zip(bins_current, bins_baseline)
    |> Enum.reduce(0.0, fn {p, q}, sum ->
      if p > 0 && q > 0 do
        sum + p * :math.log(p / q)
      else
        sum
      end
    end)
  end

  # Chi-square test for categorical
  defp chi_square_statistic(current, baseline) do
    # Count frequencies
    freq_current = Zixir.Utils.frequencies(current)
    freq_baseline = Zixir.Utils.frequencies(baseline)
    
    # Get all categories
    categories = Map.keys(freq_current) ++ Map.keys(freq_baseline) |> Enum.uniq()
    
    # Calculate chi-square statistic
    total_current = length(current)
    total_baseline = length(baseline)
    
    Enum.reduce(categories, 0.0, fn cat, sum ->
      observed = Map.get(freq_current, cat, 0)
      expected = Map.get(freq_baseline, cat, 0) * (total_current / total_baseline)
      
      if expected > 0 do
        sum + :math.pow(observed - expected, 2) / expected
      else
        sum
      end
    end)
  end

  defp calculate_stats(predictions) do
    n = length(predictions)
    
    if n == 0 do
      %{mean: 0, std: 0, min: 0, max: 0}
    else
      mean = Enum.sum(predictions) / n
      squared_diffs = Enum.map(predictions, &(:math.pow(&1 - mean, 2)))
      variance = Enum.sum(squared_diffs) / n
      std = :math.sqrt(variance)
      
      %{
        mean: mean,
        std: std,
        min: Enum.min(predictions),
        max: Enum.max(predictions),
        count: n
      }
    end
  end

  defp get_severity(score) do
    thresholds = @default_config.severity_thresholds
    
    cond do
      score >= thresholds.high -> :high
      score >= thresholds.medium -> :medium
      score >= thresholds.low -> :low
      true -> :none
    end
  end

  defp max_severity(severities) do
    cond do
      :high in severities -> :high
      :medium in severities -> :medium
      :low in severities -> :low
      true -> :none
    end
  end

  defp get_recent_predictions(_pid, existing) do
    # In real implementation, would fetch from stream
    # For now, return last 100
    Enum.take(existing, -100)
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check_drift, interval * 1000)
  end
end
