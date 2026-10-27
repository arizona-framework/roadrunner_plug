defmodule Roadrunner.Plug.HTTP2Test do
  use ExUnit.Case, async: false

  alias Roadrunner.Plug.TestPlug

  @file_body "abcdefgh"

  setup do
    file =
      Path.join(System.tmp_dir!(), "roadrunner_plug_h2_#{System.unique_integer([:positive])}")

    File.write!(file, @file_body)
    on_exit(fn -> File.rm(file) end)

    name = :"roadrunner_plug_h2_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Roadrunner.Plug,
       plug: {TestPlug, report: self(), file: file},
       port: 0,
       name: name,
       roadrunner: %{protocols: [:http2]}}
    )

    {:ok, port: Roadrunner.Plug.port(name)}
  end

  test "sends a response with the plug's headers", %{port: port} do
    c = port |> open() |> send_headers(1, "GET", "/hello", true)
    assert {[{200, headers}], "hello", _c} = response(c, 1)
    assert {"x-test", "1"} in headers
  end

  test "lowercases a header name the plug set in uppercase", %{port: port} do
    # HTTP/2 field names must be lowercase (RFC 9113 §8.2.1).
    c = port |> open() |> send_headers(1, "GET", "/upper", true)
    assert {[{200, headers}], "upper", _c} = response(c, 1)
    assert {"x-upper", "1"} in headers
  end

  test "reads the request body", %{port: port} do
    c = port |> open() |> send_headers(1, "POST", "/echo", false)
    c = send_data(c, 1, "some ", false)
    c = send_data(c, 1, "body", true)
    assert {[{200, _}], "some body", _c} = response(c, 1)
  end

  test "streams a chunked response", %{port: port} do
    c = port |> open() |> send_headers(1, "GET", "/chunked", true)
    assert {[{200, _}], "one-two", _c} = response(c, 1)
  end

  test "sends a file range", %{port: port} do
    c = port |> open() |> send_headers(1, "GET", "/file", true)
    assert {[{200, headers}], "cdef", _c} = response(c, 1)
    assert {"content-length", "4"} in headers
  end

  test "sends 103 Early Hints before the response", %{port: port} do
    c = port |> open() |> send_headers(1, "GET", "/hints", true)
    assert {[{103, hints}, {200, _}], "after hints", _c} = response(c, 1)
    assert {"link", "</a.css>; rel=preload"} in hints
  end

  test "reports HTTP/2 as the conn's protocol", %{port: port} do
    c = port |> open() |> send_headers(1, "GET", "/info", true)
    assert {[{200, _}], "ok", _c} = response(c, 1)
    assert_receive {:info, %{http_protocol: :"HTTP/2", scheme: :http, path_info: ["info"]}}
  end

  test "serves several streams on one connection", %{port: port} do
    c = port |> open() |> send_headers(1, "GET", "/hello", true)
    {[{200, _}], "hello", c} = response(c, 1)
    c = send_headers(c, 3, "GET", "/chunked", true)
    assert {[{200, _}], "one-two", _c} = response(c, 3)
  end

  @tag :capture_log
  test "a WebSocket upgrade is answered 500, as the adapter does not support it", %{port: port} do
    # `upgrade_adapter/3` raises ArgumentError; its Plug status is 500, sent
    # before roadrunner logs the crash.
    c = port |> open() |> send_headers(1, "GET", "/ws", true)
    assert {[{500, _}], _body, _c} = response(c, 1)
  end

  # --- helpers ---

  defp open(port) do
    {:ok, sock} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5000)

    :ok =
      :gen_tcp.send(sock, [
        "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n",
        :roadrunner_http2_frame.encode({:settings, 0, []})
      ])

    %{
      sock: sock,
      buf: "",
      enc: :roadrunner_http2_hpack.new_encoder(4096),
      dec: :roadrunner_http2_hpack.new_decoder(4096)
    }
  end

  defp send_headers(%{sock: sock, enc: enc} = c, stream_id, method, path, end_stream?) do
    fields = [
      {":method", method},
      {":scheme", "http"},
      {":authority", "127.0.0.1"},
      {":path", path}
    ]

    {block, enc} = :roadrunner_http2_hpack.encode(fields, enc)
    # END_HEADERS, plus END_STREAM when there is no body.
    flags = if end_stream?, do: 0x05, else: 0x04
    frame = :roadrunner_http2_frame.encode({:headers, stream_id, flags, :undefined, block})
    :ok = :gen_tcp.send(sock, frame)
    %{c | enc: enc}
  end

  defp send_data(%{sock: sock} = c, stream_id, data, end_stream?) do
    flags = if end_stream?, do: 0x01, else: 0x00
    :ok = :gen_tcp.send(sock, :roadrunner_http2_frame.encode({:data, stream_id, flags, data}))
    c
  end

  # Stream `stream_id`'s `{status, headers}` blocks in order (1xx ones
  # first) and its body, up to END_STREAM.
  defp response(c, stream_id), do: response(c, stream_id, [], "")

  defp response(c, stream_id, heads, body) do
    case next_frame(c) do
      {{:headers, ^stream_id, flags, headers}, c} ->
        {_, status} = List.keyfind(headers, ":status", 0)
        heads = heads ++ [{String.to_integer(status), headers}]

        case Bitwise.band(flags, 0x01) do
          0 -> response(c, stream_id, heads, body)
          _ -> {heads, body, c}
        end

      {{:data, ^stream_id, flags, data, _}, c} ->
        body = body <> data

        case Bitwise.band(flags, 0x01) do
          0 -> response(c, stream_id, heads, body)
          _ -> {heads, body, c}
        end

      {{:rst_stream, ^stream_id, code}, _c} ->
        flunk("stream #{stream_id} reset: #{inspect(code)}")

      {_other, c} ->
        response(c, stream_id, heads, body)
    end
  end

  defp next_frame(%{sock: sock, buf: buf, dec: dec} = c) do
    case :roadrunner_http2_frame.parse(buf, 16384) do
      {:ok, {:headers, stream_id, flags, _priority, block}, rest} ->
        {:ok, headers, dec} = :roadrunner_http2_hpack.decode(block, dec)
        {{:headers, stream_id, flags, headers}, %{c | buf: rest, dec: dec}}

      {:ok, frame, rest} ->
        {frame, %{c | buf: rest}}

      _more ->
        {:ok, data} = :gen_tcp.recv(sock, 0, 5000)
        next_frame(%{c | buf: buf <> data})
    end
  end
end
