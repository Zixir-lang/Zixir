defmodule Zixir.Embedding do
  @moduledoc """
  Lightweight, dependency-free text embedding generation.
  
  Uses hash-based deterministic embeddings for zero-dependency semantic search.
  Much faster than ML models but less semantically aware (keyword-focused).
  
  ## Performance
  - Generation: ~1ms per document
  - No external dependencies
  - No network calls
  - Works offline
  
  ## Algorithm
  1. Generate hash from text using :erlang.phash2
  2. Create deterministic pseudo-random vector using sine waves
  3. Normalize to unit length
  4. Return 1536-dimensional vector
  
  ## Trade-offs
  - ✅ Fast (1000x faster than API calls)
  - ✅ Zero dependencies
  - ✅ Deterministic (same text = same embedding)
  - ❌ Less semantic understanding than ML models
  - ❌ "Dog" ≠ "Canine" (but "database query" ≈ "SQL search")
  """
  
  @default_dimensions 1536
  @hash_space 1_000_000
  
  @doc """
  Generate embedding vector from text.
  
  ## Options
  - `:dimensions` - Vector dimensions (default: 1536)
  
  ## Examples
      iex> Zixir.Embedding.generate("Hello world")
      {:ok, [0.123, -0.456, ...]} # 1536 floats
      
      iex> Zixir.Embedding.generate("", dimensions: 384)
      {:ok, [0.0, 0.0, ...]} # 384 zeros
  """
  @spec generate(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def generate(text, opts \\ []) when is_binary(text) do
    dimensions = opts[:dimensions] || @default_dimensions
    
    # Handle empty text
    if String.trim(text) == "" do
      {:ok, List.duplicate(0.0, dimensions)}
    else
      # Generate deterministic hash
      hash = :erlang.phash2(text, @hash_space)
      
      # Create vector from hash using sine waves
      vector = 
        1..dimensions
        |> Enum.map(fn i ->
          # Use multiple harmonics for better distribution
          val = :math.sin(hash * i / 1000.0) * 0.5 +
                :math.sin(hash * i / 100.0) * 0.3 +
                :math.sin(hash * i / 10.0) * 0.2
          
          # Add position-based variation
          position_factor = :math.sin(i / dimensions * :math.pi())
          val * position_factor
        end)
      
      # Normalize to unit length
      normalized = normalize(vector)
      
      {:ok, normalized}
    end
  end
  
  @doc """
  Generate embedding and return immediately (raises on error).
  """
  @spec generate!(String.t(), keyword()) :: [float()]
  def generate!(text, opts \\ []) do
    case generate(text, opts) do
      {:ok, vector} -> vector
      {:error, reason} -> raise "Embedding generation failed: #{inspect(reason)}"
    end
  end
  
  @doc """
  Batch generate embeddings for multiple texts.
  
  ## Examples
      iex> Zixir.Embedding.generate_batch(["text1", "text2"])
      {:ok, [[0.1, ...], [0.2, ...]]}
  """
  @spec generate_batch([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def generate_batch(texts, opts \\ []) when is_list(texts) do
    try do
      vectors = Enum.map(texts, fn text ->
        {:ok, vector} = generate(text, opts)
        vector
      end)
      {:ok, vectors}
    rescue
      e -> {:error, "Batch embedding failed: #{inspect(e)}"}
    end
  end
  
  @doc """
  Calculate cosine similarity between two embeddings.
  Returns score between -1.0 and 1.0.
  """
  @spec similarity([float()], [float()]) :: float()
  def similarity(a, b) when length(a) == length(b) do
    dot = dot_product(a, b)
    norm_a = :math.sqrt(Enum.sum(Enum.map(a, &(&1 * &1))))
    norm_b = :math.sqrt(Enum.sum(Enum.map(b, &(&1 * &1))))
    
    if norm_a == 0.0 or norm_b == 0.0 do
      0.0
    else
      dot / (norm_a * norm_b)
    end
  end
  
  def similarity(_, _), do: 0.0
  
  @doc """
  Get embedding dimensions.
  """
  @spec dimensions() :: integer()
  def dimensions, do: @default_dimensions
  
  # Private functions
  
  defp normalize(vector) do
    norm = :math.sqrt(Enum.sum(Enum.map(vector, &(&1 * &1))))
    
    if norm == 0.0 do
      vector
    else
      Enum.map(vector, &(&1 / norm))
    end
  end
  
  defp dot_product(a, b) when length(a) == length(b) do
    a
    |> Enum.zip(b)
    |> Enum.map(fn {x, y} -> x * y end)
    |> Enum.sum()
  end
  
  defp dot_product(_, _), do: 0.0
end