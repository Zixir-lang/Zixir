defmodule Zixir.VectorDB.Math do
  @moduledoc """
  Vector math operations and HNSW indexing.
  
  Currently uses pure Elixir implementation. Zig NIFs can be added later
  for performance optimization.
  """
  
  @doc """
  Calculate cosine similarity between two vectors.
  """
  def cosine_similarity(a, b) when length(a) == length(b) do
    dot = dot_product(a, b)
    norm_a = :math.sqrt(Enum.sum(Enum.map(a, &(&1 * &1))))
    norm_b = :math.sqrt(Enum.sum(Enum.map(b, &(&1 * &1))))
    
    if norm_a == 0.0 or norm_b == 0.0 do
      0.0
    else
      dot / (norm_a * norm_b)
    end
  end
  
  def cosine_similarity(_, _), do: raise(ArgumentError, "Vectors must have same dimensions")
  
  @doc """
  Calculate Euclidean distance between two vectors.
  """
  def euclidean_distance(a, b) when length(a) == length(b) do
    a
    |> Enum.zip(b)
    |> Enum.map(fn {x, y} -> (x - y) * (x - y) end)
    |> Enum.sum()
    |> :math.sqrt()
  end
  
  def euclidean_distance(_, _), do: raise(ArgumentError, "Vectors must have same dimensions")
  
  @doc """
  Calculate dot product of two vectors.
  """
  def dot_product(a, b) when length(a) == length(b) do
    a
    |> Enum.zip(b)
    |> Enum.map(fn {x, y} -> x * y end)
    |> Enum.sum()
  end
  
  def dot_product(_, _), do: raise(ArgumentError, "Vectors must have same dimensions")
  
  @doc """
  Normalize a vector to unit length.
  """
  def normalize(vector) do
    norm = :math.sqrt(Enum.sum(Enum.map(vector, &(&1 * &1))))
    
    if norm == 0.0 do
      Enum.map(vector, fn _ -> 0.0 end)
    else
      Enum.map(vector, &(&1 / norm))
    end
  end
  
  # HNSW Index operations (Elixir implementation)
  
  @doc """
  Initialize HNSW index.
  """
  def hnsw_init(dimensions, max_elements, ef_construction, m, seed, metric) do
    state = %{
      dimensions: dimensions,
      max_elements: max_elements,
      ef_construction: ef_construction,
      m: m,
      seed: seed,
      metric: metric,
      count: 0,
      vectors: %{},
      ids: %{},
      deleted: MapSet.new()
    }
    
    {:ok, state}
  end
  
  @doc """
  Add vector to index.
  """
  def hnsw_add(state, id, vector) do
    if state.count >= state.max_elements do
      {:error, :index_full}
    else
      idx = state.count
      
      state = 
        state
        |> put_in([:vectors, idx], vector)
        |> put_in([:ids, idx], id)
        |> Map.put(:count, idx + 1)
      
      {:ok, state}
    end
  end
  
  @doc """
  Search index for nearest neighbors.
  """
  def hnsw_search(state, query, top_k, metric) do
    # Linear search (simplified HNSW)
    results = 
      for idx <- 0..(state.count - 1),
          not MapSet.member?(state.deleted, idx),
          vector = state.vectors[idx] do
        
        score = case metric do
          :cosine -> cosine_similarity(query, vector)
          :euclidean -> 1.0 / (1.0 + euclidean_distance(query, vector))
          :dot -> dot_product(query, vector)
          _ -> cosine_similarity(query, vector)
        end
        
        %{id: state.ids[idx], score: score}
      end
    
    # Sort by score descending and take top_k
    results
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(top_k)
    |> then(&{:ok, &1})
  end
  
  @doc """
  Mark vector as deleted.
  Returns ok even if vector not found (idempotent).
  """
  def hnsw_mark_deleted(state, id) do
    case Enum.find(state.ids, fn {idx, vec_id} -> vec_id == id end) do
      {idx, _} ->
        state = %{state | deleted: MapSet.put(state.deleted, idx)}
        {:ok, state}
      
      nil ->
        # Idempotent delete - return ok even if not found
        {:ok, state}
    end
  end
  
  @doc """
  Free HNSW index (no-op for Elixir implementation).
  """
  def hnsw_free(_state) do
    :ok
  end
end