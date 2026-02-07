defmodule Zixir.MixProject do
  use Mix.Project

  @version "7.0.0"
  @source_url "https://github.com/Zixir-lang/Zixir"

  def project do
    [
      app: :zixir,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Zixir: small, expression-oriented language and three-tier runtime — Elixir (orchestrator), Zig (engine), Python (specialist)",
      package: package(),
      docs: docs(),
      aliases: aliases(),
      releases: releases(),
      test_pattern: "*_test.exs",
      test_ignore_filters: [~r/test\/support\//]
    ]
  end

  defp releases do
    [
      zixir: [
        version: @version,
        include_executables_for: [:unix, :windows],
        applications: [runtime_tools: :permanent],
        overlays: ["rel/overlays"],
        strip_beams: true
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Zixir.Application, []}
    ]
  end

  defp deps do
    [
      # Use GitHub so priv/erl_nif_win is present on Windows (Hex omits it). Tag is 0.15.2.
      # IMPORTANT: Zig NIFs require Zig 0.15.x exactly. If you have Zig 0.16+, comment out zigler
      # and the project will use pure Elixir fallbacks (slower but universal compatibility).
      # {:zigler, [github: "E-xyza/zigler", ref: "0.15.2", runtime: false]},
      {:erlport, "~> 0.10"},
      {:jason, "~> 1.4"},
      {:nimble_parsec, "~> 1.4"},
      {:httpoison, "~> 2.2"},

      # Phoenix Web Framework (minimal - no LiveView, no Ecto)
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_view, "~> 2.0"},
      {:gettext, "~> 0.20"},

      # Lightweight HTTP server
      {:bandit, "~> 1.0"},

      # File upload processing
      {:pdf_extractor, "~> 0.5"},
      {:docxelixir, "~> 1.0"},
      {:floki, "~> 0.35"}
      # Optional MLIR (Beaver): add {:beaver, "~> 0.4"} on Unix only; Kinda does not support Windows.
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "project_Analysis_for_fork.md"]
    ]
  end

  defp aliases do
    [
      test: ["compile", "test"]
    ]
  end
end
