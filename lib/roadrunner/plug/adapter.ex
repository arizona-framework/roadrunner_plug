defmodule Roadrunner.Plug.Adapter do
  @moduledoc false
  # The `Plug.Conn.Adapter` over a roadrunner request. The plug runs inside
  # a `{send, ...}` response's fun (`Roadrunner.Plug.Handler`), so each
  # callback sends with `:roadrunner_send` as the plug calls it. The payload
  # carries the latest request (a body read moves it on) and, once a chunked
  # response starts, its `Send` fun.

  @behaviour Plug.Conn.Adapter

  @already_sent {:plug_conn, :sent}

  @doc "The `%Plug.Conn{}` for a roadrunner request."
  @spec conn(:roadrunner_req.request()) :: Plug.Conn.t()
  def conn(req) do
    scheme = :roadrunner_req.scheme(req)
    {host, port} = host_port(:roadrunner_req.header("host", req), scheme)
    path = :roadrunner_req.path(req)

    %Plug.Conn{
      adapter: {__MODULE__, %{req: req, send: nil}},
      host: host,
      method: :roadrunner_req.method(req),
      owner: self(),
      path_info: String.split(path, "/", trim: true),
      port: port,
      query_string: :roadrunner_req.qs(req),
      remote_ip: :roadrunner_req.client_ip(req) || {0, 0, 0, 0},
      req_headers: :roadrunner_req.headers(req),
      request_path: path,
      scheme: scheme
    }
  end

  @doc "The request the plug left, for the send fun to return."
  @spec request(Plug.Conn.t()) :: :roadrunner_req.request()
  def request(%Plug.Conn{adapter: {__MODULE__, %{req: req}}}), do: req

  @doc "Drop the `{:plug_conn, :sent}` Plug sends the owner per response."
  @spec flush_sent() :: :ok
  def flush_sent do
    receive do
      @already_sent -> flush_sent()
    after
      0 -> :ok
    end
  end

  defp host_port(:undefined, scheme), do: {"", default_port(scheme)}

  defp host_port(host, scheme) do
    case URI.parse("//" <> host) do
      %URI{host: h, port: nil} when is_binary(h) -> {h, default_port(scheme)}
      %URI{host: h, port: p} when is_binary(h) -> {h, p}
      _ -> {host, default_port(scheme)}
    end
  end

  defp default_port(:http), do: 80
  defp default_port(:https), do: 443

  @impl true
  def send_resp(%{req: req} = payload, status, headers, body) do
    _ = :roadrunner_send.reply(status, headers, body, req)
    {:ok, nil, payload}
  end

  @impl true
  def send_file(%{req: req} = payload, status, headers, path, offset, length) do
    length =
      case length do
        :all -> File.stat!(path).size - offset
        n when is_integer(n) -> n
      end

    headers = with_content_length(headers, length)
    _ = :roadrunner_send.file(status, headers, {path, offset, length}, req)
    {:ok, nil, payload}
  end

  defp with_content_length(headers, length) do
    case List.keymember?(headers, "content-length", 0) do
      true -> headers
      false -> [{"content-length", Integer.to_string(length)} | headers]
    end
  end

  @impl true
  def send_chunked(%{req: req} = payload, status, headers) do
    case :roadrunner_send.stream(status, headers, req) do
      {:ok, send} -> {:ok, nil, %{payload | send: send}}
      {:error, _reason} -> {:ok, nil, payload}
    end
  end

  @impl true
  def chunk(%{send: nil}, _body), do: {:error, :closed}
  def chunk(%{send: send}, body), do: send.(body, :nofin)

  @impl true
  def read_req_body(%{req: req} = payload, opts) do
    length = Keyword.get(opts, :length, 8_000_000)

    case :roadrunner_req.read_body(req, %{length: length}) do
      {:ok, data, req} -> {:ok, IO.iodata_to_binary(data), %{payload | req: req}}
      {:more, data, req} -> {:more, IO.iodata_to_binary(data), %{payload | req: req}}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def inform(%{req: req}, status, headers) do
    headers = for {name, value} <- headers, do: {to_string(name), to_string(value)}

    case :roadrunner_send.inform(status, headers, req) do
      :ok -> :ok
      {:error, _reason} -> {:error, :not_supported}
    end
  end

  @impl true
  def upgrade(%{req: req} = payload, :websocket, {websock, state, opts}) do
    case :roadrunner_req.version(req) do
      {1, _minor} ->
        # A handshake roadrunner refuses is answered (400/426) already, so
        # the conn is done either way.
        _ =
          :roadrunner_send.websocket(
            Roadrunner.Plug.WebSock,
            {websock, state},
            Roadrunner.Plug.WebSock.upgrade_opts(opts),
            req
          )

        {:ok, payload}

      _http2_or_http3 ->
        {:error, :not_supported}
    end
  end

  def upgrade(_payload, _protocol, _args), do: {:error, :not_supported}

  @impl true
  def push(_payload, _path, _headers), do: {:error, :not_supported}

  @impl true
  def get_peer_data(%{req: req}) do
    {address, port} =
      case :roadrunner_req.peer(req) do
        {_address, _port} = peer -> peer
        :undefined -> {{0, 0, 0, 0}, 0}
      end

    ssl_cert =
      case :roadrunner_req.peercert(req) do
        {:ok, der} -> der
        {:error, _reason} -> nil
      end

    %{address: address, port: port, ssl_cert: ssl_cert}
  end

  @impl true
  def get_sock_data(%{req: req}) do
    case :roadrunner_req.sockname(req) do
      {:ok, {address, port}} -> %{address: address, port: port}
      {:error, _reason} -> %{address: {0, 0, 0, 0}, port: 0}
    end
  end

  @impl true
  def get_ssl_data(%{req: req}) do
    case :roadrunner_req.tls_info(req) do
      {:ok, info} -> info
      {:error, _reason} -> nil
    end
  end

  @impl true
  def get_http_protocol(%{req: req}) do
    case :roadrunner_req.version(req) do
      {1, 1} -> :"HTTP/1.1"
      {1, 0} -> :"HTTP/1"
      {2, 0} -> :"HTTP/2"
      {3, 0} -> :"HTTP/3"
    end
  end
end
