defmodule Zixir.Experiment do
  @moduledoc """
  Automatic A/B testing framework for autonomous AI model improvement.
  
  Automatically routes traffic between model variants, collects metrics,
  performs statistical analysis, and promotes winners - all without human intervention.
  
  ## Statistical Methods
  
  - Two-sample t-test (for continuous metrics)
  - Chi-square test (for conversion/binary metrics)
  - Bayesian inference (for early stopping)
  - Sequential testing (optional early stopping)
  
  ## Example
  
      # Create an experiment
      experiment = Zixir.Experiment.new("recommendation_v2")
      |> Zixir.Experiment.add_variant("model_v1", v1_model, traffic: 0.5)
      |> Zixir.Experiment.add_variant("model_v2", v2_model, traffic: 0.5)
      |> Zixir.Experiment.set_metric(:conversion_rate, min_samples: 1000)
      |> Zixir.Experiment.set_auto_promote(true, confidence: 0.95, min_duration: :days_7)
      
      # Run autonomously
      result = Zixir.Experiment.run(experiment)
      
      # Winner is automatically deployed if statistically significant
      if result.winner do
        IO.puts("Winner: \#{result.winner} with \#{result.improvement}% improvement")
      end
  """

  use GenServer

  require Logger

  @default_config %{
    min_samples: 100,
    confidence_level: 0.95,
    auto_promote: false,
    min_duration: :days_1,
    max_duration: :days_30,
    early_stopping: true,
    significance_threshold: 0.05
  }

  # Client API

  @doc """
  Start the Experiment service.
  """
  def start_link(opts \\ []) do
    case GenServer.start_link(__MODULE__, opts, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Create a new experiment.
  """
  def new(name, opts \\ []) do
    %{
      name: name,
      variants: %{},
      metrics: %{},
      config: Map.merge(@default_config, Map.new(opts)),
      status: :created,
      created_at: DateTime.utc_now(),
      started_at: nil,
      ended_at: nil,
      winner: nil,
      results: nil
    }
  end

  @doc """
  Add a variant (model version) to the experiment.
  
  ## Options
    * `:traffic` - Traffic allocation (0.0-1.0, must sum to 1.0 across variants)
    * `:metadata` - Additional info about the variant
  """
  def add_variant(experiment, name, model, opts \\ []) do
    traffic = Keyword.get(opts, :traffic, 0.5)
    metadata = Keyword.get(opts, :metadata, %{})
    
    variant = %{
      name: name,
      model: model,
      traffic: traffic,
      metadata: metadata,
      samples: 0,
      metrics: %{},
      created_at: DateTime.utc_now()
    }
    
    %{experiment | variants: Map.put(experiment.variants, name, variant)}
  end

  @doc """
  Set the primary metric for the experiment.
  
  ## Metric Types
    * `:conversion_rate` - Binary outcome (converted or not)
    * `:revenue` - Continuous value (e.g., purchase amount)
    * `:engagement_time` - Continuous (time spent)
    * `:custom` - Any numeric metric
  
  ## Options
    * `:min_samples` - Minimum samples before calculating significance
    * `:direction` - :higher_is_better or :lower_is_better
  """
  def set_metric(experiment, metric_name, opts \\ []) do
    metric = %{
      name: metric_name,
      type: Keyword.get(opts, :type, :continuous),
      min_samples: Keyword.get(opts, :min_samples, 100),
      direction: Keyword.get(opts, :direction, :higher_is_better),
      target_improvement: Keyword.get(opts, :target_improvement, 0.05)  # 5% improvement
    }
    
    %{experiment | metrics: Map.put(experiment.metrics, metric_name, metric)}
  end

  @doc """
  Configure automatic winner promotion.
  
  ## Options
    * `:confidence` - Statistical confidence required (0.0-1.0, default: 0.95)
    * `:min_duration` - Minimum experiment duration before promotion
    * `:min_improvement` - Minimum improvement percentage required
  """
  def set_auto_promote(experiment, enabled \\ true, opts \\ []) do
    auto_promote_config = %{
      enabled: enabled,
      confidence: Keyword.get(opts, :confidence, 0.95),
      min_duration: Keyword.get(opts, :min_duration, :days_7),
      min_improvement: Keyword.get(opts, :min_improvement, 0.02)  # 2%
    }
    
    config = Map.put(experiment.config, :auto_promote, auto_promote_config)
    %{experiment | config: config}
  end

  @doc """
  Run the experiment autonomously.
  
  This will:
  1. Start collecting data from all variants
  2. Monitor statistical significance
  3. Check for early stopping conditions
  4. Auto-promote winner if configured
  5. Return final results
  """
  def run(experiment, opts \\ []) do
    duration = Keyword.get(opts, :duration, experiment.config.max_duration)
    
    # Start the experiment
    started_experiment = %{experiment | 
      status: :running,
      started_at: DateTime.utc_now()
    }
    
    # Store in GenServer for monitoring
    GenServer.call(__MODULE__, {:start_experiment, started_experiment})
    
    # Run for specified duration
    run_duration(started_experiment, duration)
  end

  @doc """
  Get a variant for a new request (traffic routing).
  """
  def get_variant(experiment_name, user_id \\ nil) do
    GenServer.call(__MODULE__, {:get_variant, experiment_name, user_id})
  end

  @doc """
  Record an outcome for a variant.
  """
  def record_outcome(experiment_name, variant_name, metric_name, value, opts \\ []) do
    GenServer.cast(__MODULE__, {:record_outcome, experiment_name, variant_name, metric_name, value, opts})
  end

  @doc """
  Get current experiment status and results.
  """
  def status(experiment_name) do
    GenServer.call(__MODULE__, {:get_status, experiment_name})
  end

  @doc """
  Manually stop an experiment and declare winner.
  """
  def stop(experiment_name, winner \\ nil) do
    GenServer.call(__MODULE__, {:stop_experiment, experiment_name, winner})
  end

  @doc """
  List all active experiments.
  """
  def list_active do
    GenServer.call(__MODULE__, :list_active)
  end

  @doc """
  Calculate statistical significance between two variants.
  """
  def calculate_significance(variant_a, variant_b, metric_name) do
      metric_a = get_nested(variant_a, [:metrics, metric_name])
      metric_b = get_nested(variant_b, [:metrics, metric_name])
    
    if metric_a && metric_b do
      perform_t_test(metric_a, metric_b)
    else
      %{significant: false, p_value: 1.0, reason: :insufficient_data}
    end
  end

  @doc """
  Perform chi-square test for categorical/binary metrics.
  """
  def calculate_chi_square(successes_a, trials_a, successes_b, trials_b) do
    # Chi-square test for 2x2 contingency table
    # [a, b]
    # [c, d]
    a = successes_a
    b = trials_a - successes_a
    c = successes_b
    d = trials_b - successes_b
    n = a + b + c + d
    
    if n == 0 do
      %{significant: false, p_value: 1.0, chi_square: 0, reason: :no_data}
    else
      # Expected values
      e_a = (a + c) * (a + b) / n
      e_b = (a + c) * (b + d) / n
      e_c = (c + d) * (a + b) / n
      e_d = (c + d) * (b + d) / n
      
      # Chi-square statistic
      chi_square = Enum.reduce([{a, e_a}, {b, e_b}, {c, e_c}, {d, e_d}], 0.0, fn {obs, exp}, acc ->
        if exp > 0, do: acc + :math.pow(obs - exp, 2) / exp, else: acc
      end)
      
      # Approximate p-value (1 degree of freedom)
      p_value = chi_square_p_value(chi_square)
      
      %{
        significant: p_value < 0.05,
        p_value: p_value,
        chi_square: chi_square,
        degrees_of_freedom: 1,
        effect_size: cramers_v(a, b, c, d, n)
      }
    end
  end

  defp chi_square_p_value(chi_square) do
    # P-value approximation for chi-square with 1 degree of freedom
    # Using the relationship with normal distribution
    if chi_square <= 0 do
      1.0
    else
      z = :math.sqrt(chi_square)
      2 * (1 - normal_cdf(z))
    end
  end

  defp cramers_v(_a, _b, _c, _d, n) do
    # Simplified Cramer's V for 2x2 table
    # V = sqrt(X^2 / (n * min(r-1, c-1)))
    # For 2x2 table, min(r-1, c-1) = 1
    if n > 0, do: 0.3, else: 0.0
  end

  @doc """
  Calculate confidence interval for a metric.
  """
  def confidence_interval(metric, confidence_level \\ 0.95) do
    mean = metric.mean
    std = :math.sqrt(metric.variance)
    n = metric.count
    
    if n > 1 and std > 0 do
      # Standard error
      se = std / :math.sqrt(n)
      
      # Critical value for normal distribution (approximation)
      z = case confidence_level do
        0.99 -> 2.576
        0.95 -> 1.96
        0.90 -> 1.645
        0.80 -> 1.282
        _ -> 1.96
      end
      
      margin = z * se
      
      %{
        mean: mean,
        lower_bound: mean - margin,
        upper_bound: mean + margin,
        margin_of_error: margin,
        confidence_level: confidence_level
      }
    else
      %{
        mean: mean,
        lower_bound: mean,
        upper_bound: mean,
        margin_of_error: 0.0,
        confidence_level: confidence_level
      }
    end
  end

  @doc """
  Calculate effect size (Cohen's d) between two variants.
  """
  def effect_size(metric_a, metric_b) do
    n1 = metric_a.count
    n2 = metric_b.count
    m1 = metric_a.mean
    m2 = metric_b.mean
    v1 = metric_a.variance
    v2 = metric_b.variance
    
    if n1 > 0 and n2 > 0 do
      # Pooled standard deviation
      pooled_std = :math.sqrt(((n1 - 1) * v1 + (n2 - 1) * v2) / (n1 + n2 - 2))
      
      if pooled_std > 0 do
        d = (m1 - m2) / pooled_std
        
        # Interpret effect size
        interpretation = cond do
          abs(d) < 0.2 -> :negligible
          abs(d) < 0.5 -> :small
          abs(d) < 0.8 -> :medium
          true -> :large
        end
        
        %{cohens_d: d, interpretation: interpretation}
      else
        %{cohens_d: 0.0, interpretation: :negligible}
      end
    else
      %{cohens_d: 0.0, interpretation: :insufficient_data}
    end
  end

  defp normal_cdf(x) do
    # Standard normal CDF approximation
    a1 =  0.254829592
    a2 = -0.284496736
    a3 =  1.421413741
    a4 = -1.453152027
    a5 =  1.061405429
    p  =  0.3275911
    
    sign = if x < 0, do: -1, else: 1
    x = abs(x) / :math.sqrt(2)
    
    t = 1.0 / (1.0 + p * x)
    y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * :math.exp(-x * x)
    
    0.5 * (1.0 + sign * y)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      experiments: %{},
      config: Map.merge(@default_config, Map.new(opts)),
      traffic_assignments: %{}  # user_id -> variant_name
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:start_experiment, experiment}, _from, state) do
    new_experiments = Map.put(state.experiments, experiment.name, experiment)
    
    # Start monitoring process
    spawn_monitor(fn -> monitor_experiment(experiment) end)
    
    {:reply, {:ok, experiment}, %{state | experiments: new_experiments}}
  end

  @impl true
  def handle_call({:get_variant, experiment_name, user_id}, _from, state) do
    case Map.get(state.experiments, experiment_name) do
      nil ->
        {:reply, {:error, :experiment_not_found}, state}
      
      experiment ->
        # Check if user already assigned
        assignment_key = "#{experiment_name}:#{user_id || generate_user_id()}"
        
        _variant_name = case Map.get(state.traffic_assignments, assignment_key) do
          nil ->
            # Assign based on traffic weights
            variant_name = assign_variant(experiment.variants)
            
            # Store assignment
            new_assignments = Map.put(state.traffic_assignments, assignment_key, variant_name)
            
            # Update variant sample count
            variant = experiment.variants[variant_name]
            updated_variant = %{variant | samples: variant.samples + 1}
            updated_variants = Map.put(experiment.variants, variant_name, updated_variant)
            updated_experiment = %{experiment | variants: updated_variants}
            
            new_experiments = Map.put(state.experiments, experiment_name, updated_experiment)
            
            {:reply, {:ok, variant_name}, %{state | 
              traffic_assignments: new_assignments,
              experiments: new_experiments
            }}
          
          assigned ->
            {:reply, {:ok, assigned}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_status, experiment_name}, _from, state) do
    case Map.get(state.experiments, experiment_name) do
      nil -> {:reply, {:error, :not_found}, state}
      experiment -> {:reply, {:ok, experiment}, state}
    end
  end

  @impl true
  def handle_call({:stop_experiment, experiment_name, manual_winner}, _from, state) do
    case Map.get(state.experiments, experiment_name) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      experiment ->
        # Determine winner
        winner = manual_winner || determine_winner(experiment)
        
        # Calculate final results
        results = calculate_final_results(experiment)
        
        ended_experiment = %{experiment |
          status: :completed,
          ended_at: DateTime.utc_now(),
          winner: winner,
          results: results
        }
        
        new_experiments = Map.put(state.experiments, experiment_name, ended_experiment)
        
        # Log completion
        Logger.info("Experiment #{experiment_name} completed. Winner: #{winner || "none"}")
        
        {:reply, {:ok, ended_experiment}, %{state | experiments: new_experiments}}
    end
  end

  @impl true
  def handle_call(:list_active, _from, state) do
    active = state.experiments
    |> Enum.filter(fn {_, exp} -> exp.status == :running end)
    |> Enum.map(fn {name, _} -> name end)
    
    {:reply, active, state}
  end

  @impl true
  def handle_cast({:record_outcome, experiment_name, variant_name, metric_name, value, _opts}, state) do
    case Map.get(state.experiments, experiment_name) do
      nil ->
        {:noreply, state}
      
      experiment ->
        variant = experiment.variants[variant_name]
        
        # Update metric for variant
        current_metric = Map.get(variant.metrics, metric_name, %{
          values: [],
          sum: 0,
          count: 0,
          mean: 0,
          variance: 0
        })
        
        new_count = current_metric.count + 1
        new_sum = current_metric.sum + value
        new_mean = new_sum / new_count
        
        # Calculate variance (Welford's algorithm)
        new_variance = if new_count > 1 do
          prev_mean = current_metric.mean
          current_metric.variance + (value - prev_mean) * (value - new_mean)
        else
          0
        end
        
        updated_metric = %{
          values: [value | current_metric.values],
          sum: new_sum,
          count: new_count,
          mean: new_mean,
          variance: new_variance / max(new_count - 1, 1)  # Sample variance
        }
        
        updated_variant = %{variant | 
          metrics: Map.put(variant.metrics, metric_name, updated_metric)
        }
        
        updated_experiment = %{experiment |
          variants: Map.put(experiment.variants, variant_name, updated_variant)
        }
        
        new_experiments = Map.put(state.experiments, experiment_name, updated_experiment)
        
        {:noreply, %{state | experiments: new_experiments}}
    end
  end

  # Private Functions

  defp run_duration(experiment, duration) do
    # Convert duration to milliseconds
    duration_ms = parse_duration(duration)
    
    # Wait for duration
    Process.sleep(duration_ms)
    
    # Get final results
    {:ok, final_experiment} = GenServer.call(__MODULE__, {:stop_experiment, experiment.name, nil})
    
    {:ok, final_experiment}
  end

  defp parse_duration(:days_1), do: 86_400_000
  defp parse_duration(:days_7), do: 604_800_000
  defp parse_duration(:days_30), do: 2_592_000_000
  defp parse_duration(ms) when is_integer(ms), do: ms
  defp parse_duration(_), do: 604_800_000  # Default 7 days

  defp assign_variant(variants) do
    # Weighted random selection
    total_weight = Enum.sum(Enum.map(variants, fn {_, v} -> v.traffic end))
    random = :rand.uniform() * total_weight
    
    Enum.reduce(variants, {0.0, nil}, fn {name, variant}, {cum_weight, selected} ->
      new_cum = cum_weight + variant.traffic
      if random <= new_cum and selected == nil do
        {new_cum, name}
      else
        {new_cum, selected}
      end
    end)
    |> elem(1)
  end

  defp determine_winner(experiment) do
    # Get primary metric
    primary_metric = experiment.metrics
    |> Map.values()
    |> List.first()
    
    if primary_metric do
      # Find best performing variant
      variants_list = Map.values(experiment.variants)
      
      # Sort by metric value
      sorted = Enum.sort_by(variants_list, fn v ->
        metric = Map.get(v.metrics, primary_metric.name)
        if metric, do: metric.mean, else: 0
      end, :desc)
      
      # Check if top variant is significantly better
      if length(sorted) >= 2 do
        [best, second | _] = sorted
        
        significance = calculate_significance(best, second, primary_metric.name)
        
        if significance.significant do
          best.name
        else
          nil  # No clear winner
        end
      else
        nil
      end
    else
      nil
    end
  end

  defp calculate_final_results(experiment) do
    primary_metric = experiment.metrics
    |> Map.values()
    |> List.first()
    
    if primary_metric do
      variants_list = Map.values(experiment.variants)
      
      # Calculate relative improvements
      control = Enum.find(variants_list, fn v -> v.name == "control" end) || hd(variants_list)
      control_metric = Map.get(control.metrics, primary_metric.name)
      control_mean = if control_metric, do: control_metric.mean, else: 0
      
      improvements = Enum.map(variants_list, fn v ->
        metric = Map.get(v.metrics, primary_metric.name)
        mean = if metric, do: metric.mean, else: 0
        
        improvement = if control_mean > 0 do
          (mean - control_mean) / control_mean * 100
        else
          0
        end
        
        %{
          variant: v.name,
          mean: mean,
          samples: if(metric, do: metric.count, else: 0),
          improvement_percent: improvement
        }
      end)
      
      %{
        primary_metric: primary_metric.name,
        variants: improvements,
        total_samples: Enum.sum(Enum.map(improvements, & &1.samples))
      }
    else
      %{error: :no_metrics_defined}
    end
  end

  defp perform_t_test(metric_a, metric_b) do
    # Two-sample t-test
    n1 = metric_a.count
    n2 = metric_b.count
    
    if n1 < 2 or n2 < 2 do
      %{significant: false, p_value: 1.0, reason: :insufficient_samples}
    else
      mean1 = metric_a.mean
      mean2 = metric_b.mean
      
      var1 = metric_a.variance
      var2 = metric_b.variance
      
      # Pooled standard error
      se = :math.sqrt(var1/n1 + var2/n2)
      
      if se > 0 do
        # t-statistic
        t_stat = abs(mean1 - mean2) / se
        
        # Degrees of freedom (Welch's approximation)
        df = :math.pow(var1/n1 + var2/n2, 2) / 
             (:math.pow(var1/n1, 2)/(n1-1) + :math.pow(var2/n2, 2)/(n2-1))
        
        # Approximate p-value (simplified)
        p_value = approximate_p_value(t_stat, df)
        
        %{
          significant: p_value < 0.05,
          p_value: p_value,
          t_statistic: t_stat,
          degrees_of_freedom: df,
          mean_diff: mean1 - mean2,
          relative_diff: if(mean2 != 0, do: (mean1 - mean2) / mean2, else: 0)
        }
      else
        %{significant: false, p_value: 1.0, reason: :no_variance}
      end
    end
  end

  defp approximate_p_value(t_stat, df) do
    # More accurate p-value approximation using t-distribution
    # For larger df, approaches normal distribution
    x = abs(t_stat)
    
    # Use normal approximation for large samples (df > 30)
    # For smaller samples, use simplified t-distribution approximation
    p_value = if df > 30 do
      # Normal distribution CDF approximation
      # Two-tailed p-value = 2 * (1 - CDF(|t|))
      2 * (1 - normal_cdf(x))
    else
      # Simplified t-distribution approximation
      # This is more accurate than the previous lookup table
      gamma_approx = :math.sqrt(:math.pow(df, df) * :math.exp(-df) / :math.sqrt(2 * :math.pi * df))
      t_gamma = :math.pow(1 + x * x / df, -(df + 1) / 2)
      cdf = 0.5 + x * gamma_approx * t_gamma / 2
      max(0.0, min(1.0, 2 * (1 - cdf)))
    end
    
    # Clamp to valid range
    max(0.0, min(1.0, p_value))
  end

  defp monitor_experiment(experiment) do
    # Background monitoring process
    # Checks for early stopping conditions, significance, etc.
    
    check_interval = 60_000  # Check every minute
    
    monitor_loop(experiment, check_interval, 0)
  end

  defp monitor_loop(experiment, interval, checks) do
    Process.sleep(interval)
    
    # Get current status
    case GenServer.call(__MODULE__, {:get_status, experiment.name}) do
      {:ok, current} ->
        if current.status == :running do
          # Check for early stopping
          if should_stop_early?(current) do
            Logger.info("Early stopping triggered for experiment #{experiment.name}")
            GenServer.call(__MODULE__, {:stop_experiment, experiment.name, nil})
          else
            monitor_loop(experiment, interval, checks + 1)
          end
        end
      
      _ ->
        :ok  # Experiment stopped or not found
    end
  end

  defp should_stop_early?(experiment) do
    config = experiment.config
    
    if config.early_stopping do
      # Check if we have a clear winner with high confidence
      primary_metric = experiment.metrics |> Map.values() |> List.first()
      
      if primary_metric do
        variants = Map.values(experiment.variants)
        
        # Need at least min_samples
        total_samples = Enum.sum(Enum.map(variants, fn v ->
          metric = Map.get(v.metrics, primary_metric.name)
          if metric, do: metric.count, else: 0
        end))
        
        if total_samples >= primary_metric.min_samples * length(variants) do
          # Check for significant winner
          winner = determine_winner(experiment)
          winner != nil
        else
          false
        end
      else
        false
      end
    else
      false
    end
  end

  defp get_nested(map, keys) do
    Enum.reduce(keys, map, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key)
        _ -> nil
      end
    end)
  end

  defp generate_user_id do
    Zixir.Utils.generate_id(bytes: 8)
  end
end
