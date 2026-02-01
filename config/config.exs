import Config

config :zixir,
  python_path: System.find_executable("python3") || System.find_executable("python"),
  python_workers_max: 4,
  restart_window_seconds: 5,
  max_restarts: 3,
  
  # Default timeouts (in milliseconds)
  default_timeout: 30_000,
  python_timeout: 30_000,
  workflow_step_timeout: 30_000,
  
  # Module-specific timeouts
  sandbox_timeout: 30_000,
  stream_timeout: 30_000,
  modules_timeout: 30_000,
  circuit_breaker_cooldown: 30_000,
  
  # Default paths for persistence
  workflow_checkpoint_dir: "_zixir_workflows",
  cache_persist_dir: "_zixir_cache"

if config_env() == :test do
  config :zixir,
    python_workers_max: 1
end
