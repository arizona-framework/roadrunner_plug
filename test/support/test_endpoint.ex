defmodule Roadrunner.Plug.TestEndpoint do
  @moduledoc false
  # A Phoenix endpoint served by `Roadrunner.PhoenixAdapter`; its config is
  # set by the test before it starts.

  use Phoenix.Endpoint, otp_app: :roadrunner_plug

  socket("/socket", Roadrunner.Plug.TestSocket, websocket: [check_origin: false])

  plug(Plug.Parsers, parsers: [:urlencoded], pass: ["*/*"])
  plug(:respond)

  defp respond(%{path_info: ["hello"]} = conn, _opts) do
    conn |> put_resp_content_type("text/plain") |> send_resp(200, "hello from phoenix")
  end

  defp respond(%{path_info: ["form"]} = conn, _opts) do
    send_resp(conn, 200, conn.body_params["name"])
  end
end
