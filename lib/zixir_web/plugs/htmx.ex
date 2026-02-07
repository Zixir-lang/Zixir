defmodule ZixirWeb.Plugs.HTMX do
  @moduledoc """
  Detects HTMX requests and sets conn.assigns[:htmx_request] so controllers
  can render fragment-only (no layout) when content is swapped into #main-content.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    htmx? = get_req_header(conn, "hx-request") == ["true"]
    assign(conn, :htmx_request, htmx?)
  end
end
