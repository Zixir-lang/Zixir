defmodule Zixir.VectorDB.Memory do
  @moduledoc """
  In-memory vector database backend using HNSW indexing.
  
  Implements the Zixir.VectorDB.Backend behavior with:
  - HNSW (Hierarchical Navigable Small World) approximate nearest neighbor search
  - In-memory storage with optional disk persistence
  - ETS tables for metadata and vector storage
  - Pure Elixir implementation (Zig NIFs can be added later for performance)
  
  ## Configuration
  
  - `:max_elements` - Maximum number of vectors (default: 100_000)
  - `:ef_construction` - HNSW build-time accuracy parameter (default: 200)
  - `:M` - Number of bi-directional links per layer (default: 16)
  - `:random_seed` - Random seed for HNSW construction (default: 100)
  
  ## Performance
  
  - Insert: O(log N) amortized
  - Search: O(log N) with high recall
  - Memory: ~4-8 bytes per dimension + metadata overhead
  
  ## When to Use
  
  - Prototyping and development
  - Small to medium datasets (< 1M vectors)
  - Low-latency requirements
  - No external dependencies needed
  """
  
  @behaviour Zixir.VectorDB.Backend
  
  require Logger
  
  alias Zixir.VectorDB.Math
  
  @default_max_elements 100_000
  @default_ef_construction 200
  @default_m 16
  @default_random_seed 100
  
  @typedoc "HNSW index state"
  @type state :: %{
    hnsw_state: map(),
    metadata_table: atom(),
    vector_table: atom(),
    dimensions: pos_integer(),
    metric: atom(),
    count: non_neg_integer()
  }
  
  @impl true
  @spec init(keyword()) :: {:ok, state()} | {:error, term()}
  def init(config) do
    name = config[:name] || "unnamed"
    dimensions = config[:dimensions]
    metric = config[:metric] || :cosine
    max_elements = config[:max_elements] || @default_max_elements
    ef_construction = config[:ef_construction] || @default_ef_construction
    m = config[:M] || @default_m
    seed = config[:random_seed] || @default_random_seed
    
    # Create ETS tables for metadata and vector storage
    metadata_table = :ets.new(:"#{name}_metadata", [:set, :public, read_concurrency: true])
    vector_table = :ets.new(:"#{name}_vectors", [:set, :public, read_concurrency: true])
    
    # Initialize HNSW index
    case Math.hnsw_init(dimensions, max_elements, ef_construction, m, seed, metric) do
      {:ok, hnsw_state} ->
        state = %{
          hnsw_state: hnsw_state,
          metadata_table: metadata_table,
          vector_table: vector_table,
          dimensions: dimensions,
          metric: metric,
          count: 0
        }
        {:ok, state}
        
      {:error, reason} ->
        :ets.delete(metadata_table)
        :ets.delete(vector_table)
        {:error, "Failed to initialize HNSW index: #{reason}"}
    end
  end
  
  @impl true
  @spec insert(state(), String.t(), [float()], map()) :: {:ok, state()} | {:error, term()}
  def insert(state, id, vector, metadata) do
    # Normalize vector if using cosine similarity
    normalized_vector = normalize_if_needed(vector, state.metric)
    
    # Add to HNSW index
    case Math.hnsw_add(state.hnsw_state, id, normalized_vector) do
      {:ok, new_hnsw_state} ->
        # Store metadata and original vector
        :ets.insert(state.metadata_table, {id, metadata})
        :ets.insert(state.vector_table, {id, vector})
        
        # Update count
        new_count = state.count + 1
        new_state = %{state | hnsw_state: new_hnsw_state, count: new_count}
        {:ok, new_state}
        
      {:error, reason} ->
        {:error, "Failed to insert vector: #{reason}"}
    end
  end
  
  @impl true
  @spec insert_batch(state(), [map()]) :: {:ok, state()} | {:error, term()}
  def insert_batch(state, vectors) do
    Enum.reduce_while(vectors, {:ok, state}, fn %{id: id, vector: vector, metadata: metadata}, {:ok, current_state} ->
      case insert(current_state, id, vector, metadata) do
        {:ok, new_state} -> {:cont, {:ok, new_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
  
  @impl true
  @spec search(state(), [float()], keyword()) :: [Zixir.VectorDB.search_result()] | {:error, term()}
  def search(state, query, opts) do
    top_k = opts[:top_k] || 10
    include_vectors = opts[:include_vectors] || false
    metric = opts[:metric] || state.metric
    
    # Normalize query if using cosine
    normalized_query = normalize_if_needed(query, metric)
    
    # Search HNSW index
    case Math.hnsw_search(state.hnsw_state, normalized_query, top_k, metric) do
      {:ok, results} ->
        # Enrich results with metadata and optionally vectors
        enriched = Enum.map(results, fn %{id: id, score: score} ->
          metadata = get_metadata(state, id)
          vector = if include_vectors, do: get_vector(state, id), else: nil
          
          %{
            id: id,
            score: score,
            vector: vector,
            metadata: metadata
          }
        end)
        
        {:ok, enriched}
        
      {:error, reason} ->
        {:error, "Search failed: #{reason}"}
    end
  end
  
  @impl true
  @spec delete(state(), String.t()) :: {:ok, state()} | {:error, term()}
  def delete(state, id) do
    # Mark as deleted in HNSW
    case Math.hnsw_mark_deleted(state.hnsw_state, id) do
      {:ok, new_hnsw_state} ->
        # Remove from ETS tables
        :ets.delete(state.metadata_table, id)
        :ets.delete(state.vector_table, id)
        
        new_count = max(0, state.count - 1)
        new_state = %{state | hnsw_state: new_hnsw_state, count: new_count}
        {:ok, new_state}
        
      {:error, reason} ->
        {:error, "Failed to delete vector: #{reason}"}
    end
  end
  
  @impl true
  @spec get(state(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(state, id) do
    case :ets.lookup(state.metadata_table, id) do
      [{^id, metadata}] ->
        vector = get_vector(state, id)
        {:ok, %{vector: vector, metadata: metadata}}
        
      [] ->
        {:error, :not_found}
    end
  end
  
  @impl true
  @spec update_metadata(state(), String.t(), map()) :: :ok | {:error, term()}
  def update_metadata(state, id, new_metadata) do
    case :ets.lookup(state.metadata_table, id) do
      [{^id, _old_metadata}] ->
        :ets.insert(state.metadata_table, {id, new_metadata})
        :ok
        
      [] ->
        {:error, :not_found}
    end
  end
  
  @impl true
  @spec stats(state()) :: map()
  def stats(state) do
    %{
      count: state.count,
      max_elements: state.hnsw_state.max_elements,
      ef_construction: state.hnsw_state.ef_construction,
      m: state.hnsw_state.m
    }
  end
  
  @impl true
  @spec save(state(), String.t()) :: :ok | {:error, term()}
  def save(state, path) do
    # Serialize state to disk
    data = %{
      dimensions: state.dimensions,
      metric: state.metric,
      count: state.count,
      hnsw_state: state.hnsw_state,
      metadata: :ets.tab2list(state.metadata_table),
      vectors: :ets.tab2list(state.vector_table)
    }
    
    binary = :erlang.term_to_binary(data, compressed: 9)
    
    case File.write(path, binary) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to save: #{reason}"}
    end
  end
  
  @impl true
  @spec load(String.t(), keyword()) :: {:ok, state()} | {:error, term()}
  def load(path, opts) do
    case File.read(path) do
      {:ok, binary} ->
        try do
          data = :erlang.binary_to_term(binary, [:safe])
          
          # Reconstruct state
          metadata_table = :ets.new(:loaded_metadata, [:set, :public, read_concurrency: true])
          vector_table = :ets.new(:loaded_vectors, [:set, :public, read_concurrency: true])
          
          # Restore metadata and vectors
          :ets.insert(metadata_table, data.metadata)
          :ets.insert(vector_table, data.vectors)
          
          state = %{
            hnsw_state: data.hnsw_state,
            metadata_table: metadata_table,
            vector_table: vector_table,
            dimensions: data.dimensions,
            metric: data.metric,
            count: data.count,
            backend: :memory
          }
          
          {:ok, state}
        rescue
          _ -> {:error, "Corrupted save file"}
        end
        
      {:error, reason} ->
        {:error, "Failed to load: #{inspect(reason)}"}
    end
  end

  @impl true
  @spec close(state()) :: :ok
  def close(state) do
    # Free HNSW index
    Math.hnsw_free(state.hnsw_state)
    
    # Clean up ETS tables
    :ets.delete(state.metadata_table)
    :ets.delete(state.vector_table)
    
    :ok
  end
  
  @impl true
  @spec backend_type() :: atom()
  def backend_type, do: :memory
  
  # Private functions
  
  defp get_metadata(state, id) do
    case :ets.lookup(state.metadata_table, id) do
      [{^id, metadata}] -> metadata
      [] -> %{}
    end
  end
  
  defp get_vector(state, id) do
    case :ets.lookup(state.vector_table, id) do
      [{^id, vector}] -> vector
      [] -> nil
    end
  end
  
  defp normalize_if_needed(vector, :cosine) do
    Math.normalize(vector)
  end
  
  defp normalize_if_needed(vector, _), do: vector
end