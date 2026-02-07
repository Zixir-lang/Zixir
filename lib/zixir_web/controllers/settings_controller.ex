defmodule ZixirWeb.SettingsController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    layout = if conn.assigns[:htmx_request], do: false, else: {ZixirWeb.LayoutView, "app.html"}
    conn
    |> put_view(ZixirWeb.SettingsView)
    |> render("index.html", layout: layout)
  end
end
