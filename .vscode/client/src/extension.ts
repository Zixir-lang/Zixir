import * as path from 'path';
import * as vscode from 'vscode';
import { LanguageClient, LanguageClientOptions, ServerOptions, TransportKind } from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const serverModule = context.asAbsolutePath('server/out/server.js');
  const serverOptions: ServerOptions = {
    run: {
      module: serverModule,
      transport: TransportKind.stdio,
      args: ['--stdio']
    },
    debug: {
      module: serverModule,
      transport: TransportKind.stdio,
      options: {
        execArgv: ['--nolazy', '--inspect=6009']
      }
    }
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'zixir' }],
    synchronize: {
      configurationSection: 'zixir'
    },
    traceOutputChannel: vscode.window.createOutputChannel('Zixir LSP Trace')
  };

  client = new LanguageClient(
    'zixirLanguageServer',
    'Zixir Language Server',
    serverOptions,
    clientOptions
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('zixir.startServer', async () => {
      if (client) {
        await client.start();
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('zixir.stopServer', async () => {
      if (client) {
        await client.stop();
      }
    })
  );

  try {
    await client.start();
    vscode.window.showInformationMessage('Zixir Language Server started');
  } catch (error) {
    vscode.window.showErrorMessage(`Failed to start Zixir Language Server: ${error}`);
  }
}

export async function deactivate(): Promise<void> {
  if (client) {
    await client.stop();
    client = undefined;
  }
}
