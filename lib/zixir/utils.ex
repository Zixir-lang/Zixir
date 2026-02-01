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
  @spec format_bytes(non_neg_integer()) :: String.t()
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
  @spec generate_id(keyword()) :: String.t()
  def generate_id(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")
    bytes = Keyword.get(opts, :bytes, 8)

    id = Base.encode16(:crypto.strong_rand_bytes(bytes), case: :lower)
    prefix <> id
  end

  @doc """
  Get current time in milliseconds using monotonic clock.
  """
  @spec now_ms() :: integer()
  def now_ms do
    System.monotonic_time(:millisecond)
  end

  @doc """
  Get current UTC time as ISO8601 string.
  """
  @spec iso8601_now() :: String.t()
  def iso8601_now do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  @doc """
  Calculate the average (mean) of a list of numbers.

  Returns 0.0 for empty lists to avoid division by zero.

  ## Examples

      iex> Zixir.Utils.average([1, 2, 3, 4, 5])
      3.0

      iex> Zixir.Utils.average([])
      0.0

      iex> Zixir.Utils.average([10, 20, 30])
      20.0
  """
  @spec average(list(number())) :: float()
  def average(list) when length(list) == 0, do: 0.0
  def average(list), do: Enum.sum(list) / length(list)

  @doc """
  Calculate the frequency distribution of items in a list.

  Returns a map where keys are the unique items and values are their counts.

  ## Examples

      iex> Zixir.Utils.frequencies(["a", "b", "a", "c", "a", "b"])
      %{"a" => 3, "b" => 2, "c" => 1}

      iex> Zixir.Utils.frequencies([1, 2, 2, 3, 3, 3])
      %{1 => 1, 2 => 2, 3 => 3}

      iex> Zixir.Utils.frequencies([])
      %{}
  """
  @spec frequencies(list()) :: map()
  def frequencies(list) do
    Enum.reduce(list, %{}, fn item, acc ->
      Map.update(acc, item, 1, &(&1 + 1))
    end)
  end

  @doc """
  Parse a human-readable memory size string into bytes.

  Supports various formats:
  - "2GB", "2 GB", "2gb" → 2147483648 bytes
  - "512MB", "512 MB" → 536870912 bytes
  - "1024KB", "1024 KB" → 1048576 bytes
  - "2048" → 2048 bytes (assumes bytes)
  - Integer values are returned as-is

  ## Examples

      iex> Zixir.Utils.parse_memory_size("2GB")
      2147483648

      iex> Zixir.Utils.parse_memory_size("512MB")
      536870912

      iex> Zixir.Utils.parse_memory_size("1024KB")
      1048576

      iex> Zixir.Utils.parse_memory_size("2048")
      2048

      iex> Zixir.Utils.parse_memory_size(1073741824)
      1073741824

      iex> Zixir.Utils.parse_memory_size(nil)
      nil
  """
  @spec parse_memory_size(String.t() | integer() | nil) :: integer() | nil
  def parse_memory_size(nil), do: nil
  def parse_memory_size(value) when is_integer(value), do: value

  def parse_memory_size(value) when is_binary(value) do
    value = value |> String.trim() |> String.upcase()

    cond do
      String.ends_with?(value, "GB") ->
        num = value |> String.replace("GB", "") |> String.trim() |> String.to_integer()
        num * 1024 * 1024 * 1024

      String.ends_with?(value, "MB") ->
        num = value |> String.replace("MB", "") |> String.trim() |> String.to_integer()
        num * 1024 * 1024

      String.ends_with?(value, "KB") ->
        num = value |> String.replace("KB", "") |> String.trim() |> String.to_integer()
        num * 1024

      true ->
        String.to_integer(value)
    end
  end

  @doc """
  Safely retrieve a nested value from a map using a list of keys.

  Returns nil if any key in the path is missing or if the intermediate
  value is not a map.

  ## Examples

      iex> Zixir.Utils.get_nested(%{a: %{b: 1}}, [:a, :b])
      1

      iex> Zixir.Utils.get_nested(%{a: %{b: 1}}, [:a, :c])
      nil

      iex> Zixir.Utils.get_nested(%{a: "not a map"}, [:a, :b])
      nil

      iex> Zixir.Utils.get_nested(%{}, [:a, :b])
      nil
  """
  @spec get_nested(map(), list()) :: any()
  def get_nested(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce(keys, map, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key)
        _ -> nil
      end
    end)
  end
  def get_nested(_map, _keys), do: nil
end
