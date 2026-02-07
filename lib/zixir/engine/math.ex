defmodule Zixir.Engine.Math do
  @moduledoc """
  Math and data operations engine.

  Provides 20+ operations with pure Elixir implementations.
  For higher performance with Zig NIFs, ensure zigler is configured with Zig 0.15.x.

  **Universal Setup**: This module runs without Zig using pure Elixir fallbacks.
  """

  # Commented out for universal compatibility (requires Zig 0.15.x + zigler):
  # use Zig, otp_app: :zixir
  #
  # ~Z"""
  # const std = @import("std");
  # ... Zig code ...
  # """

  @doc """
  Check if NIFs are loaded and available.
  Always returns false when running without Zig (universal mode).
  """
  @spec nifs_available?() :: boolean()
  def nifs_available? do
    false
  end

  # ============================================
  # Pure Elixir Implementations (Universal Mode)
  # ============================================

  @doc """
  Calculate sum of list.
  """
  @spec list_sum(list(number())) :: number()
  def list_sum(array) when is_list(array) do
    Enum.sum(array)
  end

  @doc """
  Calculate product of list.
  """
  @spec list_product(list(number())) :: number()
  def list_product(array) when is_list(array) do
    Enum.reduce(array, 1, &(&1 * &2))
  end

  @doc """
  Calculate mean (average) of list.
  """
  @spec list_mean(list(number())) :: float()
  def list_mean(array) when is_list(array) do
    if length(array) == 0, do: 0.0, else: Enum.sum(array) / length(array)
  end

  @doc """
  Find minimum value in list.
  """
  @spec list_min(list(number())) :: number()
  def list_min(array) when is_list(array) do
    Enum.min(array, fn -> 0.0 end)
  end

  @doc """
  Find maximum value in list.
  """
  @spec list_max(list(number())) :: number()
  def list_max(array) when is_list(array) do
    Enum.max(array, fn -> 0.0 end)
  end

  def dot_product(a, b) when is_list(a) and is_list(b) do
    if length(a) != length(b) do
      0.0
    else
      Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
    end
  end

  def vec_add(a, b) when is_list(a) and is_list(b) do
    len = min(length(a), length(b))
    for i <- 0..(len-1), do: Enum.at(a, i) + Enum.at(b, i)
  end

  def vec_sub(a, b) when is_list(a) and is_list(b) do
    len = min(length(a), length(b))
    for i <- 0..(len-1), do: Enum.at(a, i) - Enum.at(b, i)
  end

  def vec_mul(a, b) when is_list(a) and is_list(b) do
    len = min(length(a), length(b))
    for i <- 0..(len-1), do: Enum.at(a, i) * Enum.at(b, i)
  end

  def vec_div(a, b) when is_list(a) and is_list(b) do
    len = min(length(a), length(b))
    for i <- 0..(len-1) do
      divisor = Enum.at(b, i)
      if divisor != 0, do: Enum.at(a, i) / divisor, else: 0.0
    end
  end

  def vec_scale(array, scalar) when is_list(array) and is_number(scalar) do
    Enum.map(array, &(&1 * scalar))
  end

  def map_add(array, value) when is_list(array) and is_number(value) do
    Enum.map(array, &(&1 + value))
  end

  def map_mul(array, value) when is_list(array) and is_number(value) do
    Enum.map(array, &(&1 * value))
  end

  def filter_gt(array, threshold) when is_list(array) and is_number(threshold) do
    Enum.filter(array, &(&1 > threshold))
  end

  def sort_asc(array) when is_list(array) do
    Enum.sort(array)
  end

  def find_index(array, value) when is_list(array) do
    case Enum.find_index(array, &(&1 == value)) do
      nil -> -1
      idx -> idx
    end
  end

  def count_value(array, value) when is_list(array) do
    Enum.count(array, &(&1 == value))
  end

  def list_variance(array) when is_list(array) do
    if length(array) < 2 do
      0.0
    else
      mean = Enum.sum(array) / length(array)
      Enum.map(array, &((&1 - mean) * (&1 - mean)))
      |> Enum.sum()
      |> Kernel./(length(array))
    end
  end

  def list_std(array) when is_list(array) do
    :math.sqrt(list_variance(array))
  end

  def string_count(string) when is_binary(string) do
    byte_size(string)
  end

  def string_find(haystack, needle) when is_binary(haystack) and is_binary(needle) do
    case :binary.match(haystack, needle) do
      :nomatch -> -1
      {pos, _} -> pos
    end
  end

  def string_starts_with(string, prefix) when is_binary(string) and is_binary(prefix) do
    String.starts_with?(string, prefix)
  end

  def string_ends_with(string, suffix) when is_binary(string) and is_binary(suffix) do
    String.ends_with?(string, suffix)
  end

  def mat_mul(a, b, a_rows, a_cols, b_cols)
      when is_list(a) and is_list(b) and is_integer(a_rows) and is_integer(a_cols) and is_integer(b_cols) do
    for i <- 0..(a_rows-1) do
      for j <- 0..(b_cols-1) do
        for k <- 0..(a_cols-1) do
          ai = Enum.at(a, i * a_cols + k, 0.0)
          bk = Enum.at(b, k * b_cols + j, 0.0)
          ai * bk
        end
        |> Enum.sum()
      end
    end
    |> List.flatten()
  end

  def mat_transpose(matrix, rows, cols) when is_list(matrix) and is_integer(rows) and is_integer(cols) do
    for j <- 0..(cols-1) do
      for i <- 0..(rows-1) do
        Enum.at(matrix, i * cols + j, 0.0)
      end
    end
    |> List.flatten()
  end

  # ============================================
  # Safe wrappers (for compatibility)
  # ============================================

  @doc """
  Safely calculate sum with Elixir fallback.
  """
  @spec list_sum_safe(list(number())) :: number()
  def list_sum_safe(array) when is_list(array) do
    list_sum(array)
  end

  @doc """
  Safely calculate product with Elixir fallback.
  """
  @spec list_product_safe(list(number())) :: number()
  def list_product_safe(array) when is_list(array) do
    list_product(array)
  end

  @doc """
  Safely calculate mean with Elixir fallback.
  """
  @spec list_mean_safe(list(number())) :: float()
  def list_mean_safe(array) when is_list(array) do
    list_mean(array)
  end

  @doc """
  Safely find minimum with Elixir fallback.
  """
  @spec list_min_safe(list(number())) :: number()
  def list_min_safe(array) when is_list(array) do
    list_min(array)
  end

  @doc """
  Safely find maximum with Elixir fallback.
  """
  @spec list_max_safe(list(number())) :: number()
  def list_max_safe(array) when is_list(array) do
    list_max(array)
  end

  def dot_product_safe(a, b) when is_list(a) and is_list(b) do
    dot_product(a, b)
  end

  def vec_add_safe(a, b) when is_list(a) and is_list(b) do
    vec_add(a, b)
  end

  def vec_sub_safe(a, b) when is_list(a) and is_list(b) do
    vec_sub(a, b)
  end

  def vec_mul_safe(a, b) when is_list(a) and is_list(b) do
    vec_mul(a, b)
  end

  def vec_div_safe(a, b) when is_list(a) and is_list(b) do
    vec_div(a, b)
  end

  def vec_scale_safe(array, scalar) when is_list(array) and is_number(scalar) do
    vec_scale(array, scalar)
  end

  def map_add_safe(array, value) when is_list(array) and is_number(value) do
    map_add(array, value)
  end

  def map_mul_safe(array, value) when is_list(array) and is_number(value) do
    map_mul(array, value)
  end

  def filter_gt_safe(array, threshold) when is_list(array) and is_number(threshold) do
    filter_gt(array, threshold)
  end

  def sort_asc_safe(array) when is_list(array) do
    sort_asc(array)
  end

  def find_index_safe(array, value) when is_list(array) do
    find_index(array, value)
  end

  def count_value_safe(array, value) when is_list(array) do
    count_value(array, value)
  end

  def list_variance_safe(array) when is_list(array) do
    list_variance(array)
  end

  def list_std_safe(array) when is_list(array) do
    list_std(array)
  end

  def string_count_safe(string) when is_binary(string) do
    string_count(string)
  end

  def string_find_safe(haystack, needle) when is_binary(haystack) and is_binary(needle) do
    string_find(haystack, needle)
  end

  def string_starts_with_safe(string, prefix) when is_binary(string) and is_binary(prefix) do
    string_starts_with(string, prefix)
  end

  def string_ends_with_safe(string, suffix) when is_binary(string) and is_binary(suffix) do
    string_ends_with(string, suffix)
  end

  def mat_mul_safe(a, b, a_rows, a_cols, b_cols) do
    mat_mul(a, b, a_rows, a_cols, b_cols)
  end

  def mat_transpose_safe(matrix, rows, cols) do
    mat_transpose(matrix, rows, cols)
  end
end
