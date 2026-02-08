defmodule Zixir.Ollama do
  @moduledoc """
  Native Ollama integration for local LLM inference.

  Provides:
  - Text generation (/api/generate)
  - Embeddings (/api/embeddings)
  - Model discovery (/api/tags)
  - Streaming responses
  - Health checks

  ## Quick Start

      # Test connection
      {:ok, info} = Zixir.Ollama.health()

      # List available models
      {:ok, models} = Zixir.Ollama.list_models()

      # Generate text
      {:ok, response} = Zixir.Ollama.generate("Hello, world!")

      # Generate with options
      {:ok, response} = Zixir.Ollama.generate("Explain Elixir", model: "llama3.1", temperature: 0.7)

      # Get embeddings
      {:ok, embedding} = Zixir.Ollama.embed("Hello world", model: "nomic-embed-text")

      # Stream response
      {:ok, stream} = Zixir.Ollama.stream("Tell me a story")
      for chunk <- stream, do: print(chunk)

  """

  alias Zixir.Cache
  require Logger

  @default_host "localhost"
  @default_port 11434
  @default_timeout 60_000
  @config_prefix "ollama"

  @typedoc "Ollama model information"
  defstruct [:name, :size, :digest, :modified_at]

  @doc """
  Check Ollama health/status.
  """
  @spec health(keyword()) :: {:ok, map()} | {:error, term()}
  def health(opts \\ []) do
    case request(:get, "/api/version", %{}, opts) do
      {:ok, %{"version" => version}} ->
        {:ok, %{
          status: :healthy,
          version: version,
          host: Keyword.get(opts, :host, @default_host),
          port: Keyword.get(opts, :port, @default_port)
        }}

      {:error, reason} ->
        Logger.warning("Ollama health check failed", error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  List available models from Ollama.

  Returns list of model names and details.
  """
  @spec list_models(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_models(opts \\ []) do
    case request(:post, "/api/tags", %{}, opts) do
      {:ok, %{"models" => models}} ->
        model_list = Enum.map(models, fn m ->
          %{
            name: m["name"],
            size: m["size"],
            digest: m["digest"],
            modified_at: m["modified_at"]
          }
        end)
        {:ok, model_list}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate text with Ollama.

  ## Options

  - `:model` - Model name (default: llama3.1)
  - `:temperature` - Sampling temperature (default: 0.8)
  - `:max_tokens` - Maximum tokens to generate (default: 4096)
  - `:system` - System prompt
  - `:stream` - Enable streaming (default: false)

  ## Examples

      {:ok, response} = Zixir.Ollama.generate("Hello!")

      {:ok, response} = Zixir.Ollama.generate("Explain Elixir",
        model: "llama3.1",
        temperature: 0.7,
        max_tokens: 500
      )

  """
  @spec generate(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate(prompt, opts \\ []) when is_binary(prompt) do
    body = build_generate_body(prompt, opts)

    case request(:post, "/api/generate", body, opts) do
      {:ok, response} ->
        {:ok, %{
          text: response["response"],
          model: body["model"],
          total_duration: response["total_duration"],
          load_duration: response["load_duration"],
          prompt_eval_count: response["prompt_eval_count"],
          eval_count: response["eval_count"]
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stream generated text token by token.

  Returns a stream that emits tokens as they are generated.
  """
  @spec stream(String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(prompt, opts \\ []) when is_binary(prompt) do
    body = build_generate_body(prompt, Keyword.put(opts, :stream, true))

    case stream_request("/api/generate", body, opts) do
      {:ok, stream} ->
        token_stream = parse_stream_tokens(stream)
        {:ok, token_stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate embeddings for text.

  Used for vector storage and similarity search.

  ## Options

  - `:model` - Embedding model (default: nomic-embed-text)
  - `:truncate` - Truncate text if too long (default: true)

  ## Examples

      {:ok, embedding} = Zixir.Ollama.embed("Hello world")
      {:ok, embedding} = Zixir.Ollama.embed("Document text", model: "mxbai-embed-large")

  """
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) when is_binary(text) do
    body = %{
      model: Keyword.get(opts, :model, "nomic-embed-text"),
      text: text,
      truncate: Keyword.get(opts, :truncate, true)
    }

    case request(:post, "/api/embeddings", body, opts) do
      {:ok, %{"embedding" => embedding}} ->
        {:ok, embedding}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a specific model is available.
  """
  @spec model_available?(String.t(), keyword()) :: boolean()
  def model_available?(model_name, opts \\ []) do
    case list_models(opts) do
      {:ok, models} ->
        Enum.any?(models, fn m -> String.starts_with?(m.name, model_name) end)

      _ ->
        false
    end
  end

  @doc """
  Get configuration from cache or defaults.
  """
  @spec get_config() :: map()
  def get_config do
    case Cache.get("#{@config_prefix}:config") do
      {:ok, config} when is_map(config) ->
        config

      _ ->
        %{
          host: @default_host,
          port: @default_port,
          model: "llama3.1",
          embedding_model: "nomic-embed-text"
        }
    end
  end

  @doc """
  Save configuration to cache.
  """
  @spec save_config(map()) :: :ok
  def save_config(config) do
    Cache.put("#{@config_prefix}:config", config, persistent: true)
  end

  # ========== Private Functions ==========

  defp build_generate_body(prompt, opts) do
    model = Keyword.get(opts, :model, "llama3.1")
    temperature = Keyword.get(opts, :temperature, 0.8)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    stream = Keyword.get(opts, :stream, false)

    body = %{
      model: model,
      prompt: prompt,
      stream: stream,
      options: %{
        temperature: temperature,
        num_predict: max_tokens
      }
    }

    if system = Keyword.get(opts, :system) do
      Map.put(body, :system, system)
    else
      body
    end
  end

  defp request(method, path, body, opts) do
    config = get_config()
    host = Keyword.get(opts, :host, config[:host] || @default_host)
    port = Keyword.get(opts, :port, config[:port] || @default_port)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    url = "http://#{host}:#{port}#{path}"
    headers = [{"Content-Type", "application/json"}]

    body_json = Jason.encode!(body)

    case HTTPoison.request(method, url, body_json, headers, timeout: timeout, recv_timeout: timeout) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        Jason.decode(resp_body)

      {:ok, %{status_code: status, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"error" => error}} -> {:error, "#{status}: #{error}"}
          {:ok, data} -> {:error, "#{status}: #{inspect(data)}"}
          _ -> {:error, "HTTP #{status}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stream_request(path, body, opts) do
    config = get_config()
    host = Keyword.get(opts, :host, config[:host] || @default_host)
    port = Keyword.get(opts, :port, config[:port] || @default_port)

    url = "http://#{host}:#{port}#{path}"
    headers = [{"Content-Type", "application/json"}]
    body_json = Jason.encode!(body)

    case HTTPoison.post!(url, body_json, headers, stream_to: self()) do
      %HTTPoison.AsyncResponse{id: stream_id} ->
        {:ok, stream_id}

      error ->
        {:error, error}
    end
  end

  defp parse_stream_tokens(stream_id) do
    stream =
      Stream.repeatedly(fn ->
        receive do
          %HTTPoison.AsyncChunk{id: ^stream_id, chunk: chunk} ->
            chunk

          %HTTPoison.AsyncEnd{id: ^stream_id} ->
            nil

          _ ->
            nil
        after
          @default_timeout ->
            nil
        end
      end)

    stream
    |> Stream.map(&String.split(&1, "\n"))
    |> Stream.flat_map(& &1)
    |> Stream.filter(&String.starts_with?(&1, "data: "))
    |> Stream.map(&String.slice(&1, 6..-1//1))
    |> Stream.filter(&(&1 != "[DONE]"))
    |> Stream.map(fn data ->
      case Jason.decode(data) do
        {:ok, %{"response" => token}} -> token
        _ -> nil
      end
    end)
    |> Stream.reject(&is_nil/1)
  end
end
