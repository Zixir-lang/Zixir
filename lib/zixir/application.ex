defmodule Zixir.Application do
  @moduledoc """
  Application and top-level supervision tree for Zixir.
  All long-lived components (intent router, memory, Python port workers) run under this supervisor.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core infrastructure
      {Registry, keys: :unique, name: Zixir.Python.Registry},
      {Registry, keys: :duplicate, name: Zixir.Events.Registry},
      Zixir.Events,
      Zixir.Memory,
      
      # Python bridge
      Zixir.Python.CircuitBreaker,
      Zixir.Python.Supervisor,
      
      # Module system
      Zixir.Modules,
      
      # AI Automation services
      # Zixir.Workflow,  # Not a GenServer, use directly
      Zixir.Sandbox,
      Zixir.Stream,
      Zixir.Observability,
      Zixir.Cache,
      
      # Autonomous AI features
      Zixir.Drift,
      Zixir.Experiment,
      Zixir.Quality,
      
      # Intent router (last, depends on all above)
      Zixir.Intent,
      
      # Web Dashboard
      ZixirWeb.Endpoint
    ]

    opts = [
      strategy: :rest_for_one,
      max_restarts: Application.get_env(:zixir, :max_restarts, 10),
      max_seconds: Application.get_env(:zixir, :restart_window_seconds, 30)
    ]

    Supervisor.start_link(children, opts)
  end
end
