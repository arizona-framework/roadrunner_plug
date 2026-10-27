defmodule Roadrunner.Plug.AdapterTest do
  use ExUnit.Case, async: true

  alias Roadrunner.Plug.Adapter

  defp conn(headers, scheme \\ :http) do
    Adapter.conn(%{
      method: "GET",
      target: "/a/b?x=1",
      path: "/a/b",
      headers: headers,
      scheme: scheme,
      peer: {{127, 0, 0, 1}, 5000}
    })
  end

  # What `URI.parse/1` makes of a Host value.
  defp uri_host_port(host, default) do
    case URI.parse("//" <> host) do
      %URI{host: h, port: nil} when is_binary(h) -> {h, default}
      %URI{host: h, port: p} when is_binary(h) -> {h, p}
      _ -> {host, default}
    end
  end

  test "builds the conn from the request" do
    conn = conn([{"host", "example.com:4000"}, {"x-a", "1"}])
    assert conn.host == "example.com"
    assert conn.port == 4000
    assert conn.path_info == ["a", "b"]
    assert conn.request_path == "/a/b"
    assert conn.query_string == "x=1"
    assert conn.remote_ip == {127, 0, 0, 1}
    assert conn.req_headers == [{"host", "example.com:4000"}, {"x-a", "1"}]
  end

  test "a request without a Host gets an empty host and the scheme's port" do
    assert %{host: "", port: 80} = conn([])
    assert %{host: "", port: 443} = conn([], :https)
  end

  test "reads the host and port as URI.parse/1 does" do
    hosts = [
      "localhost",
      "localhost:4000",
      "Example.COM:0012",
      "h:99999",
      "h:",
      "h:abc",
      "h:+1",
      "h:1:2",
      ":80",
      "",
      "[::1]",
      "[::1]:8080",
      "[::1",
      "u@h:1",
      "h/x",
      "h?x",
      "h#x",
      "h]:1",
      "a b"
    ]

    for host <- hosts, {scheme, default} <- [http: 80, https: 443] do
      %{host: h, port: p} = conn([{"host", host}], scheme)
      assert {h, p} == uri_host_port(host, default), "host #{inspect(host)}"
    end
  end
end
