defmodule Mix.Tasks.Zixir.Lsp do
  @moduledoc """
  Start the Zixir Language Server Protocol (LSP) server.

  ## Usage

      mix zixir.lsp

  The server listens on stdin/stdout for JSON-RPC messages.
  """

  use Mix.Task

  @shortdoc "Start Zixir LSP server"

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:zixir)

    case args do
      ["--help" | _] ->
        IO.puts(@moduledoc)

      ["--version" | _] ->
        IO.puts("Zixir LSP Server v#{Application.spec(:zixir, :vsn)}")

      [] ->
        start_lsp_server()

      [arg | _] ->
        IO.puts("Unknown option: #{arg}")
        IO.puts("Use: mix zixir.lsp or mix zixir.lsp --help")
        System.halt(1)
    end
  end

  defp start_lsp_server do
    IO.puts("Starting Zixir LSP Server...")
    IO.puts("Connected to stdin/stdout. Waiting for LSP messages...")
    IO.puts("Press Ctrl+C to stop.")

    case Zixir.LSP.Server.start_link([]) do
      {:ok, pid} ->
        IO.puts("LSP server started (PID: #{inspect(pid)})")
        Zixir.LSP.Server.run()

      {:error, {:already_started, pid}} ->
        IO.puts("LSP server already running (PID: #{inspect(pid)})")
        Zixir.LSP.Server.run()

      {:error, reason} ->
        IO.puts("Failed to start LSP server: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
