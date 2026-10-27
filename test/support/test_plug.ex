defmodule Roadrunner.Plug.TestPlug do
  @moduledoc false
  # The plug the tests serve: one path per behaviour, reporting to the
  # `:report` pid where a test needs to see inside.

  import Plug.Conn

  def init(opts), do: opts

  def call(%{path_info: ["hello"]} = conn, _opts) do
    conn |> put_resp_header("x-test", "1") |> send_resp(200, "hello")
  end

  def call(%{path_info: ["echo"]} = conn, _opts) do
    {:ok, body, conn} = read_all(conn, "")
    send_resp(conn, 200, body)
  end

  def call(%{path_info: ["size"]} = conn, _opts) do
    {:ok, body, conn} = read_all(conn, "")
    send_resp(conn, 200, Integer.to_string(byte_size(body)))
  end

  def call(%{path_info: ["pieces"]} = conn, _opts) do
    # 4 bytes per read: the adapter hands the body over in pieces.
    {:ok, reads, conn} = count_reads(conn, 0)
    send_resp(conn, 200, Integer.to_string(reads))
  end

  def call(%{path_info: ["chunked"]} = conn, _opts) do
    conn = send_chunked(conn, 200)
    {:ok, conn} = chunk(conn, "one-")
    {:ok, conn} = chunk(conn, "")
    {:ok, conn} = chunk(conn, "two")
    conn
  end

  def call(%{path_info: ["file"]} = conn, opts) do
    send_file(conn, 200, Keyword.fetch!(opts, :file), 2, 4)
  end

  def call(%{path_info: ["whole-file"]} = conn, opts) do
    send_file(conn, 200, Keyword.fetch!(opts, :file))
  end

  def call(%{path_info: ["set-only"]} = conn, _opts) do
    resp(conn, 201, "set")
  end

  def call(%{path_info: ["nothing"]} = conn, _opts), do: conn

  def call(%{path_info: ["upper"]} = conn, _opts) do
    # Plug only checks header case in tests: set one as production code may.
    %{conn | resp_headers: [{"X-Upper", "1"} | conn.resp_headers]} |> send_resp(200, "upper")
  end

  def call(%{path_info: ["hints"]} = conn, _opts) do
    conn
    |> inform(103, [{"link", "</a.css>; rel=preload"}])
    |> send_resp(200, "after hints")
  end

  def call(%{path_info: ["info"]} = conn, opts) do
    send(Keyword.fetch!(opts, :report), {:info, info(conn)})
    send_resp(conn, 200, "ok")
  end

  def call(%{path_info: ["ws"]} = conn, opts) do
    upgrade_adapter(
      conn,
      :websocket,
      {Roadrunner.Plug.TestWebSock, Keyword.fetch!(opts, :report), [timeout: 60_000]}
    )
  end

  defp info(conn) do
    %{
      method: conn.method,
      host: conn.host,
      port: conn.port,
      scheme: conn.scheme,
      path_info: conn.path_info,
      request_path: conn.request_path,
      query_string: conn.query_string,
      remote_ip: conn.remote_ip,
      req_headers: conn.req_headers,
      http_protocol: get_http_protocol(conn),
      peer_data: get_peer_data(conn),
      sock_data: get_sock_data(conn),
      ssl_data: get_ssl_data(conn)
    }
  end

  defp read_all(conn, acc) do
    case read_body(conn, length: 64_000_000) do
      {:ok, data, conn} -> {:ok, acc <> data, conn}
      {:more, data, conn} -> read_all(conn, acc <> data)
    end
  end

  defp count_reads(conn, n) do
    case read_body(conn, length: 4) do
      {:ok, _data, conn} -> {:ok, n + 1, conn}
      {:more, _data, conn} -> count_reads(conn, n + 1)
    end
  end
end

defmodule Roadrunner.Plug.TestWebSock do
  @moduledoc false
  # A WebSock handler that echoes text, answers "push" with two frames,
  # stops on "stop", and reports `terminate/2` to its pid.

  @behaviour WebSock

  @impl true
  def init(report), do: {:ok, report}

  @impl true
  def handle_in({"push", opcode: :text}, report) do
    {:push, [{:text, "a"}, {:text, "b"}], report}
  end

  def handle_in({"stop", opcode: :text}, report) do
    {:stop, :normal, {1000, "bye"}, [{:text, "last"}], report}
  end

  def handle_in({"restart", opcode: :text}, report) do
    {:stop, {:shutdown, :restart}, report}
  end

  def handle_in({"bad-code", opcode: :text}, report) do
    {:stop, :normal, 1005, report}
  end

  def handle_in({"long-reason", opcode: :text}, report) do
    {:stop, :normal, {1000, String.duplicate("é", 100)}, report}
  end

  def handle_in({"raise", opcode: :text}, _report) do
    raise "boom"
  end

  def handle_in({"crash-stop", opcode: :text}, report) do
    {:stop, :oops, report}
  end

  def handle_in({data, opcode: :text}, report), do: {:push, {:text, data}, report}

  @impl true
  def handle_control({data, opcode: opcode}, report) do
    send(report, {:control, opcode, data})
    {:ok, report}
  end

  @impl true
  def handle_info({:tell, data}, report), do: {:push, {:text, data}, report}

  @impl true
  def terminate(reason, report), do: send(report, {:terminated, reason})
end
