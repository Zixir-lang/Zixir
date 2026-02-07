defmodule ZixirWeb.QueryController do
  use ZixirWeb, :controller

  def index(conn, _params) do
    conn = if conn.assigns[:htmx_request], do: put_layout(conn, false), else: conn
    render(conn, :index)
  end
end
