defmodule ZixirWeb.ErrorView do
  use Phoenix.View, root: "lib/zixir_web/templates", namespace: ZixirWeb

  def render("404.html", _assigns) do
    "Page not found"
  end

  def render("500.html", _assigns) do
    "Internal server error"
  end

  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
