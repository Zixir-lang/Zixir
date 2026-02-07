defmodule ZixirWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :zixir

  plug Plug.Static,
    at: "/",
    from: :zixir,
    gzip: false,
    only: ~w(css js images)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head

  plug ZixirWeb.Router
end
