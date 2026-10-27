defmodule Roadrunner.PlugTest do
  use ExUnit.Case, async: false

  alias Roadrunner.Plug.TestPlug

  @file_body "abcdefgh"

  setup_all do
    {:ok, _} = Application.ensure_all_started(:inets)
    :ok
  end

  setup do
    file =
      Path.join(System.tmp_dir!(), "roadrunner_plug_test_#{System.unique_integer([:positive])}")

    File.write!(file, @file_body)
    on_exit(fn -> File.rm(file) end)

    name = :"roadrunner_plug_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Roadrunner.Plug, plug: {TestPlug, report: self(), file: file}, port: 0, name: name}
    )

    {:ok, port: Roadrunner.Plug.port(name)}
  end

  test "sends a response with the plug's headers", %{port: port} do
    {200, headers, "hello"} = get(port, "/hello")
    assert {~c"x-test", ~c"1"} in headers
  end

  test "reads the request body", %{port: port} do
    assert {200, _, "some body"} = post(port, "/echo", "some body")
  end

  test "a body over roadrunner's default 10 MB cap reaches the plug", %{port: port} do
    size = 11 * 1024 * 1024
    assert {200, _, body} = post(port, "/size", :binary.copy("a", size))
    assert body == Integer.to_string(size)
  end

  @tag :capture_log
  test "an explicit max_content_length still caps the body" do
    name = :"roadrunner_plug_capped_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Roadrunner.Plug,
       plug: TestPlug, port: 0, name: name, roadrunner: %{max_content_length: 4}},
      id: :capped
    )

    assert {413, _, _} = post(Roadrunner.Plug.port(name), "/size", "too long")
  end

  test "reads the body in pieces of the asked length", %{port: port} do
    assert {200, _, "3"} = post(port, "/pieces", "0123456789")
  end

  test "streams a chunked response", %{port: port} do
    assert {200, _, "one-two"} = get(port, "/chunked")
  end

  test "sends a file range", %{port: port} do
    assert {200, _, "cdef"} = get(port, "/file")
  end

  test "sends a whole file", %{port: port} do
    assert {200, _, @file_body} = get(port, "/whole-file")
  end

  test "sends a response the plug only set", %{port: port} do
    assert {201, _, "set"} = get(port, "/set-only")
  end

  @tag :capture_log
  test "a plug that sends nothing is a 500", %{port: port} do
    assert {500, _, _} = get(port, "/nothing")
  end

  test "sends 103 Early Hints before the response", %{port: port} do
    response = raw(port, "GET /hints HTTP/1.1\r\nhost: x\r\nconnection: close\r\n\r\n")
    assert response =~ ~r/\AHTTP\/1.1 103 .*\r\nlink: <\/a.css>; rel=preload\r\n/s
    assert response =~ "HTTP/1.1 200 OK"
    assert String.ends_with?(response, "after hints")
  end

  test "builds the conn from the request", %{port: port} do
    {200, _, "ok"} = get(port, "/info?a=1&b=2", [{~c"x-custom", ~c"yes"}])
    assert_receive {:info, info}

    assert %{
             method: "GET",
             host: "127.0.0.1",
             port: ^port,
             scheme: :http,
             path_info: ["info"],
             request_path: "/info",
             query_string: "a=1&b=2",
             remote_ip: {127, 0, 0, 1},
             http_protocol: :"HTTP/1.1",
             ssl_data: nil
           } = info

    assert {"x-custom", "yes"} in info.req_headers
    assert %{address: {127, 0, 0, 1}, ssl_cert: nil} = info.peer_data
    assert info.sock_data == %{address: {127, 0, 0, 1}, port: port}
  end

  describe "WebSocket" do
    test "echoes through a WebSock handler", %{port: port} do
      sock = ws_connect(port)
      :ok = :gen_tcp.send(sock, masked(0x81, "hi"))
      assert {:text, "hi"} = recv_frame(sock)
    end

    test "pushes several frames and handle_info output", %{port: port} do
      sock = ws_connect(port)
      :ok = :gen_tcp.send(sock, masked(0x81, "push"))
      assert {:text, "a"} = recv_frame(sock)
      assert {:text, "b"} = recv_frame(sock)
    end

    test "stops with frames and a close, reporting terminate", %{port: port} do
      sock = ws_connect(port)
      :ok = :gen_tcp.send(sock, masked(0x81, "stop"))
      assert {:text, "last"} = recv_frame(sock)
      assert {:close, <<1000::16, "bye">>} = recv_frame(sock)
      assert_receive {:terminated, :normal}
    end

    test "an abnormal stop closes 1011 and reports the error", %{port: port} do
      sock = ws_connect(port)
      :ok = :gen_tcp.send(sock, masked(0x81, "crash-stop"))
      assert {:close, <<1011::16>>} = recv_frame(sock)
      assert_receive {:terminated, {:error, :oops}}
    end

    test "a restart stop closes 1012", %{port: port} do
      sock = ws_connect(port)
      :ok = :gen_tcp.send(sock, masked(0x81, "restart"))
      assert {:close, <<1012::16>>} = recv_frame(sock)
      assert_receive {:terminated, :normal}
    end

    test "handle_control sees a ping after the server's pong", %{port: port} do
      sock = ws_connect(port)
      :ok = :gen_tcp.send(sock, masked(0x89, "p"))
      assert {:pong, "p"} = recv_frame(sock)
      assert_receive {:control, :ping, "p"}
    end

    test "a client close reports remote", %{port: port} do
      sock = ws_connect(port)
      :ok = :gen_tcp.send(sock, masked(0x88, <<1000::16>>))
      assert {:close, <<1000::16>>} = recv_frame(sock)
      assert_receive {:terminated, :remote}
    end
  end

  # --- helpers ---

  defp get(port, path, headers \\ []) do
    request(:get, {url(port, path), headers})
  end

  defp post(port, path, body) do
    request(:post, {url(port, path), [], ~c"text/plain", body})
  end

  defp request(method, request) do
    {:ok, {{_, status, _}, headers, body}} =
      :httpc.request(method, request, [], body_format: :binary)

    {status, headers, body}
  end

  defp url(port, path), do: ~c"http://127.0.0.1:#{port}#{path}"

  defp raw(port, request) do
    {:ok, sock} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    :ok = :gen_tcp.send(sock, request)
    recv_all(sock, "")
  end

  defp recv_all(sock, acc) do
    case :gen_tcp.recv(sock, 0, 5000) do
      {:ok, data} -> recv_all(sock, acc <> data)
      {:error, :closed} -> acc
    end
  end

  defp ws_connect(port) do
    {:ok, sock} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

    :ok =
      :gen_tcp.send(sock, [
        "GET /ws HTTP/1.1\r\nhost: x\r\nupgrade: websocket\r\nconnection: Upgrade\r\n",
        "sec-websocket-key: dGhlIHNhbXBsZSBub25jZQ==\r\nsec-websocket-version: 13\r\n\r\n"
      ])

    {:ok, "HTTP/1.1 101" <> _} = recv_head(sock, "")
    sock
  end

  defp recv_head(sock, acc) do
    case :binary.match(acc, "\r\n\r\n") do
      :nomatch ->
        {:ok, data} = :gen_tcp.recv(sock, 0, 5000)
        recv_head(sock, acc <> data)

      _ ->
        {:ok, acc}
    end
  end

  defp recv_frame(sock) do
    {:ok, <<_fin::1, _rsv::3, opcode::4, 0::1, len::7>>} = :gen_tcp.recv(sock, 2, 5000)
    {:ok, payload} = if len == 0, do: {:ok, ""}, else: :gen_tcp.recv(sock, len, 5000)
    {opcode(opcode), payload}
  end

  defp opcode(0x1), do: :text
  defp opcode(0x8), do: :close
  defp opcode(0xA), do: :pong

  defp masked(op, payload) do
    key = <<1, 2, 3, 4>>
    mask = :binary.copy(key, div(byte_size(payload), 4) + 1) |> binary_part(0, byte_size(payload))
    <<op, 0x80 + byte_size(payload), key::binary, :crypto.exor(payload, mask)::binary>>
  end
end
