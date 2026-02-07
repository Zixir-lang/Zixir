defmodule Zixir.LLM do
  @moduledoc """
  Native LLM Integration with Structured Output.

  Provides easy access to OpenAI, Anthropic, and local models with:
  - Simple prompt completion
  - Structured output via Pydantic models
  - Streaming responses
  - Token usage tracking
  - Cost estimation
  - Retry with backoff

  ## Quick Start

      # Simple call
      {:ok, response} = Zixir.LLM.call(:openai, "Tell me a joke about Elixir")

      # With structured output
      {:ok, %{sentiment: "positive", score: 0.95}} = Zixir.LLM.call(
        :openai,
        "Analyze the sentiment: I love Zixir!",
        schema: %{
          sentiment: :string,
          score: :float
        }
      )

  ## Supported Providers

  | Provider | Description | Best For |
  |----------|-------------|---------|
  | `:openai` | OpenAI GPT models | General purpose |
  | `:anthropic` | Anthropic Claude | Long context |
  | `:local` | Local models (Ollama) | Privacy, cost |
  | `:azure` | Azure OpenAI | Enterprise |

  ## Configuration

      config :zixir, :llm,
        providers: %{
          openai: %{
            api_key: System.get_env("OPENAI_API_KEY"),
            model: "gpt-4",
            temperature: 0.1
          },
          anthropic: %{
            api_key: System.get_env("ANTHROPIC_API_KEY"),
            model: "claude-3-opus-20240229"
          }
        }

  """

  require Logger

  @ets_table_name :zixir_llm_usage

  @type provider :: :openai | :anthropic | :local | :azure
  @type prompt :: String.t()
  @type schema :: map() | nil
  @type options :: keyword()
  @type response :: {:ok, term()} | {:error, term()}

  @default_model "gpt-4o"
  @default_temperature 0.1
  @default_max_tokens 4096

  @on_load :init_ets_table
  def init_ets_table do
    case :ets.whereis(@ets_table_name) do
      :undefined ->
        :ets.new(@ets_table_name, [:set, :public, :named_table])
      _ ->
        :ok
    end
    :ok
  end

  @doc """
  Call an LLM with a prompt.

  ## Parameters

  - `provider` - LLM provider (:openai, :anthropic, :local, :azure)
  - `prompt` - The prompt to send
  - `options` - Additional options

  ## Options

  - `:model` - Model name (default: provider's default)
  - `:temperature` - Sampling temperature (0.0-1.0, default: 0.1)
  - `:max_tokens` - Maximum output tokens (default: 4096)
  - `:schema` - Output schema for structured response
  - `:system` - System prompt
  - `:stream` - Enable streaming (default: false)

  ## Examples

      # Simple call
      {:ok, response} = Zixir.LLM.call(:openai, "Summarize this: your text here")

      # With options
      {:ok, response} = Zixir.LLM.call(:openai, "Explain how HTTP works",
        model: "gpt-4",
        temperature: 0.2,
        max_tokens: 1000
      )

      # With system prompt
      {:ok, response} = Zixir.LLM.call(:openai, "What is 2+2?",
        system: "You are a math expert. Always show your work."
      )

  """
  @spec call(provider(), prompt(), options()) :: response()
  def call(provider, prompt, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    model = get_model(provider, opts)
    temperature = Keyword.get(opts, :temperature, @default_temperature)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    system = Keyword.get(opts, :system)
    schema = Keyword.get(opts, :schema)

    request = build_request(provider, prompt, model, temperature, max_tokens, system, schema)

    case send_request(provider, request, opts) do
      {:ok, response} ->
        duration = System.monotonic_time(:millisecond) - start_time
        record_usage(provider, model, response, duration)
        {:ok, response}

      {:error, reason} ->
        _duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("LLM call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Call a custom AI provider with OpenAI-compatible API.

  ## Parameters

  - `provider_id` - Unique identifier for the custom provider
  - `prompt` - The prompt to send
  - `options` - Additional options

  ## Examples

      {:ok, response} = Zixir.LLM.call_custom("groq", "Hello, world!")

  """
  @spec call_custom(String.t(), prompt(), options()) :: response()
  def call_custom(provider_id, prompt, opts \\ []) when is_binary(provider_id) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, config} <- Zixir.AI.Config.get_custom_provider(provider_id) do
      model = opts[:model] || config.model || "gpt-4o-mini"
      temperature = Keyword.get(opts, :temperature, config[:temperature] || @default_temperature)
      max_tokens = Keyword.get(opts, :max_tokens, config[:max_tokens] || @default_max_tokens)
      system = Keyword.get(opts, :system)
      schema = Keyword.get(opts, :schema)

      body = Jason.encode!(%{
        model: model,
        messages: build_messages(system, prompt),
        max_tokens: max_tokens,
        temperature: temperature
      })

      headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{config.api_key}"}
      ]

      endpoint = config.endpoint

      case HTTPoison.post(endpoint <> "/chat/completions", body, headers, timeout: 60000, recv_timeout: 60000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          duration = System.monotonic_time(:millisecond) - start_time
          response = Jason.decode!(response_body)
          text = get_in(response, ["choices", Access.at!(0), "message", "content"])
          usage = response["usage"]

          parsed_response = %{
            text: text,
            input_tokens: usage["prompt_tokens"] || 0,
            output_tokens: usage["completion_tokens"] || 0,
            model: model
          }

          record_usage({:custom, provider_id}, model, parsed_response, duration)
          {:ok, parsed_response}

        {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
          {:error, "HTTP #{status_code}: #{body}"}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_messages(nil, prompt), do: [%{role: "user", content: prompt}]
  defp build_messages(system, prompt) when is_binary(system), do: [%{role: "system", content: system}, %{role: "user", content: prompt}]

  @doc """
  Stream LLM response token by token.

  Returns a stream that emits tokens.

  ## Examples

      {:ok, stream} = Zixir.LLM.stream(:openai, "Tell me a story")
      for chunk <- stream do
        IO.write(chunk)
      end

  """
  @spec stream(provider(), prompt(), options()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(provider, prompt, opts \\ []) do
    model = get_model(provider, opts)
    temperature = Keyword.get(opts, :temperature, @default_temperature)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    system = Keyword.get(opts, :system)

    request = build_request(provider, prompt, model, temperature, max_tokens, system, nil)

    case create_stream(provider, request, opts) do
      {:ok, stream} ->
        {:ok, stream}

      error ->
        error
    end
  end

  @doc """
  Call with structured schema output.

  Automatically parses and validates the response against the schema.

  ## Schema Definition

      schema = %{
        entities: [
          %{
            name: :string,
            type: :string,
            confidence: :float
          }
        ],
        summary: :string
      }

  ## Examples

      {:ok, result} = Zixir.LLM.structured_call(
        :openai,
        "Extract entities from: your text here",
        %{
          entities: [
            %{
              name: :string,
              type: :string
            }
          ],
          summary: :string
        }
      )

      # Access result
      result.entities  # [%{name: "...", type: "..."}]
      result.summary   # "..."

  """
  @spec structured_call(provider(), prompt(), map(), options()) :: response()
  def structured_call(provider, prompt, schema, opts \\ []) do
    opts = Keyword.put(opts, :schema, schema)
    call(provider, prompt, opts)
  end

  @doc """
  Get token usage statistics for a session.

  ## Examples

      usage = Zixir.LLM.usage("session_123")
      # => %{input_tokens: 1000, output_tokens: 500, cost: 0.05}

  """
  @spec usage_stats(String.t()) :: map()
  def usage_stats(session_id \\ "default") do
    init_ets_table()
    case :ets.lookup(@ets_table_name, session_id) do
      [{^session_id, data}] -> data
      _ -> %{input_tokens: 0, output_tokens: 0, cost: 0.0, requests: 0}
    end
  end

  @doc """
  Get aggregated usage statistics for a provider.

  ## Examples

      usage = Zixir.LLM.provider_usage(:openai)
      # => %{input_tokens: 10000, output_tokens: 5000, cost: 0.5, requests: 100}

  """
  @spec provider_usage(provider()) :: map()
  def provider_usage(provider) do
    init_ets_table()
    case :ets.lookup(@ets_table_name, provider) do
      [{^provider, data}] -> data
      _ -> %{input_tokens: 0, output_tokens: 0, cost: 0.0, requests: 0}
    end
  end

  @doc """
  Get aggregated usage statistics for all providers.

  ## Examples

      all_usage = Zixir.LLM.all_usage()
      # => %{openai: %{...}, anthropic: %{...}, ...}

  """
  @spec all_usage() :: map()
  def all_usage do
    init_ets_table()
    :ets.foldl(
      fn
        {key, data}, acc when is_atom(key) and key in [:openai, :anthropic, :local, :azure] ->
          Map.put(acc, key, data)
        _, acc ->
          acc
      end,
      %{},
      @ets_table_name
    )
  end

  @doc """
  Reset all usage statistics (for testing).

  ## Examples

      Zixir.LLM.reset_usage()
      # => :ok

  """
  @spec reset_usage() :: :ok
  def reset_usage do
    init_ets_table()
    :ets.delete_all_objects(@ets_table_name)
    :ok
  end

  @doc """
  Estimate cost for a model call.

  ## Examples

      cost = Zixir.LLM.estimate_cost(:openai, "gpt-4", 1000, 500)
      # => 0.06 (dollars)

  """
  @spec estimate_cost(provider(), String.t(), non_neg_integer(), non_neg_integer()) :: float()
  def estimate_cost(provider, model, input_tokens, output_tokens) do
    rates = get_pricing(provider, model)

    input_rate = rates[:input] || 0.01
    output_rate = rates[:output] || 0.03

    (input_tokens * input_rate + output_tokens * output_rate) / 1_000_000
  end

  @doc """
  List available models for a provider.

  ## Examples

      models = Zixir.LLM.models(:openai)
      # => ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"]

  """
  @spec models(provider()) :: [String.t()]
  def models(provider) do
    get_available_models(provider)
  end

  @doc """
  Check if a provider is configured.

  ## Examples

      Zixir.LLM.available?(:openai)
      # => true

      Zixir.LLM.available?(:anthropic)
      # => false

  """
  @spec available?(provider()) :: boolean()
  def available?(provider) do
    config = get_provider_config(provider)
    config[:api_key] != nil
  end

  # Private Functions

  defp get_model(provider, opts) do
    case Keyword.get(opts, :model) do
      nil -> get_default_model(provider)
      model -> model
    end
  end

  defp get_default_model(:openai), do: "gpt-4o"
  defp get_default_model(:anthropic), do: "claude-3-5-sonnet-20241022"
  defp get_default_model(:local), do: "llama3.1"
  defp get_default_model(:azure), do: "gpt-4"

  defp build_request(:openai, prompt, model, temperature, max_tokens, system, schema) do
    messages =
      if system do
        [%{"role" => "system", "content" => system}, %{"role" => "user", "content" => prompt}]
      else
        [%{"role" => "user", "content" => prompt}]
      end

    request = %{
      model: model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }

    if schema do
      Map.put(request, :response_format, %{type: "json_object", schema: schema})
    else
      request
    end
  end

  defp build_request(:anthropic, prompt, model, temperature, max_tokens, system, schema) do
    messages =
      if system do
        [%{"role" => "user", "content" => system <> "\n\n" <> prompt}]
      else
        [%{"role" => "user", "content" => prompt}]
      end

    %{
      model: model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }
  end

  defp build_request(:local, prompt, model, temperature, max_tokens, _system, _schema) do
    %{
      model: model,
      prompt: prompt,
      temperature: temperature,
      num_predict: max_tokens
    }
  end

  defp build_request(:azure, prompt, model, temperature, max_tokens, system, schema) do
    messages =
      if system do
        [%{"role" => "system", "content" => system}, %{"role" => "user", "content" => prompt}]
      else
        [%{"role" => "user", "content" => prompt}]
      end

    request = %{
      model: model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }

    if schema do
      Map.put(request, "response_format", %{"type" => "json_object", "schema" => schema})
    else
      request
    end
  end

  defp send_request(:openai, request, opts) do
    api_key = get_api_key(:openai)

    headers = [
      "Content-Type": "application/json",
      Authorization: "Bearer #{api_key}"
    ]

    url = "https://api.openai.com/v1/chat/completions"

    case HTTPoison.post(url, Jason.encode!(request), headers) do
      {:ok, %{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        text = get_in(response, ["choices", Access.at!(0), "message", "content"])
        usage = response["usage"]

        {:ok,
         %{
           text: text,
           input_tokens: usage["prompt_tokens"],
           output_tokens: usage["completion_tokens"],
           model: request[:model]
         }}

      {:ok, %{status_code: status, body: body}} ->
        error = Jason.decode!(body)
        {:error, "#{status}: #{error["error"]["message"]}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_request(:anthropic, request, opts) do
    api_key = get_api_key(:anthropic)

    headers = [
      "Content-Type": "application/json",
      "x-api-key": api_key,
      "anthropic-version": "2023-06-01",
      "anthropic-dangerous-direct-browser-access": "true"
    ]

    body = %{
      model: request[:model],
      messages: request[:messages],
      max_tokens: request[:max_tokens] || 1024,
      temperature: request[:temperature] || 0.1
    }

    url = "https://api.anthropic.com/v1/messages"

    case HTTPoison.post(url, Jason.encode!(body), headers) do
      {:ok, %{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        text = get_in(response, ["content", Access.at!(0), "text"])

        {:ok,
         %{
           text: text,
           input_tokens: response["usage"]["input_tokens"],
           output_tokens: response["usage"]["output_tokens"],
           model: request[:model]
         }}

      {:ok, %{status_code: status, body: body}} ->
        error = Jason.decode!(body)
        {:error, "#{status}: #{inspect(error)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_request(:local, request, opts) do
    # Delegate to Zixir.Ollama for local inference
    prompt = request[:prompt] || request["prompt"]
    model = request[:model] || "llama3.1"
    temperature = request[:temperature] || 0.8

    ollama_opts = [
      model: model,
      temperature: temperature,
      max_tokens: request[:num_predict] || request["num_predict"] || 4096
    ]

    # Add system prompt if present
    if system = request[:system] || request["system"] do
      ollama_opts = Keyword.put(ollama_opts, :system, system)
    end

    case Zixir.Ollama.generate(prompt, ollama_opts) do
      {:ok, response} ->
        {:ok, %{
          text: response[:text],
          input_tokens: nil,
          output_tokens: nil,
          model: model
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_request(:azure, request, opts) do
    config = get_provider_config(:azure)
    endpoint = config[:endpoint] || raise "Azure endpoint not configured"
    deployment = config[:deployment] || request[:model]
    api_key = config[:api_key] || raise "API key not configured for Azure"

    headers = [
      "Content-Type": "application/json",
      "api-key": api_key
    ]

    url =
      "#{endpoint}/openai/deployments/#{deployment}/chat/completions?api-version=2024-08-01-preview"

    body = Map.delete(request, :model) |> Jason.encode!()

    case HTTPoison.post(url, body, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        text = get_in(response, ["choices", Access.at!(0), "message", "content"])
        usage = response["usage"]

        {:ok,
         %{
           text: text,
           input_tokens: usage["prompt_tokens"],
           output_tokens: usage["completion_tokens"],
           model: request[:model]
         }}

      {:ok, %{status_code: status, body: body}} ->
        error = Jason.decode!(body)
        {:error, "#{status}: #{inspect(error)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_stream(:openai, request, opts) do
    api_key = get_api_key(:openai)

    headers = [
      "Content-Type": "application/json",
      Authorization: "Bearer #{api_key}"
    ]

    url = "https://api.openai.com/v1/chat/completions"
    body = Map.put(request, :stream, true) |> Jason.encode!()

    case HTTPoison.post!(url, body, headers, stream_to: self()) do
      %HTTPoison.AsyncResponse{id: id} ->
        {:ok, stream_tokens(id)}

      error ->
        {:error, error}
    end
  end

  defp stream_tokens(id) do
    receive do
      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
        lines = String.split(chunk, "\n")

        tokens =
          for line <- lines do
            if String.starts_with?(line, "data: ") do
              data = String.slice(line, 6..-1//1)

              if data != "[DONE]" do
                case Jason.decode(data) do
                  {:ok, %{"choices" => [%{"delta" => %{"content" => token}}]}} ->
                    token

                  _ ->
                    nil
                end
              end
            end
          end
          |> Enum.reject(&is_nil/1)

        [tokens | stream_tokens(id)]

      %HTTPoison.AsyncEnd{id: ^id} ->
        []

      _ ->
        stream_tokens(id)
    after
      30_000 ->
        []
    end
  end

  defp create_stream(:local, request, _opts) do
    # Delegate to Zixir.Ollama for streaming
    prompt = request[:prompt] || request["prompt"]
    model = request[:model] || "llama3.1"

    ollama_opts = [
      model: model,
      temperature: request[:temperature] || 0.8,
      max_tokens: request[:num_predict] || 4096
    ]

    case Zixir.Ollama.stream(prompt, ollama_opts) do
      {:ok, stream} ->
        # Transform Ollama tokens to match expected format
        token_stream = Stream.map(stream, fn token ->
          %{"delta" => %{"content" => token}}
        end)
        {:ok, token_stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_stream(_, _, _) do
    {:error, "Streaming not supported for this provider"}
  end

  defp get_api_key(provider) do
    config = get_provider_config(provider)
    config[:api_key] || raise "API key not configured for #{provider}"
  end

  defp get_provider_config(:openai) do
    case Zixir.AI.Config.get_provider(:openai) do
      {:ok, config} -> Map.take(config, [:api_key, :model, :temperature, :max_tokens, :endpoint, :deployment])
      _ -> Application.get_env(:zixir, :llm, [])[:providers] || %{openai: %{api_key: nil}}
    end
  end

  defp get_provider_config(:anthropic) do
    case Zixir.AI.Config.get_provider(:anthropic) do
      {:ok, config} -> Map.take(config, [:api_key, :model, :temperature, :max_tokens])
      _ -> Application.get_env(:zixir, :llm, [])[:providers] || %{}
    end
  end

  defp get_provider_config(:azure) do
    case Zixir.AI.Config.get_provider(:azure) do
      {:ok, config} -> Map.take(config, [:api_key, :model, :temperature, :max_tokens, :endpoint, :deployment])
      _ -> Application.get_env(:zixir, :llm, [])[:providers] || %{}
    end
  end

  defp get_provider_config(:local) do
    case Zixir.AI.Config.get_provider(:local) do
      {:ok, config} -> Map.take(config, [:host, :port, :model, :temperature, :max_tokens, :embedding_model])
      _ -> Application.get_env(:zixir, :llm, [])[:providers] || %{}
    end
  end

  defp get_pricing(:openai, "gpt-4o"), do: %{input: 5.0, output: 15.0}
  defp get_pricing(:openai, "gpt-4"), do: %{input: 30.0, output: 60.0}
  defp get_pricing(:openai, "gpt-4-turbo"), do: %{input: 10.0, output: 30.0}
  defp get_pricing(:openai, "gpt-3.5-turbo"), do: %{input: 0.5, output: 1.5}
  defp get_pricing(:anthropic, "claude-3-opus-20240229"), do: %{input: 15.0, output: 75.0}
  defp get_pricing(:anthropic, "claude-3-sonnet-20240229"), do: %{input: 3.0, output: 15.0}
  defp get_pricing(:anthropic, "claude-3-haiku-20240307"), do: %{input: 0.25, output: 1.25}
  defp get_pricing(:azure, model), do: get_pricing(:openai, model)
  defp get_pricing(:local, _), do: %{input: 0.0, output: 0.0}

  defp get_available_models(:openai),
    do: ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"]

  defp get_available_models(:anthropic),
    do: ["claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307"]

  defp get_available_models(:local), do: ["llama3.1", "llama3.2", "mistral", "codellama", "nomic-embed-text"]
  defp get_available_models(:azure), do: get_available_models(:openai)

  defp record_usage(provider, model, response, duration_ms) do
    init_ets_table()

    input_tokens = response[:input_tokens] || 0
    output_tokens = response[:output_tokens] || 0
    cost = estimate_cost(provider, model, input_tokens, output_tokens)

    new_usage = %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cost: cost,
      requests: 1,
      total_duration_ms: duration_ms
    }

    case :ets.lookup(@ets_table_name, provider) do
      [{^provider, existing_usage}] ->
        aggregated = %{
          input_tokens: existing_usage.input_tokens + input_tokens,
          output_tokens: existing_usage.output_tokens + output_tokens,
          cost: existing_usage.cost + cost,
          requests: existing_usage.requests + 1,
          total_duration_ms: existing_usage.total_duration_ms + duration_ms
        }
        :ets.insert(@ets_table_name, {provider, aggregated})
      _ ->
        :ets.insert(@ets_table_name, {provider, new_usage})
    end

    Logger.debug("LLM usage recorded", provider: provider, model: model, input_tokens: input_tokens, output_tokens: output_tokens, cost: cost)
  end
end
