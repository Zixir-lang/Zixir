defmodule Zixir.LSP.Server do
  @moduledoc """
  Language Server Protocol (LSP) implementation for Zixir.
  
  Provides IDE features:
  - Syntax highlighting (via TextMate grammar)
  - Diagnostics (error/warning reporting)
  - Go to definition
  - Find references
  - Hover information
  - Code completion
  - Formatting
  """

  use GenServer
  require Logger

  alias Zixir.Compiler.Parser
  alias Zixir.Compiler.TypeSystem

  # LSP Protocol constants

  defmodule State do
    defstruct [
      :client_capabilities,
      :root_uri,
      :documents,
      :diagnostics,
      :initialized
    ]
  end

  defmodule Document do
    defstruct [:uri, :version, :text, :ast, :errors]
  end

  # Client API

  @doc """
  Start the LSP server GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start the LSP server and listen on stdin/stdout.
  """
  @spec run() :: :ok
  def run do
    {:ok, _} = start_link()
    
    # Read messages from stdin
    loop_io()
  end

  defp loop_io do
    case read_message() do
      {:ok, message} ->
        handle_message(message)
        loop_io()
      
      {:error, :eof} ->
        Logger.info("LSP client disconnected")
        :ok
      
      {:error, reason} ->
        Logger.error("LSP read error: #{inspect(reason)}")
        loop_io()
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %State{
      client_capabilities: %{},
      root_uri: nil,
      documents: %{},
      diagnostics: %{},
      initialized: false
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:handle_message, message}, _from, state) do
    {response, new_state} = process_message(message, state)
    {:reply, response, new_state}
  end

  @impl true
  def handle_cast({:send_notification, method, params}, state) do
    send_notification(method, params)
    {:noreply, state}
  end

  # Message handling

  defp read_message do
    # Read Content-Length header
    case IO.read(:line) do
      :eof -> 
        {:error, :eof}
      
      header ->
        header = String.trim(header)
        
        if String.starts_with?(header, "Content-Length: ") do
          length = header |> String.replace("Content-Length: ", "") |> String.to_integer()
          
          # Read empty line
          _ = IO.read(:line)
          
          # Read body
          body = IO.read(length)
          
          case Jason.decode(body) do
            {:ok, message} -> {:ok, message}
            {:error, _} -> {:error, :invalid_json}
          end
        else
          read_message()
        end
    end
  end

  defp handle_message(message) do
    GenServer.call(__MODULE__, {:handle_message, message})
  end

  defp process_message(%{"jsonrpc" => "2.0", "id" => id, "method" => method} = message, state) do
    params = message["params"] || %{}
    
    case method do
      "initialize" ->
        {handle_initialize(id, params, state), %{state | initialized: true}}
      
      "initialized" ->
        {nil, state}
      
      "shutdown" ->
        {make_response(id, nil), state}
      
      "textDocument/didOpen" ->
        {nil, handle_did_open(params, state)}
      
      "textDocument/didChange" ->
        {nil, handle_did_change(params, state)}
      
      "textDocument/didClose" ->
        {nil, handle_did_close(params, state)}
      
      "textDocument/didSave" ->
        {nil, handle_did_save(params, state)}
      
      "textDocument/definition" ->
        {handle_definition(id, params, state), state}
      
      "textDocument/hover" ->
        {handle_hover(id, params, state), state}
      
      "textDocument/completion" ->
        {handle_completion(id, params, state), state}
      
      "textDocument/formatting" ->
        {handle_formatting(id, params, state), state}
      
      "textDocument/documentSymbol" ->
        {handle_document_symbol(id, params, state), state}
      
      _ ->
        {make_error_response(id, -32601, "Method not found: #{method}"), state}
    end
  end

  defp process_message(%{"jsonrpc" => "2.0", "method" => method} = message, state) do
    params = message["params"] || %{}
    
    case method do
      "textDocument/didOpen" ->
        {nil, handle_did_open(params, state)}
      
      "textDocument/didChange" ->
        {nil, handle_did_change(params, state)}
      
      "textDocument/didClose" ->
        {nil, handle_did_close(params, state)}
      
      "textDocument/didSave" ->
        {nil, handle_did_save(params, state)}
      
      "exit" ->
        System.halt(0)
      
      _ ->
        {nil, state}
    end
  end

  defp process_message(_, state) do
    {nil, state}
  end

  # LSP method handlers

  defp handle_initialize(id, params, _state) do
    _root_uri = params["rootUri"]
    _client_capabilities = params["capabilities"] || %{}
    
    server_capabilities = %{
      "textDocumentSync" => %{
        "openClose" => true,
        "change" => 2,  # Incremental
        "willSave" => false,
        "willSaveWaitUntil" => false,
        "save" => %{"includeText" => false}
      },
      "hoverProvider" => true,
      "completionProvider" => %{
        "triggerCharacters" => ["."],
        "resolveProvider" => false
      },
      "definitionProvider" => true,
      "documentSymbolProvider" => true,
      "documentFormattingProvider" => true,
      "diagnosticProvider" => %{
        "interFileDependencies" => false,
        "workspaceDiagnostics" => false
      }
    }
    
    result = %{
      "capabilities" => server_capabilities,
      "serverInfo" => %{
        "name" => "zixir-lsp",
        "version" => "0.1.0"
      }
    }
    
    make_response(id, result)
  end

  defp handle_did_open(params, state) do
    text_document = params["textDocument"]
    uri = text_document["uri"]
    text = text_document["text"]
    version = text_document["version"]
    
    document = parse_document(uri, text, version)
    documents = Map.put(state.documents, uri, document)
    
    # Send diagnostics
    send_diagnostics(uri, document.errors)
    
    %{state | documents: documents}
  end

  defp handle_did_change(params, state) do
    text_document = params["textDocument"]
    uri = text_document["uri"]
    version = text_document["version"]
    changes = params["contentChanges"]
    
    case Map.get(state.documents, uri) do
      nil ->
        state
      
      doc ->
        new_text = apply_content_changes(doc.text, changes)
        new_doc = parse_document(uri, new_text, version)
        documents = Map.put(state.documents, uri, new_doc)
        
        # Send updated diagnostics
        send_diagnostics(uri, new_doc.errors)
        
        %{state | documents: documents}
    end
  end

  defp handle_did_close(params, state) do
    uri = params["textDocument"]["uri"]
    documents = Map.delete(state.documents, uri)
    
    # Clear diagnostics
    send_diagnostics(uri, [])
    
    %{state | documents: documents}
  end

  defp handle_did_save(_params, state) do
    # Could trigger full project analysis here
    state
  end

  defp handle_definition(id, params, state) do
    text_document = params["textDocument"]
    uri = text_document["uri"]
    position = params["position"]
    line = position["line"]
    character = position["character"]
    
    case Map.get(state.documents, uri) do
      nil ->
        make_response(id, nil)
      
      doc ->
        result = find_definition(doc, line, character)
        make_response(id, result)
    end
  end

  defp handle_hover(id, params, state) do
    text_document = params["textDocument"]
    uri = text_document["uri"]
    position = params["position"]
    line = position["line"]
    character = position["character"]
    
    case Map.get(state.documents, uri) do
      nil ->
        make_response(id, nil)
      
      doc ->
        contents = get_hover_info(doc, line, character)
        
        result = if contents do
          %{
            "contents" => contents,
            "range" => nil
          }
        else
          nil
        end
        
        make_response(id, result)
    end
  end

  defp handle_completion(id, params, state) do
    text_document = params["textDocument"]
    uri = text_document["uri"]
    position = params["position"]
    line = position["line"]
    character = position["character"]
    
    case Map.get(state.documents, uri) do
      nil ->
        make_response(id, nil)
      
      doc ->
        items = get_completions(doc, line, character)
        make_response(id, %{"items" => items, "isIncomplete" => false})
    end
  end

  defp handle_formatting(id, params, state) do
    text_document = params["textDocument"]
    uri = text_document["uri"]
    
    case Map.get(state.documents, uri) do
      nil ->
        make_response(id, nil)
      
      doc ->
        formatted = format_document(doc)
        
        edits = [
          %{
            "range" => %{
              "start" => %{"line" => 0, "character" => 0},
              "end" => %{"line" => 999999, "character" => 0}
            },
            "newText" => formatted
          }
        ]
        
        make_response(id, edits)
    end
  end

  defp handle_document_symbol(id, params, state) do
    text_document = params["textDocument"]
    uri = text_document["uri"]
    
    case Map.get(state.documents, uri) do
      nil ->
        make_response(id, [])
      
      doc ->
        symbols = extract_document_symbols(doc)
        make_response(id, symbols)
    end
  end

  # Helper functions

  defp parse_document(uri, text, version) do
    case Parser.parse(text) do
      {:ok, ast} ->
        errors = []
        
        # Run type checking if available
        errors = case TypeSystem.infer(ast) do
          {:ok, _} -> errors
          {:error, error} -> [error | errors]
        end
        
        %Document{uri: uri, version: version, text: text, ast: ast, errors: errors}
      
      {:error, error} ->
        %Document{uri: uri, version: version, text: text, ast: nil, errors: [error]}
    end
  end

  defp apply_content_changes(text, changes) do
    Enum.reduce(changes, text, fn change, acc ->
      if change["range"] do
        # Incremental change
        range = change["range"]
        start_line = range["start"]["line"]
        start_char = range["start"]["character"]
        end_line = range["end"]["line"]
        end_char = range["end"]["character"]
        new_text = change["text"]
        
        lines = String.split(acc, "\n")
        
        # Extract prefix and suffix
        prefix_lines = Enum.take(lines, start_line)
        prefix = if start_line > 0 do
          Enum.join(prefix_lines, "\n") <> "\n"
        else
          ""
        end
        
        start_line_text = Enum.at(lines, start_line, "")
        prefix = prefix <> String.slice(start_line_text, 0, start_char)
        
        suffix_lines = Enum.drop(lines, end_line + 1)
        end_line_text = Enum.at(lines, end_line, "")
        suffix = String.slice(end_line_text, end_char..-1//1)
        suffix = if length(suffix_lines) > 0 do
          suffix <> "\n" <> Enum.join(suffix_lines, "\n")
        else
          suffix
        end
        
        prefix <> new_text <> suffix
      else
        # Full document change
        change["text"]
      end
    end)
  end

  defp find_definition(doc, line, character) do
    # Extract identifier at position
    identifier = get_identifier_at_position(doc.text, line, character)
    
    if identifier do
      # Search for definition in AST
      find_identifier_definition(doc.ast, identifier)
    else
      nil
    end
  end

  defp get_identifier_at_position(text, line, character) do
    lines = String.split(text, "\n")
    target_line = Enum.at(lines, line, "")
    
    # Find word boundaries around character
    left = String.slice(target_line, 0, character)
    right = String.slice(target_line, character..-1//1)
    
    left_part = Regex.run(~r/[a-zA-Z_][a-zA-Z0-9_]*$/, left) |> List.first("")
    right_part = Regex.run(~r/^[a-zA-Z0-9_]*/, right) |> List.first("")
    
    identifier = left_part <> right_part
    
    if String.length(identifier) > 0 do
      identifier
    else
      nil
    end
  end

  defp find_identifier_definition({:program, statements}, identifier) do
    Enum.find_value(statements, fn stmt ->
      find_identifier_in_statement(stmt, identifier)
    end)
  end

  defp find_identifier_in_statement({:function, name, _params, _ret, _body, _pub, line, col}, identifier) do
    if name == identifier do
      %{
        "uri" => "",
        "range" => %{
          "start" => %{"line" => line - 1, "character" => col - 1},
          "end" => %{"line" => line - 1, "character" => col - 1 + String.length(identifier)}
        }
      }
    else
      nil
    end
  end

  defp find_identifier_in_statement({:let, name, _expr, line, col}, identifier) do
    if name == identifier do
      %{
        "uri" => "",
        "range" => %{
          "start" => %{"line" => line - 1, "character" => col - 1},
          "end" => %{"line" => line - 1, "character" => col - 1 + String.length(identifier)}
        }
      }
    else
      nil
    end
  end

  defp find_identifier_in_statement(_, _), do: nil

  defp get_hover_info(doc, line, character) do
    identifier = get_identifier_at_position(doc.text, line, character)
    
    if identifier do
      # Get type information if available
      type_info = get_type_at_position(doc.ast, identifier)
      
      if type_info do
        %{
          "kind" => "markdown",
          "value" => "```zixir\n#{identifier}: #{type_info}\n```"
        }
      else
        nil
      end
    else
      nil
    end
  end

  defp get_type_at_position({:program, statements}, identifier) do
    Enum.find_value(statements, fn stmt ->
      get_type_from_statement(stmt, identifier)
    end)
  end

  defp get_type_from_statement({:function, name, params, return_type, _body, _pub, _line, _col}, identifier) do
    if name == identifier do
      params_str = Enum.map(params, fn {pname, ptype} ->
        "#{pname}: #{format_type(ptype)}"
      end) |> Enum.join(", ")
      
      ret_str = format_type(return_type)
      "fn #{name}(#{params_str}) -> #{ret_str}"
    else
      nil
    end
  end

  defp get_type_from_statement({:let, name, _expr, _line, _col}, identifier) do
    if name == identifier do
      # Would need type inference result
      "inferred"
    else
      nil
    end
  end

  defp get_type_from_statement(_, _), do: nil

  defp format_type({:type, :auto}), do: "auto"
  defp format_type({:type, name}) when is_atom(name), do: Atom.to_string(name)
  defp format_type(_), do: "unknown"

  defp get_completions(doc, line, character) do
    # Get context at position
    prefix = get_line_prefix(doc.text, line, character)
    
    # Build completion items
    items = []
    
    # Add keywords
    items = items ++ [
      %{"label" => "fn", "kind" => 14, "detail" => "keyword"},
      %{"label" => "let", "kind" => 14, "detail" => "keyword"},
      %{"label" => "if", "kind" => 14, "detail" => "keyword"},
      %{"label" => "else", "kind" => 14, "detail" => "keyword"},
      %{"label" => "return", "kind" => 14, "detail" => "keyword"},
      %{"label" => "match", "kind" => 14, "detail" => "keyword"},
      %{"label" => "type", "kind" => 14, "detail" => "keyword"},
      %{"label" => "pub", "kind" => 14, "detail" => "keyword"},
      %{"label" => "import", "kind" => 14, "detail" => "keyword"},
      %{"label" => "extern", "kind" => 14, "detail" => "keyword"}
    ]
    
    # Add built-in types
    items = items ++ [
      %{"label" => "Int", "kind" => 7, "detail" => "type"},
      %{"label" => "Float", "kind" => 7, "detail" => "type"},
      %{"label" => "Bool", "kind" => 7, "detail" => "type"},
      %{"label" => "String", "kind" => 7, "detail" => "type"},
      %{"label" => "Void", "kind" => 7, "detail" => "type"}
    ]
    
    # Add functions from document
    items = items ++ get_document_completions(doc)
    
    # Filter based on prefix
    if String.length(prefix) > 0 do
      Enum.filter(items, fn item ->
        String.starts_with?(item["label"], prefix)
      end)
    else
      items
    end
  end

  defp get_line_prefix(text, line, character) do
    lines = String.split(text, "\n")
    target_line = Enum.at(lines, line, "")
    String.slice(target_line, 0, character)
    |> String.replace(~r/.*[^a-zA-Z0-9_]/, "")
  end

  defp get_document_completions(doc) do
    case doc.ast do
      {:program, statements} ->
        Enum.flat_map(statements, fn
          {:function, name, _params, _ret, _body, _pub, _line, _col} ->
            [%{"label" => name, "kind" => 3, "detail" => "function"}]
          
          {:let, name, _expr, _line, _col} ->
            [%{"label" => name, "kind" => 6, "detail" => "variable"}]
          
          _ ->
            []
        end)
      
      _ ->
        []
    end
  end

  defp format_document(doc) do
    # Simple formatter - just ensure consistent spacing
    doc.text
    |> String.replace(~r/\n\s*\n\s*\n/, "\n\n")
    |> String.replace(~r/\{\s*\n/, "{\n")
    |> String.replace(~r/\n\s*\}/, "\n}")
  end

  defp extract_document_symbols(doc) do
    case doc.ast do
      {:program, statements} ->
        Enum.flat_map(statements, fn
          {:function, name, _params, _ret, _body, _pub, line, col} ->
            [%{
              "name" => name,
              "kind" => 12,  # Function
              "location" => %{
                "uri" => doc.uri,
                "range" => %{
                  "start" => %{"line" => line - 1, "character" => col - 1},
                  "end" => %{"line" => line - 1, "character" => col - 1}
                }
              }
            }]
          
          {:type_def, name, _def, line, col} ->
            [%{
              "name" => name,
              "kind" => 10,  # Type
              "location" => %{
                "uri" => doc.uri,
                "range" => %{
                  "start" => %{"line" => line - 1, "character" => col - 1},
                  "end" => %{"line" => line - 1, "character" => col - 1}
                }
              }
            }]
          
          _ ->
            []
        end)
      
      _ ->
        []
    end
  end

  # Response helpers

  defp make_response(id, result) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
    |> Jason.encode!()
    |> send_message()
  end

  defp make_error_response(id, code, message) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => code,
        "message" => message
      }
    }
    |> Jason.encode!()
    |> send_message()
  end

  defp send_notification(method, params) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params
    }
    |> Jason.encode!()
    |> send_message()
  end

  defp send_diagnostics(uri, errors) do
    diagnostics = Enum.map(errors, fn error ->
      %{
        "range" => %{
          "start" => %{
            "line" => (error.line || 1) - 1,
            "character" => (error.column || 1) - 1
          },
          "end" => %{
            "line" => (error.line || 1) - 1,
            "character" => 999
          }
        },
        "severity" => 1,  # Error
        "message" => error.message
      }
    end)
    
    send_notification("textDocument/publishDiagnostics", %{
      "uri" => uri,
      "diagnostics" => diagnostics
    })
  end

  defp send_message(json) do
    body = json <> "\n"
    header = "Content-Length: #{byte_size(body)}\r\n\r\n"
    IO.write(:stdio, header <> body)
  end
end
