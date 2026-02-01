defmodule Zixir.Engine.Math do
  @moduledoc """
  Zig engine NIFs: comprehensive math and data operations.
  Uses Zigler BEAM allocator. Keep NIFs short (< 1ms).
  
  Provides 20+ operations with graceful fallbacks to pure Elixir.
  """

  use Zig, otp_app: :zixir

  ~Z"""
  const std = @import("std");

  // ============================================
  // Basic Aggregations
  // ============================================
  
  /// Sum of f64 list
  pub fn list_sum(array: []const f64) f64 {
    var sum: f64 = 0.0;
    for (array) |item| {
      sum += item;
    }
    return sum;
  }

  /// Product of f64 list
  pub fn list_product(array: []const f64) f64 {
    var prod: f64 = 1.0;
    for (array) |item| {
      prod *= item;
    }
    return prod;
  }

  /// Mean (average) of f64 list
  pub fn list_mean(array: []const f64) f64 {
    if (array.len == 0) return 0.0;
    var sum: f64 = 0.0;
    for (array) |item| {
      sum += item;
    }
    return sum / @as(f64, @floatFromInt(array.len));
  }

  /// Minimum value in f64 list
  pub fn list_min(array: []const f64) f64 {
    if (array.len == 0) return 0.0;
    var min_val = array[0];
    for (array[1..]) |item| {
      if (item < min_val) min_val = item;
    }
    return min_val;
  }

  /// Maximum value in f64 list
  pub fn list_max(array: []const f64) f64 {
    if (array.len == 0) return 0.0;
    var max_val = array[0];
    for (array[1..]) |item| {
      if (item > max_val) max_val = item;
    }
    return max_val;
  }

  // ============================================
  // Vector Operations
  // ============================================
  
  /// Dot product of two f64 slices
  pub fn dot_product(a: []const f64, b: []const f64) f64 {
    if (a.len != b.len) return 0.0;
    var sum: f64 = 0.0;
    for (a, b) |x, y| {
      sum += x * y;
    }
    return sum;
  }

  /// Element-wise addition of two arrays
  pub fn vec_add(a: []const f64, b: []const f64) []f64 {
    const len = if (a.len < b.len) a.len else b.len;
    var result = std.heap.page_allocator.alloc(f64, len) catch return &[_]f64{};
    for (0..len) |i| {
      result[i] = a[i] + b[i];
    }
    return result;
  }

  /// Element-wise subtraction of two arrays
  pub fn vec_sub(a: []const f64, b: []const f64) []f64 {
    const len = if (a.len < b.len) a.len else b.len;
    var result = std.heap.page_allocator.alloc(f64, len) catch return &[_]f64{};
    for (0..len) |i| {
      result[i] = a[i] - b[i];
    }
    return result;
  }

  /// Element-wise multiplication of two arrays
  pub fn vec_mul(a: []const f64, b: []const f64) []f64 {
    const len = if (a.len < b.len) a.len else b.len;
    var result = std.heap.page_allocator.alloc(f64, len) catch return &[_]f64{};
    for (0..len) |i| {
      result[i] = a[i] * b[i];
    }
    return result;
  }

  /// Element-wise division of two arrays
  pub fn vec_div(a: []const f64, b: []const f64) []f64 {
    const len = if (a.len < b.len) a.len else b.len;
    var result = std.heap.page_allocator.alloc(f64, len) catch return &[_]f64{};
    for (0..len) |i| {
      result[i] = if (b[i] != 0.0) a[i] / b[i] else 0.0;
    }
    return result;
  }

  /// Scale array by constant
  pub fn vec_scale(array: []const f64, scalar: f64) []f64 {
    var result = std.heap.page_allocator.alloc(f64, array.len) catch return &[_]f64{};
    for (array, 0..) |item, i| {
      result[i] = item * scalar;
    }
    return result;
  }

  // ============================================
  // Transformations
  // ============================================
  
  /// Map: apply function to each element (simulated with common ops)
  pub fn map_add(array: []const f64, value: f64) []f64 {
    var result = std.heap.page_allocator.alloc(f64, array.len) catch return &[_]f64{};
    for (array, 0..) |item, i| {
      result[i] = item + value;
    }
    return result;
  }

  pub fn map_mul(array: []const f64, value: f64) []f64 {
    var result = std.heap.page_allocator.alloc(f64, array.len) catch return &[_]f64{};
    for (array, 0..) |item, i| {
      result[i] = item * value;
    }
    return result;
  }

  /// Filter: keep elements where predicate is true (using threshold)
  pub fn filter_gt(array: []const f64, threshold: f64) []f64 {
    var temp = std.heap.page_allocator.alloc(f64, array.len) catch return &[_]f64{};
    defer std.heap.page_allocator.free(temp);
    
    var count: usize = 0;
    for (array) |item| {
      if (item > threshold) {
        temp[count] = item;
        count += 1;
      }
    }
    
    var result = std.heap.page_allocator.alloc(f64, count) catch return &[_]f64{};
    for (0..count) |i| {
      result[i] = temp[i];
    }
    return result;
  }

  // ============================================
  // Sorting and Searching
  // ============================================
  
  /// Sort array in ascending order (returns new array)
  pub fn sort_asc(array: []const f64) []f64 {
    var result = std.heap.page_allocator.alloc(f64, array.len) catch return &[_]f64{};
    for (array, 0..) |item, i| {
      result[i] = item;
    }
    
    // Simple bubble sort for small arrays
    var i: usize = 0;
    while (i < result.len) : (i += 1) {
      var j: usize = 0;
      while (j < result.len - i - 1) : (j += 1) {
        if (result[j] > result[j + 1]) {
          const temp = result[j];
          result[j] = result[j + 1];
          result[j + 1] = temp;
        }
      }
    }
    return result;
  }

  /// Find index of value in array (-1 if not found)
  pub fn find_index(array: []const f64, value: f64) i64 {
    for (array, 0..) |item, i| {
      if (item == value) return @intCast(i);
    }
    return -1;
  }

  /// Count occurrences of value
  pub fn count_value(array: []const f64, value: f64) i64 {
    var count: i64 = 0;
    for (array) |item| {
      if (item == value) count += 1;
    }
    return count;
  }

  // ============================================
  // Matrix Operations
  // ============================================
  
  /// Matrix multiplication (2D only, flattened)
  pub fn mat_mul(a: []const f64, b: []const f64, a_rows: i64, a_cols: i64, b_cols: i64) []f64 {
    const m = @as(usize, @intCast(a_rows));
    const n = @as(usize, @intCast(a_cols));
    const p = @as(usize, @intCast(b_cols));
    
    var result = std.heap.page_allocator.alloc(f64, m * p) catch return &[_]f64{};
    
    for (0..m) |i| {
      for (0..p) |j| {
        var sum: f64 = 0.0;
        for (0..n) |k| {
          sum += a[i * n + k] * b[k * p + j];
        }
        result[i * p + j] = sum;
      }
    }
    return result;
  }

  /// Matrix transpose (2D, flattened)
  pub fn mat_transpose(matrix: []const f64, rows: i64, cols: i64) []f64 {
    const r = @as(usize, @intCast(rows));
    const c = @as(usize, @intCast(cols));
    
    var result = std.heap.page_allocator.alloc(f64, r * c) catch return &[_]f64{};
    
    for (0..r) |i| {
      for (0..c) |j| {
        result[j * r + i] = matrix[i * c + j];
      }
    }
    return result;
  }

  // ============================================
  // Statistics
  // ============================================
  
  /// Variance of f64 list
  pub fn list_variance(array: []const f64) f64 {
    if (array.len < 2) return 0.0;
    const mean_val = list_mean(array);
    var sum_sq_diff: f64 = 0.0;
    for (array) |item| {
      const diff = item - mean_val;
      sum_sq_diff += diff * diff;
    }
    return sum_sq_diff / @as(f64, @floatFromInt(array.len));
  }

  /// Standard deviation of f64 list
  pub fn list_std(array: []const f64) f64 {
    return std.math.sqrt(list_variance(array));
  }

  // ============================================
  // String Operations
  // ============================================
  
  /// Byte length of binary
  pub fn string_count(string: []const u8) i64 {
    return @intCast(string.len);
  }

  /// Find substring position (-1 if not found)
  pub fn string_find(haystack: []const u8, needle: []const u8) i64 {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return -1;
    
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
      var found = true;
      var j: usize = 0;
      while (j < needle.len) : (j += 1) {
        if (haystack[i + j] != needle[j]) {
          found = false;
          break;
        }
      }
      if (found) return @intCast(i);
    }
    return -1;
  }

  /// Check if string starts with prefix
  pub fn string_starts_with(string: []const u8, prefix: []const u8) bool {
    if (prefix.len > string.len) return false;
    for (prefix, 0..) |c, i| {
      if (string[i] != c) return false;
    }
    return true;
  }

  /// Check if string ends with suffix
  pub fn string_ends_with(string: []const u8, suffix: []const u8) bool {
    if (suffix.len > string.len) return false;
    const offset = string.len - suffix.len;
    for (suffix, 0..) |c, i| {
      if (string[offset + i] != c) return false;
    }
    return true;
  }
  """

  @doc """
  Check if NIFs are loaded and available.
  """
  @spec nifs_available?() :: boolean()
  def nifs_available? do
    try do
      _ = list_sum([])
      true
    rescue
      _ -> false
    end
  end

  # ============================================
  # Safe wrappers with Elixir fallbacks
  # ============================================

  @doc """
  Safely calculate sum of list with Elixir fallback.
  """
  @spec list_sum_safe(list(number())) :: number()
  def list_sum_safe(array) when is_list(array) do
    if nifs_available?() do
      # Convert integers to floats for the NIF
      float_array = Enum.map(array, &convert_to_float/1)
      list_sum(float_array)
    else
      Enum.sum(array)
    end
  end

  @doc """
  Safely calculate product of list with Elixir fallback.
  """
  @spec list_product_safe(list(number())) :: number()
  def list_product_safe(array) when is_list(array) do
    if nifs_available?(), do: list_product(array), else: Enum.product(array)
  end

  @doc """
  Safely calculate mean of list with Elixir fallback.
  """
  @spec list_mean_safe(list(number())) :: float()
  def list_mean_safe(array) when is_list(array) do
    if nifs_available?() do
      list_mean(array)
    else
      if length(array) == 0, do: 0.0, else: Enum.sum(array) / length(array)
    end
  end

  @doc """
  Safely find minimum value in list with Elixir fallback.
  """
  @spec list_min_safe(list(number())) :: number()
  def list_min_safe(array) when is_list(array) do
    if nifs_available?() do
      list_min(array)
    else
      Enum.min(array, fn -> 0.0 end)
    end
  end

  @doc """
  Safely find maximum value in list with Elixir fallback.
  """
  @spec list_max_safe(list(number())) :: number()
  def list_max_safe(array) when is_list(array) do
    if nifs_available?() do
      list_max(array)
    else
      Enum.max(array, fn -> 0.0 end)
    end
  end

  def dot_product_safe(a, b) when is_list(a) and is_list(b) do
    if nifs_available?() do
      dot_product(a, b)
    else
      if length(a) != length(b) do
        0.0
      else
        Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
      end
    end
  end

  def vec_add_safe(a, b) when is_list(a) and is_list(b) do
    if nifs_available?() do
      vec_add(a, b)
    else
      len = min(length(a), length(b))
      for i <- 0..(len-1), do: Enum.at(a, i) + Enum.at(b, i)
    end
  end

  def vec_sub_safe(a, b) when is_list(a) and is_list(b) do
    if nifs_available?() do
      vec_sub(a, b)
    else
      len = min(length(a), length(b))
      for i <- 0..(len-1), do: Enum.at(a, i) - Enum.at(b, i)
    end
  end

  def vec_mul_safe(a, b) when is_list(a) and is_list(b) do
    if nifs_available?() do
      vec_mul(a, b)
    else
      len = min(length(a), length(b))
      for i <- 0..(len-1), do: Enum.at(a, i) * Enum.at(b, i)
    end
  end

  def vec_div_safe(a, b) when is_list(a) and is_list(b) do
    if nifs_available?() do
      vec_div(a, b)
    else
      len = min(length(a), length(b))
      for i <- 0..(len-1) do
        divisor = Enum.at(b, i)
        if divisor != 0, do: Enum.at(a, i) / divisor, else: 0.0
      end
    end
  end

  def vec_scale_safe(array, scalar) when is_list(array) and is_number(scalar) do
    if nifs_available?() do
      vec_scale(array, scalar)
    else
      Enum.map(array, &(&1 * scalar))
    end
  end

  def map_add_safe(array, value) when is_list(array) and is_number(value) do
    if nifs_available?(), do: map_add(array, value), else: Enum.map(array, &(&1 + value))
  end

  def map_mul_safe(array, value) when is_list(array) and is_number(value) do
    if nifs_available?(), do: map_mul(array, value), else: Enum.map(array, &(&1 * value))
  end

  def filter_gt_safe(array, threshold) when is_list(array) and is_number(threshold) do
    if nifs_available?(), do: filter_gt(array, threshold), else: Enum.filter(array, &(&1 > threshold))
  end

  def sort_asc_safe(array) when is_list(array) do
    if nifs_available?(), do: sort_asc(array), else: Enum.sort(array)
  end

  def find_index_safe(array, value) when is_list(array) do
    if nifs_available?() do
      find_index(array, value)
    else
      case Enum.find_index(array, &(&1 == value)) do
        nil -> -1
        idx -> idx
      end
    end
  end

  def count_value_safe(array, value) when is_list(array) do
    if nifs_available?(), do: count_value(array, value), else: Enum.count(array, &(&1 == value))
  end

  def list_variance_safe(array) when is_list(array) do
    if nifs_available?() do
      list_variance(array)
    else
      if length(array) < 2 do
        0.0
      else
        mean = Enum.sum(array) / length(array)
        Enum.map(array, &((&1 - mean) * (&1 - mean)))
        |> Enum.sum()
        |> Kernel./(length(array))
      end
    end
  end

  def list_std_safe(array) when is_list(array) do
    if nifs_available?() do
      list_std(array)
    else
      :math.sqrt(list_variance_safe(array))
    end
  end

  def string_count_safe(string) when is_binary(string) do
    if nifs_available?(), do: string_count(string), else: byte_size(string)
  end

  def string_find_safe(haystack, needle) when is_binary(haystack) and is_binary(needle) do
    if nifs_available?() do
      string_find(haystack, needle)
    else
      case :binary.match(haystack, needle) do
        :nomatch -> -1
        {pos, _} -> pos
      end
    end
  end

  def string_starts_with_safe(string, prefix) when is_binary(string) and is_binary(prefix) do
    if nifs_available?() do
      string_starts_with(string, prefix)
    else
      String.starts_with?(string, prefix)
    end
  end

  def string_ends_with_safe(string, suffix) when is_binary(string) and is_binary(suffix) do
    if nifs_available?() do
      string_ends_with(string, suffix)
    else
      String.ends_with?(string, suffix)
    end
  end

  # Matrix operations (always use Elixir fallback for complex allocations)
  def mat_mul_safe(a, b, a_rows, a_cols, b_cols) 
      when is_list(a) and is_list(b) and is_integer(a_rows) and is_integer(a_cols) and is_integer(b_cols) do
    # Matrix multiplication in Elixir
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

  def mat_transpose_safe(matrix, rows, cols) when is_list(matrix) and is_integer(rows) and is_integer(cols) do
    for j <- 0..(cols-1) do
      for i <- 0..(rows-1) do
        Enum.at(matrix, i * cols + j, 0.0)
      end
    end
    |> List.flatten()
  end

  # Helper function to convert integers to floats
  defp convert_to_float(n) when is_integer(n), do: n * 1.0
  defp convert_to_float(n) when is_float(n), do: n
  defp convert_to_float(_), do: 0.0
end
