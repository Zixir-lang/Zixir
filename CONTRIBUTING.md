# Contributing to Zixir

Thank you for considering contributing to Zixir. This document explains how to build, test, and submit changes.

## Prerequisites

- **Elixir** 1.14+ / OTP 25+
- **Zig** 0.15+ (or run `mix zig.get` after `mix deps.get`)
- **Git**

Optional: Python 3.8+ (for specialist calls), Beaver (Unix, for MLIR).

## Setup

```bash
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
mix deps.get
mix zig.get
mix compile
```

## Running tests

```bash
mix test
```

To run a single test file:

```bash
mix test path/to/test_file_test.exs
```

## Verifying the runtime

After building, verify the JIT path:

```bash
mix zixir run examples/enterprise_test.zr
```

Expected output ends with a number (e.g. `28.75`). Interpreter path:

```bash
mix zixir.run examples/hello.zixir
```

Expected: `11.0`.

## Project layout

| Path | Purpose |
|------|---------|
| `lib/zixir/` | Main application and compiler |
| `lib/zixir/compiler/` | Parser, Zig backend, MLIR, type system, GPU |
| `lib/mix/tasks/` | Mix tasks (`mix zixir`, `mix zixir.run`, `mix zixir.lsp`) |
| `priv/zig/` | Zig runtime and bridges |
| `priv/python/` | Python port bridge |
| `.vscode/` | VS Code extension (syntax, LSP client) |
| `examples/` | Example Zixir scripts |
| `docs/` | Documentation |
| `test/` | ExUnit tests |

The canonical source is under `lib/`. Do not rely on the nested `Zixir/` directory; it may be legacy or reference-only.

## Code style

- Follow the existing style in the codebase (indentation, naming).
- Run the formatter: `mix format`.
- Use consistent import ordering (stdlib, third-party, local).

## Submitting changes

1. **Fork** the repository on GitHub.
2. **Create a branch** from `master`: `git checkout -b my-feature`.
3. **Make your changes.** Keep commits focused and messages clear.
4. **Run** `mix compile`, `mix test`, and `mix zixir run examples/enterprise_test.zr`.
5. **Push** to your fork and open a **Pull Request** against `Zixir-lang/Zixir` `master`.
6. In the PR description, briefly explain what changed and why.

## Areas that welcome contributions

- Tests (especially for compiler/Zig backend and edge cases)
- Documentation (examples, use cases, clarifications)
- Bug fixes and small improvements
- Examples (`.zr` / `.zixir` scripts)

For larger features (e.g. new language constructs or backend changes), open an issue first to discuss.

## Questions

Open an [issue](https://github.com/Zixir-lang/Zixir/issues) for bugs, feature ideas, or questions.
