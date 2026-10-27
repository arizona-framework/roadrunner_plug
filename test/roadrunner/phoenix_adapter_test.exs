defmodule Roadrunner.PhoenixAdapterTest do
  use ExUnit.Case, async: false

  alias Roadrunner.Plug.TestEndpoint

  setup_all do
    Application.put_env(:roadrunner_plug, TestEndpoint,
      adapter: Roadrunner.PhoenixAdapter,
      http: [ip: {127, 0, 0, 1}, port: 0],
      server: true,
      secret_key_base: String.duplicate("a", 64),
      pubsub_server: Roadrunner.Plug.TestPubSub
    )

    start_supervised!({Phoenix.PubSub, name: Roadrunner.Plug.TestPubSub})
    start_supervised!(TestEndpoint)
    {:ok, {_ip, port}} = TestEndpoint.server_info(:http)
    {:ok, port: port}
  end

  test "reports where it listens", %{port: port} do
    assert {:ok, {{127, 0, 0, 1}, ^port}} = TestEndpoint.server_info(:http)
    assert port > 0
    assert {:error, :no_server_found} = TestEndpoint.server_info(:https)
  end

  test "serves the endpoint's plugs", %{port: port} do
    {:ok, {{_, 200, _}, headers, body}} =
      :httpc.request(:get, {~c"http://127.0.0.1:#{port}/hello", []}, [], body_format: :binary)

    assert body == "hello from phoenix"
    assert {~c"content-type", ~c"text/plain; charset=utf-8"} in headers
  end

  test "parses a form body through Plug.Parsers", %{port: port} do
    request =
      {~c"http://127.0.0.1:#{port}/form", [], ~c"application/x-www-form-urlencoded",
       "name=roadrunner"}

    assert {:ok, {{_, 200, _}, _, "roadrunner"}} =
             :httpc.request(:post, request, [], body_format: :binary)
  end

  test "runs a channel over the socket's WebSocket", %{port: port} do
    {:ok, sock} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

    :ok =
      :gen_tcp.send(sock, [
        "GET /socket/websocket?vsn=2.0.0 HTTP/1.1\r\nhost: x\r\n",
        "upgrade: websocket\r\nconnection: Upgrade\r\n",
        "sec-websocket-key: dGhlIHNhbXBsZSBub25jZQ==\r\nsec-websocket-version: 13\r\n\r\n"
      ])

    assert {:ok, "HTTP/1.1 101" <> _} = recv_head(sock, "")

    send_message(sock, ["1", "1", "room:lobby", "phx_join", %{}])

    assert ["1", "1", "room:lobby", "phx_reply", %{"status" => "ok", "response" => %{}}] =
             recv_message(sock)

    send_message(sock, ["1", "2", "room:lobby", "ping", %{"n" => 1}])

    # The channel pushes before it replies.
    assert ["1", nil, "room:lobby", "pushed", %{"n" => 1}] = recv_message(sock)

    assert ["1", "2", "room:lobby", "phx_reply", %{"status" => "ok", "response" => %{"n" => 1}}] =
             recv_message(sock)
  end

  defp recv_head(sock, acc) do
    case :binary.match(acc, "\r\n\r\n") do
      {_pos, _len} ->
        {:ok, acc}

      :nomatch ->
        {:ok, data} = :gen_tcp.recv(sock, 0, 5000)
        recv_head(sock, acc <> data)
    end
  end

  # A masked text frame, as a client sends.
  defp send_message(sock, message) do
    payload = Jason.encode!(message)
    key = <<1, 2, 3, 4>>
    mask = :binary.copy(key, div(byte_size(payload), 4) + 1) |> binary_part(0, byte_size(payload))
    :ok = :gen_tcp.send(sock, [0x81, 0x80 + byte_size(payload), key, :crypto.exor(payload, mask)])
  end

  defp recv_message(sock) do
    {:ok, <<1::1, 0::3, 0x1::4, 0::1, len::7>>} = :gen_tcp.recv(sock, 2, 5000)

    len =
      case len do
        126 ->
          {:ok, <<extended::16>>} = :gen_tcp.recv(sock, 2, 5000)
          extended

        short ->
          short
      end

    {:ok, payload} = :gen_tcp.recv(sock, len, 5000)
    Jason.decode!(payload)
  end
end
