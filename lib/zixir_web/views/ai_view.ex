defmodule ZixirWeb.AIView do
  use Phoenix.View, root: "lib/zixir_web/templates", namespace: ZixirWeb

  # Helper functions for AI views
  def format_currency(amount) when is_number(amount) do
    :erlang.float_to_binary(amount / 1, decimals: 2)
  end

  def format_currency(_), do: "0.00"

  def format_number(num) when is_integer(num) do
    Integer.to_string(num)
  end

  def format_number(_), do: "0"
end
