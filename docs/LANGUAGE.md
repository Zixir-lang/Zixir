# Zixir Language

## Surface syntax (grammar)

Zixir source is a sequence of **statements**. Each statement is either a **let** binding or an **expression**. Expressions can be used as statements; the last expression's value is the result of the program.

### Statements

- **let** `id` `=` `expr` — bind a name to the value of the expression.
- **expr** — expression statement (e.g. engine call, python call). The last one is the return value.

### Expressions

- **Literals**: numbers (`42`, `3.14`), strings (`"hello"`), lists (`[1, 2, 3]`), maps (`{"a": 1}`).
- **Variable**: identifier (e.g. `x`) — value of a previous `let` binding.
- **Binary ops**: `+`, `-`, `*`, `/` — left-associative, over numbers.
- **Engine call**: `engine.`**op**`(`**args**`)` — runs Zig engine (e.g. `engine.list_sum([1.0, 2.0])`).
- **Python call**: `python` **"module"** **"function"** `(`**args**`)` — calls Python (e.g. `python "math" "sqrt" (4.0)`).
- **Pattern matching**: `match` **expr** `{` **pattern** `->` **body** `,` ... `}` — match value to first matching clause; patterns: literals, variable (binds), array, guards (`==`, `<`).
- **Parentheses**: `(` expr `)`.

### Comments

- From `#` to end of line.

### Example

```zixir
let x = engine.list_sum([1.0, 2.0, 3.0])
let y = 10
x + y
# result: 16.0
```

## Types and semantics

- **Number**: integer or float; engine ops use f64 for lists.
- **String**: UTF-8; engine.string_count returns byte length.
- **List**: ordered; engine ops expect list of numbers where applicable.
- **Map**: string keys, any values.
- **Evaluation**: left-to-right; `let` binds in order; last expression is returned.
- **Engine**: hot path (math, data) — Zig NIFs; keep calls short.
- **Python**: library calls only; returns value or raises on error.

## Standard library (engine)

| Op | Args | Description |
|----|------|-------------|
| `engine.list_sum` | `[numbers]` | Sum of f64 list |
| `engine.list_product` | `[numbers]` | Product of f64 list |
| `engine.dot_product` | `[a, b]` | Dot product of two f64 lists |
| `engine.string_count` | `string` | Byte length of string |

## Entry points

- **Zixir.eval(source)** — parse, compile, evaluate; returns `{:ok, result}` or `{:error, Zixir.CompileError}`.
- **Zixir.run(source)** — like eval but raises on error; returns result.

## Verification

From repo root: `mix deps.get && mix zig.get && mix compile && mix test && mix zixir.run examples/hello.zixir`. On Windows: `scripts\verify.ps1` (with Elixir and Zig on PATH).
