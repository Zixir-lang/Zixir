# Zixir Documentation Index

Welcome to Zixir! This index will help you find the documentation you need.

## 📚 Documentation Files

### Getting Started
- **[README.md](../README.md)** - Project overview and quick setup
- **[SETUP_GUIDE.md](../SETUP_GUIDE.md)** - Step-by-step install (Elixir, Zig, Python) per OS
- **[GUIDE.md](../GUIDE.md)** - Complete user guide with examples
- **[QUICKREF.md](../QUICKREF.md)** - Quick reference cheat sheet
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** - How to build, test, and contribute
- **[ROADMAP.md](../ROADMAP.md)** - Public roadmap and priorities

### Why Zixir and use cases
- **[WHY_ZIXIR_AND_COMPARISON.md](WHY_ZIXIR_AND_COMPARISON.md)** - Why Zixir exists and comparison with Airflow, Prefect, Temporal
- **[USE_CASES.md](USE_CASES.md)** - Real-world use cases (pipelines, agentic, numeric services, ETL, edge)
- **[CONFIG_AND_DEPLOY.md](CONFIG_AND_DEPLOY.md)** - Configuration options and production deployment
- **[STANDARD_LIBRARY.md](STANDARD_LIBRARY.md)** - What's in the box (engine, CLI, Elixir API, workflow, cache)

### Language Reference
- **[LANGUAGE.md](LANGUAGE.md)** - Formal language specification
- **[COMPILER_SUMMARY.md](../COMPILER_SUMMARY.md)** - Compiler architecture overview
- **[MLIR_AND_PYTHON.md](MLIR_AND_PYTHON.md)** - How MLIR (Phase 4) fits with the three-tier runtime (Elixir, Zig, Python)

### Examples
- **[tutorial.zr](../examples/tutorial.zr)** - Step-by-step tutorial
- **[hello.zixir](../examples/hello.zixir)** - Simple hello world example
- **[demo.zr](../examples/demo.zr)** - Advanced features demonstration

## 🚀 Quick Start

```bash
# 1. Setup
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
mix deps.get
mix zig.get
mix compile

# 2. Try an example
mix zixir.run examples/hello.zixir
```

## 📖 Learning Path

### Beginner
1. Read [GUIDE.md](../GUIDE.md) - "What is Zixir?" and "Quick Start"
2. Run `examples/tutorial.zr`
3. Try modifying the tutorial examples
4. Check [QUICKREF.md](../QUICKREF.md) for syntax

### Intermediate
1. Read [GUIDE.md](../GUIDE.md) - "Complete Examples" section
2. Study [LANGUAGE.md](LANGUAGE.md) - "Types and semantics"
3. Run `examples/demo.zr` to see advanced features
4. Write your own Zixir programs

### Advanced
1. Read [COMPILER_SUMMARY.md](../COMPILER_SUMMARY.md)
2. Study the compiler source in `lib/zixir/compiler/`
3. Read [project_Analysis_for_fork.md](../project_Analysis_for_fork.md)
4. Contribute to the project!

## 🎯 Common Tasks

| Task | Documentation |
|------|---------------|
| Learn the language | [GUIDE.md](../GUIDE.md) |
| Quick syntax lookup | [QUICKREF.md](../QUICKREF.md) |
| Run a program | [GUIDE.md](../GUIDE.md) - "Running Zixir Programs" |
| Use engine operations | [GUIDE.md](../GUIDE.md) - "Engine Operations" |
| Call Python | [GUIDE.md](../GUIDE.md) - "Python Integration" |
| Understand types | [LANGUAGE.md](LANGUAGE.md) - "Types and semantics" |
| CLI commands | [GUIDE.md](../GUIDE.md) - "CLI Reference" |
| API reference | [GUIDE.md](../GUIDE.md) - "Elixir API" |

## 🔧 Available Operations

### Engine Operations (Zig)
- `engine.list_sum([Float])` - Sum array elements
- `engine.list_product([Float])` - Multiply array elements
- `engine.dot_product([Float], [Float])` - Dot product
- `engine.string_count(String)` - String byte length

### Python Integration
- `python "module" "function" (args)` - Call any Python function

## 📁 Project Structure

```
ExlirZig/
├── docs/               # Documentation
│   ├── LANGUAGE.md     # Language specification
│   └── INDEX.md        # This file
├── examples/           # Example programs
│   ├── tutorial.zr     # Learning tutorial
│   ├── hello.zixir     # Simple example
│   └── demo.zr         # Advanced demo
├── lib/                # Source code
│   └── zixir/
│       ├── compiler/   # Compiler modules
│       └── ...
├── test/               # Test files
├── GUIDE.md           # User guide
├── QUICKREF.md        # Quick reference
└── README.md          # Project readme
```

## 💡 Tips

- Start with the [tutorial](../examples/tutorial.zr)
- Keep [QUICKREF.md](../QUICKREF.md) open while coding
- Use `mix zixir repl` to experiment
- Check tests in `test/` for working examples
- Join discussions and contribute!

## 🆘 Need Help?

1. Check the [GUIDE.md](../GUIDE.md) troubleshooting section
2. Look at working examples in `examples/`
3. Review tests in `test/` for usage patterns
4. Read the language spec in [LANGUAGE.md](LANGUAGE.md)

---

**Ready to start?** → Run `mix zixir run examples/tutorial.zr`