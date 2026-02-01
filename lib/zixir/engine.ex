defmodule Zixir.Engine do
  @moduledoc """
  Enhanced Elixir surface for Zig engine with 25+ operations.
  
  ## Available Operations
  
  ### Aggregations
  - `:list_sum` - Sum of list
  - `:list_product` - Product of list  
  - `:list_mean` - Arithmetic mean
  - `:list_min` - Minimum value
  - `:list_max` - Maximum value
  - `:list_variance` - Statistical variance
  - `:list_std` - Standard deviation
  
  ### Vector Operations
  - `:dot_product` - Dot product of two vectors
  - `:vec_add` - Element-wise addition
  - `:vec_sub` - Element-wise subtraction
  - `:vec_mul` - Element-wise multiplication
  - `:vec_div` - Element-wise division
  - `:vec_scale` - Scale by constant
  
  ### Transformations
  - `:map_add` - Add constant to each element
  - `:map_mul` - Multiply each element by constant
  - `:filter_gt` - Filter elements greater than threshold
  - `:sort_asc` - Sort ascending
  
  ### Search
  - `:find_index` - Find index of value
  - `:count_value` - Count occurrences
  
  ### Matrix Operations
  - `:mat_mul` - Matrix multiplication
  - `:mat_transpose` - Matrix transpose
  
  ### String Operations
  - `:string_count` - Byte length
  - `:string_find` - Find substring
  - `:string_starts_with` - Prefix check
  - `:string_ends_with` - Suffix check
  """

  require Logger

  @doc """
  Run engine operation. `op` is atom (e.g. :list_sum); `args` is list. 
  Returns result or raises on error.
  
  Automatically falls back to Elixir implementation if NIFs are not available.
  """
  def run(op, args) do
    run_with_fallback(op, args, _fallback_attempted = false)
  end

  defp run_with_fallback(op, args, fallback_attempted) do
    try do
      do_run(op, args)
    rescue
      _e in ErlangError ->
        if fallback_attempted do
          # Already tried fallback, don't retry to avoid infinite loop
          Logger.error("NIF not available for #{op} and fallback also failed")
          raise ArgumentError, "Engine operation #{inspect(op)} failed: NIF not available and fallback failed"
        else
          Logger.debug("NIF not available for #{op}, using Elixir fallback")
          # The _safe functions in Zixir.Engine.Math already handle both NIF and pure Elixir
          # implementations internally, so we can retry once with the same do_run
          run_with_fallback(op, args, true)
        end
    end
  end

  # Aggregations
  defp do_run(:list_sum, args), do: Zixir.Engine.Math.list_sum_safe(List.first(args) || [])
  defp do_run(:list_product, args), do: Zixir.Engine.Math.list_product_safe(List.first(args) || [])
  defp do_run(:list_mean, args), do: Zixir.Engine.Math.list_mean_safe(List.first(args) || [])
  defp do_run(:list_min, args), do: Zixir.Engine.Math.list_min_safe(List.first(args) || [])
  defp do_run(:list_max, args), do: Zixir.Engine.Math.list_max_safe(List.first(args) || [])
  defp do_run(:list_variance, args), do: Zixir.Engine.Math.list_variance_safe(List.first(args) || [])
  defp do_run(:list_std, args), do: Zixir.Engine.Math.list_std_safe(List.first(args) || [])

  # Vector Operations
  defp do_run(:dot_product, args) do
    a = Enum.at(args, 0) || []
    b = Enum.at(args, 1) || []
    Zixir.Engine.Math.dot_product_safe(a, b)
  end
  
  defp do_run(:vec_add, args) do
    a = Enum.at(args, 0) || []
    b = Enum.at(args, 1) || []
    Zixir.Engine.Math.vec_add_safe(a, b)
  end
  
  defp do_run(:vec_sub, args) do
    a = Enum.at(args, 0) || []
    b = Enum.at(args, 1) || []
    Zixir.Engine.Math.vec_sub_safe(a, b)
  end
  
  defp do_run(:vec_mul, args) do
    a = Enum.at(args, 0) || []
    b = Enum.at(args, 1) || []
    Zixir.Engine.Math.vec_mul_safe(a, b)
  end
  
  defp do_run(:vec_div, args) do
    a = Enum.at(args, 0) || []
    b = Enum.at(args, 1) || []
    Zixir.Engine.Math.vec_div_safe(a, b)
  end
  
  defp do_run(:vec_scale, args) do
    array = Enum.at(args, 0) || []
    scalar = Enum.at(args, 1) || 1.0
    Zixir.Engine.Math.vec_scale_safe(array, scalar)
  end

  # Transformations
  defp do_run(:map_add, args) do
    array = Enum.at(args, 0) || []
    value = Enum.at(args, 1) || 0.0
    Zixir.Engine.Math.map_add_safe(array, value)
  end
  
  defp do_run(:map_mul, args) do
    array = Enum.at(args, 0) || []
    value = Enum.at(args, 1) || 1.0
    Zixir.Engine.Math.map_mul_safe(array, value)
  end
  
  defp do_run(:filter_gt, args) do
    array = Enum.at(args, 0) || []
    threshold = Enum.at(args, 1) || 0.0
    Zixir.Engine.Math.filter_gt_safe(array, threshold)
  end
  
  defp do_run(:sort_asc, args), do: Zixir.Engine.Math.sort_asc_safe(List.first(args) || [])

  # Search
  defp do_run(:find_index, args) do
    array = Enum.at(args, 0) || []
    value = Enum.at(args, 1) || 0.0
    Zixir.Engine.Math.find_index_safe(array, value)
  end
  
  defp do_run(:count_value, args) do
    array = Enum.at(args, 0) || []
    value = Enum.at(args, 1) || 0.0
    Zixir.Engine.Math.count_value_safe(array, value)
  end

  # Matrix Operations
  defp do_run(:mat_mul, args) do
    a = Enum.at(args, 0) || []
    b = Enum.at(args, 1) || []
    a_rows = Enum.at(args, 2) || 1
    a_cols = Enum.at(args, 3) || 1
    b_cols = Enum.at(args, 4) || 1
    Zixir.Engine.Math.mat_mul_safe(a, b, a_rows, a_cols, b_cols)
  end
  
  defp do_run(:mat_transpose, args) do
    matrix = Enum.at(args, 0) || []
    rows = Enum.at(args, 1) || 1
    cols = Enum.at(args, 2) || 1
    Zixir.Engine.Math.mat_transpose_safe(matrix, rows, cols)
  end

  # String Operations
  defp do_run(:string_count, args), do: Zixir.Engine.Math.string_count_safe(List.first(args) || "")
  
  defp do_run(:string_find, args) do
    haystack = Enum.at(args, 0) || ""
    needle = Enum.at(args, 1) || ""
    Zixir.Engine.Math.string_find_safe(haystack, needle)
  end
  
  defp do_run(:string_starts_with, args) do
    string = Enum.at(args, 0) || ""
    prefix = Enum.at(args, 1) || ""
    Zixir.Engine.Math.string_starts_with_safe(string, prefix)
  end
  
  defp do_run(:string_ends_with, args) do
    string = Enum.at(args, 0) || ""
    suffix = Enum.at(args, 1) || ""
    Zixir.Engine.Math.string_ends_with_safe(string, suffix)
  end

  defp do_run(op, _args) do
    raise ArgumentError, "unknown engine op: #{inspect(op)}"
  end

  @doc """
  Check if engine NIFs are available.
  """
  def nifs_available? do
    Zixir.Engine.Math.nifs_available?()
  end

  @doc """
  Get list of all available operations.
  """
  def operations do
    [
      # Aggregations
      :list_sum, :list_product, :list_mean, :list_min, :list_max,
      :list_variance, :list_std,
      # Vector
      :dot_product, :vec_add, :vec_sub, :vec_mul, :vec_div, :vec_scale,
      # Transformations
      :map_add, :map_mul, :filter_gt, :sort_asc,
      # Search
      :find_index, :count_value,
      # Matrix
      :mat_mul, :mat_transpose,
      # String
      :string_count, :string_find, :string_starts_with, :string_ends_with
    ]
  end
end
