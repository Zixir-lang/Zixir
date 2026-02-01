defmodule Zixir.Utils do
  @moduledoc """
  Shared utility functions for Zixir.
  
  Provides common functionality used across multiple modules including:
  - Byte formatting for memory display
  - ID generation with optional prefixes
  - Time utilities
  """

  @doc """
  Format bytes into human-readable string (B, KB, MB, GB).
  
  ## Examples
  
      iex> Zixir.Utils.format_bytes(512)
      "512 B"
      
      iex> Zixir.Utils.format_bytes(1536)
      "1.5 KB"
      
      iex> Zixir.Utils.format_bytes(1024 * 1024 * 2)
      "2.0 MB"
  """
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 2)} KB"
  def format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"
  def format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"

  @doc """
  Generate a random ID with optional prefix.
  
  ## Options
  
    * `:prefix` - String prefix for the ID (default: "")
    * `:bytes` - Number of random bytes (default: 8)
  
  ## Examples
  
      iex> Zixir.Utils.generate_id()
      "a1b2c3d4e5f6g7h8"
      
      iex> Zixir.Utils.generate_id(prefix: "wf_")
      "wf_a1b2c3d4e5f6g7h8"
      
      iex> Zixir.Utils.generate_id(bytes: 4)
      "a1b2c3d4"
  """
  def generate_id(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")
    bytes = Keyword.get(opts, :bytes, 8)
    
    id = Base.encode16(:crypto.strong_rand_bytes(bytes), case: :lower)
    prefix <> id
  end

  @doc """
  Get current time in milliseconds using monotonic clock.
  """
  def now_ms do
    System.monotonic_time(:millisecond)
  end

  @doc """
  Get current UTC time as ISO8601 string.
  """
  def iso8601_now do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end
end
