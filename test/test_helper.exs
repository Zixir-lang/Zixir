# Enhanced Test Helper for Zixir
# This file configures the test environment and starts required services

# Compile test support files first
test_support_dir = Path.join(__DIR__, "support")
support_files = Path.wildcard(Path.join(test_support_dir, "*.ex"))

Enum.each(support_files, fn file ->
  Code.compile_file(file)
end)

# Start the Zixir application
{:ok, _} = Application.ensure_all_started(:zixir)

# Give the application time to start all services
Process.sleep(500)

# Verify critical services are running
services = [
  # Zixir.Workflow,  # Not a GenServer, use directly
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

# Configure ExUnit
ExUnit.configure(
  # Seed for reproducible test runs
  seed: System.get_env("EXUNIT_SEED", "0") |> String.to_integer(),
  
  # Maximum number of concurrent test cases
  max_cases: System.schedulers_online() * 2,
  
  # Enable tracing to see test names as they run
  trace: System.get_env("EXUNIT_TRACE", "false") == "true",
  
  # Formatters
  formatters: [ExUnit.CLIFormatter],
  
  # Exclude certain tests by default
  exclude: [
    # Skip Python integration tests if Python not available
    :python_integration,
    # Skip GPU tests if no GPU available
    :gpu_required,
    # Skip slow tests in quick mode
    :slow,
    # Skip integration tests when running unit tests only
    :integration
  ]
)

# Check environment and configure exclusions
python_available = case System.cmd("python", ["--version"], stderr_to_stdout: true) do
  {_, 0} -> true
  _ -> false
end

if not python_available do
  IO.puts("\n⚠️  Python not available - skipping Python integration tests")
  ExUnit.configure(exclude: [python_integration: true])
end

# Check for GPU
gpu_available = case System.cmd("nvcc", ["--version"], stderr_to_stdout: true) do
  {_, 0} -> true
  _ -> 
    case System.cmd("hipcc", ["--version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
end

if not gpu_available do
  IO.puts("⚠️  GPU not available - skipping GPU tests")
  ExUnit.configure(exclude: [gpu_required: true])
end

# Include slow tests if explicitly requested
if System.get_env("EXUNIT_INCLUDE_SLOW") == "true" do
  IO.puts("✓ Including slow tests")
  ExUnit.configure(include: [slow: true])
end

# Include integration tests if explicitly requested
if System.get_env("EXUNIT_INCLUDE_INTEGRATION") == "true" do
  IO.puts("✓ Including integration tests")
  ExUnit.configure(include: [integration: true])
end

# Start ExUnit
ExUnit.start()

# Print test configuration
IO.puts("\n🧪 Zixir Test Suite")
IO.puts("=" |> String.duplicate(50))
IO.puts("Elixir version: #{System.version()}")
IO.puts("OTP version: #{:erlang.system_info(:otp_release)}")
IO.puts("Schedulers: #{System.schedulers_online()}")
IO.puts("Python available: #{python_available}")
IO.puts("GPU available: #{gpu_available}")
IO.puts("=" |> String.duplicate(50))
IO.puts("")
