defmodule ZixirWeb do
  @moduledoc """
  Zixir Web Dashboard - Phoenix + HTMX + Tailwind
  """

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  def controller do
    quote do
      use Phoenix.Controller, namespace: ZixirWeb
      import Plug.Conn
      alias ZixirWeb.Router.Helpers, as: Routes
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/zixir_web/templates",
        namespace: ZixirWeb
      import Phoenix.View
      alias ZixirWeb.Router.Helpers, as: Routes
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end
end
