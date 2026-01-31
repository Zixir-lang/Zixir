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
      Zixir.Memory,
      
      # Python bridge
      Zixir.Python.CircuitBreaker,
      Zixir.Python.Supervisor,
      
      # Module system
      Zixir.Modules,
      
      # AI Automation services
      Zixir.Workflow,
      Zixir.Sandbox,
      Zixir.Stream,
      Zixir.Observability,
      Zixir.Cache,
      
      # Intent router (last, depends on all above)
      Zixir.Intent
    ]

    opts = [
      strategy: :rest_for_one,
      max_restarts: Application.get_env(:zixir, :max_restarts, 10),
      max_seconds: Application.get_env(:zixir, :restart_window_seconds, 30)
    ]

    Supervisor.start_link(children, opts)
  end
end
