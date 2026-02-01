import Config

config :zixir,
  python_path: System.find_executable("python3") || System.find_executable("python"),
  python_workers_max: 4,
  restart_window_seconds: 5,
  max_restarts: 3,
  
  # Default timeouts (in milliseconds)
  default_timeout: 30_000,
  python_timeout: 30_000,
  workflow_step_timeout: 30_000

if config_env() == :test do
  config :zixir,
    python_workers_max: 1
end
