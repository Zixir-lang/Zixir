defmodule Zixir.VectorDB.BackendBehaviour do
  @moduledoc """
  Backend dispatcher - routes operations to appropriate backend.

  - :memory - Uses native Elixir implementation (Zig NIFs for HNSW)
  - Other backends - Delegates to Python bridge

  """

  require Logger

  @python_backends [:chroma, :pinecone, :weaviate, :qdrant, :milvus, :pgvector, :redis, :azure]

  @doc """
  Initialize a backend with configuration.
  """
  @spec init(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def init(:memory = backend, config) do
    config = Keyword.put(config, :name, config[:name] || "memory_db")
    with {:ok, state} <- Zixir.VectorDB.Memory.init(config) do
      {:ok, Map.put(state, :backend, backend)}
    end
  end

  def init(backend, config) when backend in @python_backends do
    python_bridge_call(:init, [backend, config])
  end

  def init(other, _config) do
    {:error, "Unknown backend: #{inspect(other)}"}
  end

  @doc """
  Add a document.
  """
  @spec add(map(), String.t(), [float()], map()) :: {:ok, map()} | {:error, term()}
  def add(%{backend: :memory} = state, id, embedding, metadata) do
    Zixir.VectorDB.Memory.insert(state, id, embedding, metadata)
  end

  def add(state, id, embedding, metadata) do
    python_bridge_call(:add, [state, id, embedding, metadata])
  end

  @doc """
  Add multiple documents.
  """
  @spec add_batch(map(), [map()]) :: {:ok, map()} | {:error, term()}
  def add_batch(%{backend: :memory} = state, documents) do
    Zixir.VectorDB.Memory.insert_batch(state, documents)
  end

  def add_batch(state, documents) do
    python_bridge_call(:add_batch, [state, documents])
  end

  @doc """
  Search for similar documents.
  """
  @spec search(map(), [float()], non_neg_integer(), map() | nil, boolean()) :: {:ok, [map()]} | {:error, term()}
  def search(%{backend: :memory} = state, query, top_k, _filter, _include_embeddings) do
    Zixir.VectorDB.Memory.search(state, query, top_k: top_k)
  end

  def search(state, query, top_k, filter, include_embeddings) do
    python_bridge_call(:search, [state, query, top_k, filter, include_embeddings])
  end

  @doc """
  Get a document by ID.
  """
  @spec get(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(%{backend: :memory} = state, id) do
    Zixir.VectorDB.Memory.get(state, id)
  end

  def get(state, id) do
    python_bridge_call(:get, [state, id])
  end

  @doc """
  Delete a document.
  """
  @spec delete(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def delete(%{backend: :memory} = state, id) do
    Zixir.VectorDB.Memory.delete(state, id)
  end

  def delete(state, id) do
    python_bridge_call(:delete, [state, id])
  end

  @doc """
  Update metadata.
  """
  @spec update_metadata(map(), String.t(), map()) :: :ok | {:error, term()}
  def update_metadata(%{backend: :memory} = state, id, metadata) do
    Zixir.VectorDB.Memory.update_metadata(state, id, metadata)
  end

  def update_metadata(state, id, metadata) do
    python_bridge_call(:update_metadata, [state, id, metadata])
  end

  @doc """
  Get document count.
  """
  @spec count(map()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(%{backend: :memory} = state) do
    stats = Zixir.VectorDB.Memory.stats(state)
    {:ok, stats[:count]}
  end

  def count(state) do
    python_bridge_call(:count, [state])
  end

  @doc """
  Get statistics.
  """
  @spec stats(map()) :: {:ok, map()} | {:error, term()}
  def stats(%{backend: :memory} = state) do
    stats = Zixir.VectorDB.Memory.stats(state)
    {:ok, Map.merge(%{backend: :memory}, stats)}
  end

  def stats(state) do
    python_bridge_call(:stats, [state])
  end

  @doc """
  Get health status including circuit breaker and pool stats.
  """
  @spec health(map()) :: {:ok, map()} | {:error, term()}
  def health(%{backend: :memory}) do
    {:ok, %{
      circuit_breaker: %{state: "closed", failure_count: 0},
      pool: %{healthy: true, available_connections: :infinity, avg_latency_ms: 0.0},
      cache: %{enabled: false}
    }}
  end

  def health(state) do
    python_bridge_call(:health, [state])
  end

  @doc """
  Get request metrics.
  """
  @spec metrics(map()) :: {:ok, map()} | {:error, term()}
  def metrics(%{backend: :memory}) do
    {:ok, %{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      avg_latency_ms: 0.0,
      success_rate: 1.0
    }}
  end

  def metrics(state) do
    python_bridge_call(:metrics, [state])
  end

  @doc """
  Get cache statistics.
  """
  @spec cache_stats(map()) :: {:ok, map()} | {:error, term()}
  def cache_stats(%{backend: :memory}) do
    {:ok, %{enabled: false}}
  end

  def cache_stats(state) do
    python_bridge_call(:cache_stats, [state])
  end

  @doc """
  Clear the query cache.
  """
  @spec clear_cache(map()) :: :ok | {:error, term()}
  def clear_cache(%{backend: :memory}), do: :ok

  def clear_cache(state) do
    case python_bridge_call(:clear_cache, [state]) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, _} -> {:error, "Failed to clear cache"}
    end
  end

  @doc """
  Get circuit breaker state.
  """
  @spec circuit_breaker(map()) :: {:ok, atom()} | {:error, term()}
  def circuit_breaker(%{backend: :memory}) do
    {:ok, :closed}
  end

  def circuit_breaker(state) do
    case python_bridge_call(:circuit_breaker, [state]) do
      {:ok, state_data} -> {:ok, String.to_atom(state_data)}
      _ -> {:ok, :unknown}
    end
  end

  @doc """
  Close and cleanup.
  """
  @spec close(map()) :: :ok
  def close(%{backend: :memory} = state) do
    Zixir.VectorDB.Memory.close(state)
    :ok
  end

  def close(state) do
    python_bridge_call(:close, [state])
  end

  @doc """
  Check backend availability.
  """
  @spec available_backends() :: map()
  def available_backends do
    python_backends = python_bridge_call(:available_backends, [])

    %{
      memory: true,
      chroma: python_backends[:chroma] || false,
      pinecone: python_backends[:pinecone] || false,
      weaviate: python_backends[:weaviate] || false,
      qdrant: python_backends[:qdrant] || false,
      milvus: python_backends[:milvus] || false
    }
  end

  @doc """
  Dispatch operation to appropriate backend.
  """
  @spec call(atom(), map(), atom(), list()) :: {:ok, any()} | {:error, term()}
  def call(:memory, state, :init, [config]), do: init(:memory, config)
  def call(:memory, state, :add, [id, emb, meta]), do: add(state, id, emb, meta)
  def call(:memory, state, :add_batch, [docs]), do: add_batch(state, docs)
  def call(:memory, state, :search, [query, top_k, filter, emb]), do: search(state, query, top_k, filter, emb)
  def call(:memory, state, :get, [id]), do: get(state, id)
  def call(:memory, state, :delete, [id]), do: delete(state, id)
  def call(:memory, state, :update_metadata, [id, meta]), do: update_metadata(state, id, meta)
  def call(:memory, state, :count, []), do: count(state)
  def call(:memory, state, :stats, []), do: stats(state)
  def call(:memory, state, :health, []), do: health(state)
  def call(:memory, state, :metrics, []), do: metrics(state)
  def call(:memory, state, :cache_stats, []), do: cache_stats(state)
  def call(:memory, state, :clear_cache, []), do: clear_cache(state)
  def call(:memory, state, :circuit_breaker, []), do: circuit_breaker(state)
  def call(:memory, state, :close, []), do: close(state)

  def call(backend, state, op, args) when backend in @python_backends do
    apply(__MODULE__, op, [state | args])
  end

  # Private functions

  defp python_bridge_call(operation, args) do
    try do
      result = Zixir.Python.call("vector_db_bridge", "bridge_#{operation}", args)
      process_result(operation, result)
    rescue
      e ->
        Logger.error("VectorDB Python bridge error: #{inspect(e)}")
        {:error, "VectorDB operation failed: #{operation}"}
    end
  end

  defp process_result(:init, %{"status" => "ok", "state" => state}), do: {:ok, Map.put(state, :backend, :python)}
  defp process_result(:add, %{"status" => "ok", "state" => state}), do: {:ok, state}
  defp process_result(:add_batch, %{"status" => "ok", "state" => state}), do: {:ok, state}
  defp process_result(:search, %{"status" => "ok", "results" => results}), do: {:ok, parse_search_results(results)}
  defp process_result(:get, %{"status" => "ok", "document" => doc}), do: {:ok, parse_document(doc)}
  defp process_result(:delete, %{"status" => "ok", "state" => state}), do: {:ok, state}
  defp process_result(:update_metadata, %{"status" => "ok"}), do: :ok
  defp process_result(:count, %{"status" => "ok", "count" => n}), do: {:ok, n}
  defp process_result(:stats, %{"status" => "ok", "stats" => stats}), do: {:ok, stats}
  defp process_result(:health, %{"status" => "ok", "health" => health}), do: {:ok, health}
  defp process_result(:metrics, %{"status" => "ok", "metrics" => metrics}), do: {:ok, metrics}
  defp process_result(:cache_stats, %{"status" => "ok", "stats" => stats}), do: {:ok, stats}
  defp process_result(:clear_cache, %{"status" => "ok"}), do: :ok
  defp process_result(:circuit_breaker, %{"status" => "ok", "state" => state}), do: {:ok, state}
  defp process_result(:close, %{"status" => "ok"}), do: :ok
  defp process_result(:available_backends, %{"status" => "ok", "backends" => backends}), do: backends
  defp process_result(_, %{"status" => "error", "message" => msg}), do: {:error, msg}
  defp process_result(_, result), do: {:ok, result}

  defp parse_search_results(results) when is_list(results) do
    Enum.map(results, fn r ->
      %{
        id: r["id"] || r["doc_id"] || "unknown",
        score: r["score"] || r["similarity"] || 0.0,
        embedding: r["embedding"] || r["vector"],
        metadata: r["metadata"] || r["payload"] || %{}
      }
    end)
  end

  defp parse_search_results(_), do: []

  defp parse_document(%{"id" => id, "embedding" => emb, "metadata" => meta}),
    do: %{id: id, embedding: emb, metadata: meta}
  defp parse_document(doc) when is_map(doc), do: doc
  defp parse_document(_), do: %{embedding: nil, metadata: %{}}
end
