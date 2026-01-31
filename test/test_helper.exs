# Start the Zixir application
{:ok, _} = Application.ensure_all_started(:zixir)

# Give the application time to start all services
Process.sleep(500)

# Verify critical services are running
services = [
  {Zixir.Workflow, []},
  {Zixir.Sandbox, []},
  {Zixir.Cache, []},
  {Zixir.Observability, []},
  {Zixir.Stream, []}
]

Enum.each(services, fn {module, opts} ->
  case Process.whereis(module) do
    nil -> 
      IO.puts("Starting #{module}...")
      case module.start_link(opts) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        error -> IO.puts("Warning: Could not start #{module}: #{inspect(error)}")
      end
    _ -> 
      :ok
  end
end)

ExUnit.start()
