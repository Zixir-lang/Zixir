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

# Zixir Web Dashboard Configuration
config :zixir, ZixirWeb.Endpoint,
  url: [host: "localhost", port: 4000],
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  render_errors: [view: ZixirWeb.ErrorView, accepts: [:html]],
  secret_key_base: "dev_secret_key_base_change_in_prod",
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/zixir_web/(controllers|live|views)/.*(ex|eex)$"
    ]
  ]

if config_env() == :test do
  config :zixir,
    python_workers_max: 1
end
