defmodule Zixir.Python.Protocol do
  @moduledoc """
  Enhanced wire format between Elixir and Python.
  Supports numpy arrays, pandas DataFrames, and efficient binary serialization.
  """

  @doc """
  Encode request: module, function, args, kwargs -> JSON line (binary).
  """
  def encode_request(module, function, args, kwargs \\ []) do
    map = %{
      "m" => to_string(module),
      "f" => to_string(function),
      "a" => elixir_to_wire(args)
    }
    
    # Add kwargs if present
    map = if length(kwargs) > 0 do
      Map.put(map, "k", Enum.into(kwargs, %{}))
    else
      map
    end
    
    Jason.encode!(map) <> "\n"
  end

  @doc """
  Encode a special command (ping, health check, etc.)
  """
  def encode_command(cmd) when is_atom(cmd) do
    Jason.encode!(%{"cmd" => to_string(cmd)}) <> "\n"
  end

  @doc """
  Decode response line (binary) -> {:ok, term} or {:error, reason}.
  """
  def decode_response(line) when is_binary(line) do
    line = String.trim(line)
    if line == "" do
      {:error, :empty_line}
    else
      case Jason.decode(line) do
        {:ok, %{"ok" => value}} -> {:ok, wire_to_elixir(value)}
        {:ok, %{"error" => reason}} -> {:error, to_string(reason)}
        {:ok, %{"ready" => true} = info} -> {:ok, {:ready, info}}
        {:ok, _} -> {:error, :invalid_response}
        {:error, _} -> Zixir.Errors.decode_failed()
      end
    end
  end

  # Elixir to wire format conversion
  defp elixir_to_wire(list) when is_list(list) do
    # Check if this is a numeric array that could be encoded efficiently
    if numeric_array?(list) do
      encode_numeric_array(list)
    else
      Enum.map(list, &elixir_to_wire/1)
    end
  end
  
  defp elixir_to_wire(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), elixir_to_wire(v)} end)
  end
  
  defp elixir_to_wire(bin) when is_binary(bin) do
    # Check if binary is actually bytes (contains non-printable chars)
    if String.printable?(bin) do
      bin
    else
      %{"__bytes__" => Base.encode64(bin)}
    end
  end
  
  defp elixir_to_wire(atom) when is_atom(atom) do
    if atom == nil do
      nil
    else
      to_string(atom)
    end
  end
  
  defp elixir_to_wire(num) when is_number(num), do: num
  defp elixir_to_wire(nil), do: nil
  defp elixir_to_wire(other), do: other

  # Wire to Elixir conversion
  defp wire_to_elixir(%{"__numpy_array__" => arr_info}) do
    decode_numpy_array(arr_info)
  end
  
  defp wire_to_elixir(%{"__pandas_df__" => df_info}) do
    decode_pandas_df(df_info)
  end
  
  defp wire_to_elixir(%{"__bytes__" => b64}) do
    Base.decode64!(b64)
  end
  
  defp wire_to_elixir(list) when is_list(list) do
    Enum.map(list, &wire_to_elixir/1)
  end
  
  defp wire_to_elixir(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, wire_to_elixir(v)} end)
  end
  
  defp wire_to_elixir(other), do: other

  # Helper functions for numeric array encoding
  defp numeric_array?([]), do: false
  defp numeric_array?(list) when is_list(list) do
    Enum.all?(list, fn x -> is_number(x) or (is_list(x) and numeric_array?(x)) end)
  end
  defp numeric_array?(_), do: false

  defp encode_numeric_array(list) do
    # Flatten nested lists and encode as numpy-compatible format
    flat_list = List.flatten(list)
    shape = get_shape(list)
    
    # Determine best dtype
    has_float = Enum.any?(flat_list, &is_float/1)
    dtype = if has_float, do: "f64", else: "i64"
    
    # Pack binary data
    data = if has_float do
      Enum.map(flat_list, &:erlang.float_to_binary(&1, [:compact, decimals: 17])) |> IO.iodata_to_binary()
    else
      Enum.map(flat_list, &:erlang.term_to_binary(&1, [:compressed])) |> IO.iodata_to_binary()
    end
    
    %{"__numpy_array__" => %{
      "dtype" => dtype,
      "shape" => shape,
      "data" => Base.encode64(data)
    }}
  end

  defp get_shape(list) when is_list(list) do
    if length(list) > 0 and is_list(hd(list)) do
      [length(list) | get_shape(hd(list))]
    else
      [length(list)]
    end
  end
  defp get_shape(_), do: []

  @doc """
  Decode numpy array info from Python to Elixir list.
  """
  def decode_numpy_array(arr_info) when is_map(arr_info) do
    dtype = arr_info["dtype"]
    shape = arr_info["shape"]
    data = Base.decode64!(arr_info["data"])
    
    # Decode based on dtype
    values = case dtype do
      "f64" -> decode_float64_array(data)
      "f32" -> decode_float32_array(data)
      "i64" -> decode_int64_array(data)
      "i32" -> decode_int32_array(data)
      _ -> decode_float64_array(data)
    end
    
    # Reshape if needed
    reshape_if_needed(values, shape)
  end

  defp decode_float64_array(data) do
    # 8 bytes per float64
    for <<value::native-float-64 <- data>>, do: value
  end

  defp decode_float32_array(data) do
    # 4 bytes per float32
    for <<value::native-float-32 <- data>>, do: value
  end

  defp decode_int64_array(data) do
    for <<value::native-signed-64 <- data>>, do: value
  end

  defp decode_int32_array(data) do
    for <<value::native-signed-32 <- data>>, do: value
  end

  defp reshape_if_needed(values, [_dim1]) do
    # 1D array - already correct shape
    values
  end
  
  defp reshape_if_needed(values, [_rows, _cols]) do
    # 2D array - chunk into rows
    values
    |> length()
    |> then(&Enum.chunk_every(values, &1))
  end
  
  defp reshape_if_needed(values, [_d1, d2, d3]) do
    # 3D array
    values
    |> Enum.chunk_every(d2 * d3)
    |> Enum.map(&Enum.chunk_every(&1, d3))
  end
  
  defp reshape_if_needed(values, _), do: values

  defp decode_pandas_df(df_info) do
    data = decode_numpy_array(df_info["data"])
    columns = df_info["columns"]
    
    # Return as map with column names
    Enum.zip(columns, transpose_matrix(data))
    |> Enum.into(%{})
  end

  defp transpose_matrix(matrix) when is_list(matrix) and length(matrix) > 0 do
    if is_list(hd(matrix)) do
      # 2D matrix
      cols = length(hd(matrix))
      for col_idx <- 0..(cols - 1) do
        Enum.map(matrix, &Enum.at(&1, col_idx))
      end
    else
      # 1D - treat as single column
      [matrix]
    end
  end
  defp transpose_matrix(matrix), do: matrix
end
