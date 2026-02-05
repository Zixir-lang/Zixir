defmodule Zixir.VectorDB do
  @moduledoc """
  Vector database operations for AI-native programming.

  Delegates to Python backends for actual database operations.
  Supports nine backends: Memory, Chroma, Pinecone, Weaviate, Qdrant, Milvus,
  pgvector (PostgreSQL), Redis, and Azure. Cloud backends use connection pooling,
  exponential backoff, circuit breaker, query caching, health checks, and request metrics.

  ## Architecture

      Zixir (orchestration)
         ↓
      Python bridge (unified interface)
         ↓
      Backends: Memory | Chroma | Pinecone | Weaviate | Qdrant | Milvus | pgvector | Redis | Azure

  ## Usage

      # Create database (delegates to Python)
      db = Zixir.VectorDB.create("my_db",
        backend: :chroma,
        collection: "documents",
        dimensions: 1536
      )

      # Insert vectors
      Zixir.VectorDB.add(db, "doc1", embedding, %{text: "Hello"})

      # Search
      results = Zixir.VectorDB.search(db, query_embedding, top_k: 5)

  ## Backends

  | Backend   | Type    | Best For                          |
  |-----------|--------|------------------------------------|
  | :memory   | Native | Prototyping (< 100K vectors)       |
  | :chroma   | Python | Simple local development          |
  | :pinecone | Python | Production cloud                   |
  | :weaviate | Python | Self-hosted, GraphQL               |
  | :qdrant   | Python | High-performance                   |
  | :milvus   | Python | Enterprise distributed             |
  | :pgvector | Python | PostgreSQL users, ACID compliance |
  | :redis    | Python | Real-time apps, sub-ms latency    |
  | :azure    | Python | Microsoft ecosystems               |

  Setup and `pip install` instructions: see `docs/VECTORDB_BACKENDS.md`.
  """

  require Logger

  alias Zixir.VectorDB.BackendBehaviour

  @typedoc "Vector database handle"
  @type t :: %__MODULE__{
    name: String.t(),
    backend: atom(),
    config: keyword(),
    dimensions: pos_integer(),
    metric: atom()
  }

  defstruct [:name, :backend, :config, :dimensions, :metric]

  @doc """
  Get the backend module for a given backend type.
  """
  @spec backend_module(atom()) :: module() | nil
  def backend_module(:memory), do: Zixir.VectorDB.Memory
  def backend_module(_), do: nil

  @typedoc "Vector as list of floats"
  @type vector :: [float()]

  @typedoc "Search result"
  @type search_result :: %{
    id: String.t(),
    score: float(),
    embedding: vector() | nil,
    metadata: map()
  }

  @typedoc "Distance metric"
  @type metric :: :cosine | :euclidean | :dot

  @doc """
  Create a new vector database.

  Delegates to Python bridge which handles backend-specific initialization.

  ## Options

  - `:backend` - Backend: `:memory`, `:chroma`, `:pinecone`, `:weaviate`, `:qdrant`, `:milvus`, `:pgvector`, `:redis`, `:azure`
  - `:dimensions` - Vector dimensions (required)
  - `:metric` - Distance metric: `:cosine`, `:euclidean`, `:dot` (default: `:cosine`)
  - Backend-specific options passed through to Python

  ## Examples

      # Memory (fastest for prototyping)
      db = Zixir.VectorDB.create("test", dimensions: 1536)

      # Chroma (local persistence)
      db = Zixir.VectorDB.create("local",
        backend: :chroma,
        collection: "documents",
        dimensions: 1536,
        host: "localhost:8000"
      )

      # Pinecone (production cloud)
      db = Zixir.VectorDB.create("prod",
        backend: :pinecone,
        api_key: System.get_env("PINECONE_API_KEY"),
        index_name: "my-index",
        dimensions: 1536
      )

      # Weaviate (self-hosted)
      db = Zixir.VectorDB.create("selfhosted",
        backend: :weaviate,
        host: "http://localhost:8080",
        class_name: "Documents"
      )

  """
  @spec create(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(name, opts \\ []) do
    backend = opts[:backend] || :memory
    dimensions = opts[:dimensions]

    with {:ok, _} <- validate_backend(backend),
         {:ok, _} <- validate_dimensions(dimensions) do
      config = Keyword.merge(opts, name: name)

      case init_python_backend(backend, config) do
        {:ok, backend_state} ->
          db = %__MODULE__{
            name: name,
            backend: backend,
            config: Keyword.put(config, :state, backend_state),
            dimensions: dimensions,
            metric: opts[:metric] || :cosine
          }
          Logger.info("VectorDB created: #{name} (#{backend})")
          {:ok, db}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Add a single document with embedding.
  """
  @spec add(t(), String.t(), vector(), map()) :: {:ok, t()} | {:error, term()}
  def add(%__MODULE__{backend: backend, config: config} = db, id, embedding, metadata \\ %{}) do
    validate_vector!(db, embedding)

    case BackendBehaviour.call(backend, config[:state], :add, [id, embedding, metadata]) do
      {:ok, new_state} ->
        {:ok, %{db | config: Keyword.put(config, :state, new_state)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Add multiple documents efficiently.

  ## Example

      docs = [
        %{id: "doc1", embedding: [...], metadata: %{text: "A"}},
        %{id: "doc2", embedding: [...], metadata: %{text: "B"}}
      ]
      Zixir.VectorDB.add_batch(db, docs)
  """
  @spec add_batch(t(), [map()]) :: {:ok, t()} | {:error, term()}
  def add_batch(%__MODULE__{backend: backend, config: config} = db, documents) do
    with {:ok, new_state} <- BackendBehaviour.call(backend, config[:state], :add_batch, [documents]) do
      {:ok, %{db | config: Keyword.put(config, :state, new_state)}}
    end
  end

  @doc """
  Search for similar documents.

  ## Options

  - `:top_k` - Number of results (default: 10)
  - `:filter` - Metadata filter (backend-dependent)
  - `:include_embeddings` - Return embeddings in results (default: false)

  ## Example

      results = Zixir.VectorDB.search(db, query,
        top_k: 5,
        filter: %{category: "tech"},
        include_embeddings: false
      )
  """
  @spec search(t(), vector(), keyword()) :: [search_result()] | {:error, term()}
  def search(%__MODULE__{backend: backend, config: config} = db, query, opts \\ []) do
    validate_vector!(db, query)

    top_k = opts[:top_k] || 10
    include_embeddings = opts[:include_embeddings] || false
    filter = opts[:filter]

    case BackendBehaviour.call(backend, config[:state], :search, [query, top_k, filter, include_embeddings]) do
      {:ok, results} -> results
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get a document by ID.
  """
  @spec get(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(%__MODULE__{backend: backend, config: config}, id) do
    BackendBehaviour.call(backend, config[:state], :get, [id])
  end

  @doc """
  Delete a document by ID.
  """
  @spec delete(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def delete(%__MODULE__{backend: backend, config: config} = db, id) do
    case BackendBehaviour.call(backend, config[:state], :delete, [id]) do
      {:ok, new_state} ->
        {:ok, %{db | config: Keyword.put(config, :state, new_state)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Update document metadata.
  """
  @spec update_metadata(t(), String.t(), map()) :: :ok | {:error, term()}
  def update_metadata(%__MODULE__{backend: backend, config: config}, id, metadata) do
    BackendBehaviour.call(backend, config[:state], :update_metadata, [id, metadata])
  end

  @doc """
  Get document count.
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{backend: backend, config: config}) do
    case BackendBehaviour.call(backend, config[:state], :count, []) do
      {:ok, n} -> n
      _ -> 0
    end
  end

  @doc """
  Get database statistics.
  """
  @spec stats(t()) :: map()
  def stats(%__MODULE__{backend: backend, config: config} = db) do
    case BackendBehaviour.call(backend, config[:state], :stats, []) do
      {:ok, backend_stats} ->
        Map.merge(backend_stats, %{
          dimensions: db.dimensions,
          metric: db.metric,
          name: db.name
        })

      _ ->
        %{
          backend: backend,
          count: 0,
          dimensions: db.dimensions,
          metric: db.metric,
          name: db.name
        }
    end
  end

  @doc """
  Close the database and free resources.
  """
  @spec close(t()) :: :ok
  def close(%__MODULE__{backend: backend, config: config}) do
    BackendBehaviour.call(backend, config[:state], :close, [])
    :ok
  end

  @doc """
  Save the database to disk.
  """
  @spec save(t(), String.t()) :: :ok | {:error, term()}
  def save(%__MODULE__{backend: :memory} = db, path) do
    Zixir.VectorDB.Memory.save(db.config[:state], path)
  end

  def save(_db, _path) do
    {:error, "Save only supported for :memory backend"}
  end

  @doc """
  Load a database from disk.
  """
  @spec load(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(path, opts \\ []) do
    with {:ok, state} <- Zixir.VectorDB.Memory.load(path, opts) do
      db = %__MODULE__{
        name: opts[:name] || Path.basename(path),
        backend: :memory,
        config: [state: state],
        dimensions: state.dimensions,
        metric: state.metric || :cosine
      }
      {:ok, db}
    end
  end

  @doc """
  Check which backends are available.
  """
  @spec available_backends() :: map()
  def available_backends do
    BackendBehaviour.available_backends()
  end

  @doc """
  List supported backends.
  """
  @spec supported_backends() :: [atom()]
  def supported_backends do
    [:memory, :chroma, :pinecone, :weaviate, :qdrant, :milvus, :pgvector, :redis, :azure]
  end

  @doc """
  Alias for add/4 - insert a single document with embedding.
  """
  @spec insert(t(), String.t(), vector(), map()) :: {:ok, t()} | {:error, term()}
  def insert(db, id, embedding, metadata \\ %{}), do: add(db, id, embedding, metadata)

  @doc """
  Alias for insert_batch/2 - insert multiple documents.
  """
  @spec insert_batch(t(), [map()]) :: {:ok, t()} | {:error, term()}
  def insert_batch(db, documents), do: add_batch(db, documents)

  @doc """
  Calculate cosine similarity between two vectors.
  """
  @spec cosine_similarity(vector(), vector()) :: float()
  def cosine_similarity(a, b), do: Zixir.VectorDB.Math.cosine_similarity(a, b)

  @doc """
  Calculate Euclidean distance between two vectors.
  """
  @spec euclidean_distance(vector(), vector()) :: float()
  def euclidean_distance(a, b), do: Zixir.VectorDB.Math.euclidean_distance(a, b)

  @doc """
  Calculate dot product of two vectors.
  """
  @spec dot_product(vector(), vector()) :: float()
  def dot_product(a, b), do: Zixir.VectorDB.Math.dot_product(a, b)

  @doc """
  Normalize a vector to unit length.
  """
  @spec normalize(vector()) :: vector()
  def normalize(vector), do: Zixir.VectorDB.Math.normalize(vector)

  @doc """
  Get health status of the database connection.

  Returns circuit breaker state, pool stats, and cache stats.

  ## Example

      health = Zixir.VectorDB.health(db)
      # => %{
      #   circuit_breaker: %{state: "closed", failure_count: 0},
      #   pool: %{healthy: true, avg_latency_ms: 45.2},
      #   cache: %{size: 150, hit_rate: 0.85}
      # }

  """
  @spec health(t()) :: map()
  def health(%__MODULE__{backend: :memory, config: config}) do
    %{
      circuit_breaker: %{state: :closed, failure_count: 0},
      pool: %{healthy: true, available_connections: :infinity, avg_latency_ms: 0.0},
      cache: %{enabled: false}
    }
  end

  def health(%__MODULE__{backend: backend, config: config}) do
    case BackendBehaviour.call(backend, config[:state], :health, []) do
      {:ok, health_data} -> health_data
      _ -> %{error: "Health check failed"}
    end
  end

  @doc """
  Get request metrics for the database.

  Returns request counts, latency, and success rates.

  ## Example

      metrics = Zixir.VectorDB.metrics(db)
      # => %{
      #   total_requests: 1000,
      #   successful_requests: 985,
      #   failed_requests: 15,
      #   avg_latency_ms: 45.2,
      #   success_rate: 0.985
      # }

  """
  @spec metrics(t()) :: map()
  def metrics(%__MODULE__{backend: :memory}) do
    %{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      avg_latency_ms: 0.0,
      success_rate: 1.0,
      backend: :memory
    }
  end

  def metrics(%__MODULE__{backend: backend, config: config}) do
    case BackendBehaviour.call(backend, config[:state], :metrics, []) do
      {:ok, metrics_data} -> Map.put(metrics_data, :backend, backend)
      _ -> %{error: "Metrics unavailable"}
    end
  end

  @doc """
  Get cache statistics for the database.

  Returns cache size, hit rate, and hit/miss counts.

  ## Example

      cache_stats = Zixir.VectorDB.cache_stats(db)
      # => %{
      #   size: 150,
      #   max_size: 1000,
      #   hits: 850,
      #   misses: 150,
      #   hit_rate: 0.85
      # }

  """
  @spec cache_stats(t()) :: map()
  def cache_stats(%__MODULE__{backend: :memory}) do
    %{enabled: false}
  end

  def cache_stats(%__MODULE__{backend: backend, config: config}) do
    case BackendBehaviour.call(backend, config[:state], :cache_stats, []) do
      {:ok, stats} -> stats
      _ -> %{enabled: false}
    end
  end

  @doc """
  Clear the query cache for the database.

  Useful when data changes and cached results are stale.

  ## Example

      :ok = Zixir.VectorDB.clear_cache(db)

  """
  @spec clear_cache(t()) :: :ok | {:error, term()}
  def clear_cache(%__MODULE__{backend: :memory}), do: :ok

  def clear_cache(%__MODULE__{backend: backend, config: config}) do
    case BackendBehaviour.call(backend, config[:state], :clear_cache, []) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, _} -> {:error, "Failed to clear cache"}
    end
  end

  @doc """
  Get the circuit breaker state.

  Returns whether requests are allowed or blocked.

  ## States

  - `:closed` - Normal operation, requests allowed
  - `:open` - Failing, requests blocked
  - `:half_open` - Testing recovery, requests allowed

  ## Example

      Zixir.VectorDB.circuit_breaker(db)
      # => :closed

  """
  @spec circuit_breaker(t()) :: atom()
  def circuit_breaker(%__MODULE__{backend: :memory}), do: :closed

  def circuit_breaker(%__MODULE__{backend: backend, config: config}) do
    case BackendBehaviour.call(backend, config[:state], :circuit_breaker, []) do
      {:ok, state} -> state
      _ -> :unknown
    end
  end

  @doc """
  Check if the database connection is healthy.

  Returns true if circuit breaker is closed and pool is healthy.
  """
  @spec healthy?(t()) :: boolean()
  def healthy?(db) do
    health(db) |> Map.get(:circuit_breaker, %{}) |> Map.get(:state) == :closed
  end

  # Private functions

  defp validate_backend(backend) when backend in [:memory, :chroma, :pinecone, :weaviate, :qdrant, :milvus, :pgvector, :redis, :azure],
    do: {:ok, backend}

  defp validate_backend(other),
    do: {:error, "Unsupported backend: #{inspect(other)}. Supported: memory, chroma, pinecone, weaviate, qdrant, milvus, pgvector, redis, azure"}

  defp validate_dimensions(nil), do: {:error, "dimensions is required"}
  defp validate_dimensions(d) when not is_integer(d), do: {:error, "dimensions must be an integer"}
  defp validate_dimensions(d) when d <= 0, do: {:error, "dimensions must be positive"}
  defp validate_dimensions(d) when is_integer(d), do: {:ok, d}

  defp init_python_backend(backend, config) do
    BackendBehaviour.init(backend, config)
  end

  defp validate_vector!(%__MODULE__{dimensions: dims}, vector) do
    unless is_list(vector) and length(vector) == dims do
      raise ArgumentError, "Vector must have #{dims} dimensions, got #{length(vector)}"
    end

    unless Enum.all?(vector, &is_number/1) do
      raise ArgumentError, "Vector must contain only numbers"
    end
  end
end
