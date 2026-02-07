defmodule Zixir.VectorDB.Backend do
  @moduledoc """
  Behaviour for vector database backends.

  Zixir supports two types of backends:

  1. **Native (Memory)** - Fast, uses Zig NIFs for HNSW indexing
  2. **Python Delegation** - Chroma, Pinecone, Weaviate, Qdrant, Milvia via Python

  ## For Native Backends

      defmodule Zixir.VectorDB.MyBackend do
        @behaviour Zixir.VectorDB.Backend

        @impl true
        def init(config) do
          {:ok, state}
        end

        # ... implement other callbacks
      end

  ## For Python Backends

  Use the Python bridge instead - see `Zixir.VectorDB.BackendBehaviour`.

  """
  
  @typedoc "Backend state (implementation-specific)"
  @type state :: any()
  
  @doc """
  Initialize the backend with configuration.
  
  Returns `{:ok, state}` on success or `{:error, reason}` on failure.
  """
  @callback init(keyword()) :: {:ok, state()} | {:error, term()}
  
  @doc """
  Insert a single vector.
  """
  @callback insert(state(), String.t(), [float()], map()) :: {:ok, state()} | {:error, term()}
  
  @doc """
  Insert multiple vectors in batch.
  """
  @callback insert_batch(state(), [map()]) :: {:ok, state()} | {:error, term()}
  
  @doc """
  Search for similar vectors.
  
  Returns list of search results sorted by score (highest first).
  """
  @callback search(state(), [float()], keyword()) :: [Zixir.VectorDB.search_result()] | {:error, term()}
  
  @doc """
  Delete a vector by ID.
  """
  @callback delete(state(), String.t()) :: {:ok, state()} | {:error, term()}
  
  @doc """
  Get a vector by ID.
  
  Returns `{:ok, %{vector: [...], metadata: %{}}}` or `{:error, :not_found}`.
  """
  @callback get(state(), String.t()) :: {:ok, map()} | {:error, term()}
  
  @doc """
  Update metadata for a vector.
  """
  @callback update_metadata(state(), String.t(), map()) :: :ok | {:error, term()}
  
  @doc """
  Get backend statistics.
  """
  @callback stats(state()) :: map()
  
  @doc """
  Save state to disk (optional, may be no-op).
  """
  @callback save(state(), String.t()) :: :ok | {:error, term()}
  
  @doc """
  Load state from disk.
  """
  @callback load(String.t(), keyword()) :: {:ok, state()} | {:error, term()}
  
  @doc """
  Close the backend and free resources.
  """
  @callback close(state()) :: :ok
  
  @doc """
  Return the backend type atom (e.g., `:memory`, `:pinecone`).
  """
  @callback backend_type() :: atom()
end