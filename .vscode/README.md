# Zixir VS Code Extension

This folder is the **Zixir Language Client** extension (syntax, LSP client).

## Install from this repo (development)

**Use this folder, not the repo root.**

1. In VS Code: **Ctrl+Shift+P** → **Developer: Install Extension from Location...**
2. Choose the **`.vscode`** folder:
   - `c:\Users\Legion\Desktop\ExlirZig\.vscode`
   - Or the full path to the repo’s `.vscode` directory on your machine.

VS Code expects a folder that contains a `package.json` with `engines.vscode`. That file is here in `.vscode/`; the repo root has `mix.exs` and is not an extension, so selecting the repo root will fail.

## Build

From the repo root:

```bash
cd .vscode
npm install
npm run compile
```

Then install from location (path = `.vscode` as above).
