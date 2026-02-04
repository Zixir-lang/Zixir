# Zixir standard library and built-ins

This document lists what is available “in the box” in Zixir—no extra deps required for core use.

## Language basics

- **Literals:** integers, floats, strings, booleans, arrays `[a, b, c]`
- **Bindings:** `let name = expr`
- **Binary ops:** `+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `and`, `or`
- **Control flow:** `if cond then ... else ...`, `for x in arr { ... }`, `while cond { ... }`
- **Functions:** `fn name(params) -> return_type: body`
- **Pattern matching:** `match value: pattern => body, ...` (parsed and codegen for common cases)
- **Pipe:** `a |> f(b)` → `f(a, b)`
- **Comments:** `# line comment`

## Engine (Zig NIFs)

Fast numeric and core operations; call as `engine.<op>(args)`.

| Operation | Signature | Description |
|-----------|-----------|-------------|
| `engine.list_sum` | `(array of Float)` | Sum of array elements. |
| `engine.list_product` | `(array of Float)` | Product of array elements. |
| `engine.dot_product` | `(array, array)` | Dot product of two float arrays. |
| `engine.string_count` | `(string)` | Byte length of string. |

Additional engine operations may be present in the codebase (see `lib/zixir/engine/` and Zig NIFs). The above are the ones used in examples and JIT.

## Python specialist (optional)

- **Syntax:** `python "module" "function" (args)`
- **Runtime:** Via port (default) or NIF when built. Requires Python on PATH or `config :zixir, :python_path`.
- **Use:** Call numpy, pandas, APIs, etc. from Zixir.

## Elixir API (from Elixir code)

When calling Zixir from Elixir (e.g. in tests or tooling):

| Module / function | Purpose |
|--------------------|---------|
| `Zixir.eval/1` | Evaluate Zixir source string; returns `{:ok, result}` or `{:error, reason}`. |
| `Zixir.run/1` | Run Zixir source; returns result or raises. |
| `Zixir.Compiler.compile/1` | Full pipeline: parse, typecheck, optimize (MLIR if enabled), codegen. |
| `Zixir.Compiler.Pipeline.run_string/3` | JIT: parse → Zig → compile → run; returns `{:ok, output}` or `{:error, reason}`. |
| `Zixir.Compiler.Pipeline.compile_file/2` | Compile a `.zr` file to a binary. |
| `Zixir.Compiler.typecheck/1` | Parse and type-check only. |
| `Zixir.call_python/3` | Call Python module/function from Elixir (port). |
| `Zixir.Observability` | Logging, tracing, metrics (see `lib/zixir/observability.ex`). |
| `Zixir.Package` | Package manager: resolve, install (Git/path), list, cache; `zixir.toml` manifest. |

## CLI (Mix tasks)

| Command | Purpose |
|---------|---------|
| `mix zixir run <file.zr>` | JIT run (parse → Zig → execute; prints last expression). |
| `mix zixir compile <file.zr>` | Compile to native binary. |
| `mix zixir check <file.zr>` | Type-check only. |
| `mix zixir repl` | Interactive REPL (JIT evaluation). |
| `mix zixir.run <file.zixir>` | Run via interpreter (`Zixir.eval`). |
| `mix zixir.lsp` | Start LSP server (for editors). |

## Workflow and runtime features

- **Workflow:** Steps, retries, checkpoints, sandboxing (see `lib/zixir/workflow.ex` and related).
- **Cache:** ETS + disk caching (see `lib/zixir/cache.ex`).
- **Experiment:** A/B testing, statistics (see `lib/zixir/experiment.ex`).
- **Observability:** Structured logging, tracing, metrics (see `lib/zixir/observability.ex`).

## Optional or toolchain-dependent

- **MLIR (Phase 4):** Optional; with Beaver (Unix) you get full MLIR; without, AST-level optimizations. See [MLIR_AND_PYTHON.md](MLIR_AND_PYTHON.md).
- **GPU:** Detection and codegen for CUDA/ROCm/Metal when the corresponding toolchain is installed.
- **Python NIF:** Optional faster Python path when the NIF is built; port is the default.

For implementation status and details, see [PROJECT_ANALYSIS.md](../PROJECT_ANALYSIS.md).
