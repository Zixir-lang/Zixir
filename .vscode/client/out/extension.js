"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.deactivate = exports.activate = void 0;
const vscode = __importStar(require("vscode"));
const node_1 = require("vscode-languageclient/node");
let client;
async function activate(context) {
    const serverModule = context.asAbsolutePath('server/out/server.js');
    const serverOptions = {
        run: {
            module: serverModule,
            transport: node_1.TransportKind.stdio,
            args: ['--stdio']
        },
        debug: {
            module: serverModule,
            transport: node_1.TransportKind.stdio,
            options: {
                execArgv: ['--nolazy', '--inspect=6009']
            }
        }
    };
    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'zixir' }],
        synchronize: {
            configurationSection: 'zixir'
        },
        traceOutputChannel: vscode.window.createOutputChannel('Zixir LSP Trace')
    };
    client = new node_1.LanguageClient('zixirLanguageServer', 'Zixir Language Server', serverOptions, clientOptions);
    context.subscriptions.push(vscode.commands.registerCommand('zixir.startServer', async () => {
        if (client) {
            await client.start();
        }
    }));
    context.subscriptions.push(vscode.commands.registerCommand('zixir.stopServer', async () => {
        if (client) {
            await client.stop();
        }
    }));
    try {
        await client.start();
        vscode.window.showInformationMessage('Zixir Language Server started');
    }
    catch (error) {
        vscode.window.showErrorMessage(`Failed to start Zixir Language Server: ${error}`);
    }
}
exports.activate = activate;
async function deactivate() {
    if (client) {
        await client.stop();
        client = undefined;
    }
}
exports.deactivate = deactivate;
//# sourceMappingURL=extension.js.map