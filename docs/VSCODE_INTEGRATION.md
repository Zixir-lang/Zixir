# Zixir VS Code Integration Guide

This document describes how to set up Zixir language support in Visual Studio Code.

## Quick Setup (Recommended)

### Option 1: Using LSP Extension (Easiest)

1. **Install VS Code Extension**
   - Open VS Code
   - Press `Ctrl+Shift+X` to open Extensions
   - Search for "LSP" or "LSP Language Server Protocol"
   - Install the "LSP" extension by **Tomoki1206** (or "LSP-py" for Python-based LSP)

2. **Configure LSP Client**
   - Open VS Code settings (`Ctrl+,`)
   - Search for "LSP Language Server Configuration"
   - Click "Edit in settings.json"
   - Add the following configuration:

```json
{
  "LSP": {
    "LanguageServerConfiguration": {
      "zixir": {
        "command": "mix",
        "args": ["zixir.lsp"],
        "transport": "stdio",
        "languageId": "zixir",
        "documentSelector": ["zixir"],
        "configurationSection": "zixir"
      }
    }
  },
  "[zixir]": {
    "editor.defaultFormatter": null,
    "editor.tabSize": 2
  }
}
```

3. **Restart VS Code**

### Option 2: Using Elixir LS (Limited Support)

If you have Elixir LS installed, Zixir files will inherit some basic editing features:

1. Install **ElixirLS** extension from VS Code marketplace
2. Open a `.zixir` or `.zr` file
3. Basic syntax highlighting and formatting should work

## Manual Setup

### For Developers: Running Zixir LSP

```bash
# Start the LSP server
mix zixir.lsp

# With verbose logging
mix zixir.lsp --help
```

### VS Code Settings (.vscode/settings.json)

Create `.vscode/settings.json`:

```json
{
  "files.associations": {
    "*.zixir": "zixir",
    "*.zr": "zixir"
  },
  "[zixir]": {
    "editor.defaultFormatter": null,
    "editor.tabSize": 2,
    "editor.insertSpaces": true,
    "editor.formatOnSave": false,
    "editor.wordBasedSuggestions": "currentDocument",
    "editor.semanticHighlighting.enabled": true
  },
  "files.watcherExclude": {
    "**/_zixir_cache/**": true,
    "**/_build/**": true,
    "**/node_modules/**": true
  },
  "search.exclude": {
    "**/_zixir_cache": true,
    "**/_build": true
  }
}
```

### Syntax Highlighting

The `.vscode/syntaxes/zixir.tmLanguage.json` file provides syntax highlighting for Zixir files.

## Zixir File Types

| Extension | Type | Description |
|-----------|------|-------------|
| `.zixir` | Source | Main Zixir source files |
| `.zr` | Source | Short-form Zixir files |

## Example Zixir Code

```zixir
// Zixir example
let x = 42
let result = engine.list_sum([1.0, 2.0, 3.0])
python "numpy" "array" ([[1, 2], [3, 4]])
```

## Troubleshooting

### LSP Not Connecting

1. Ensure `mix` is in your PATH
2. Run `mix zixir.lsp` manually to verify it starts
3. Check VS Code Developer Tools (`Help > Toggle Developer Tools`)

### No Syntax Highlighting

1. Reload VS Code window: `Ctrl+Shift+P` > "Developer: Reload Window"
2. Check that `.vscode/extensions.json` references are correct
3. Verify the grammar file exists at `.vscode/syntaxes/zixir.tmLanguage.json`

### Extension Conflicts

If using multiple language extensions:
1. Use "Language Specific" settings
2. Configure `editor.defaultFormatter` per language
3. Disable conflicting extensions

## Install bundled extension from this repo

To install the Zixir extension from the repo (development):

1. **Ctrl+Shift+P** → **Developer: Install Extension from Location...**
2. Select the **`.vscode`** folder (e.g. `c:\Users\Legion\Desktop\ExlirZig\.vscode`), **not** the repo root.

VS Code looks for a `package.json` with `engines.vscode` in the chosen folder. The extension lives in `.vscode/`; the repo root has `mix.exs` and is not an extension, so choosing the repo root will fail with "Cannot find a valid extension from the location".

## Development

To modify the LSP client:

1. Edit `.vscode/client/src/extension.ts`
2. Run `npm install` in `.vscode/`
3. Compile with `npm run compile` (from `.vscode/`)
4. Package extension with `vsce package`

## Related Files

- `.vscode/package.json` - Extension manifest
- `.vscode/language-configuration.json` - Editor settings for Zixir
- `.vscode/syntaxes/zixir.tmLanguage.json` - Syntax highlighting rules
- `lib/mix/tasks/zixir.lsp.ex` - Zixir LSP server implementation
- `lib/zixir/lsp/server.ex` - LSP protocol implementation
