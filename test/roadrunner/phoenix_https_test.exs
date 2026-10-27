defmodule Roadrunner.PhoenixHTTPSTest do
  use ExUnit.Case, async: false

  alias Roadrunner.Plug.TestEndpoint

  setup_all do
    key = fn -> :public_key.generate_key({:rsa, 2048, 65537}) end

    %{server_config: server} =
      :public_key.pkix_test_data(%{
        server_chain: %{
          root: [key: key.(), digest: :sha256],
          peer: [key: key.(), digest: :sha256]
        },
        client_chain: %{
          root: [key: key.(), digest: :sha256],
          peer: [key: key.(), digest: :sha256]
        }
      })

    dir =
      Path.join(System.tmp_dir!(), "roadrunner_plug_https_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    {key_type, key_der} = Keyword.fetch!(server, :key)
    keyfile = Path.join(dir, "key.pem")
    certfile = Path.join(dir, "cert.pem")
    File.write!(keyfile, :public_key.pem_encode([{key_type, key_der, :not_encrypted}]))

    File.write!(
      certfile,
      :public_key.pem_encode([{:Certificate, Keyword.fetch!(server, :cert), :not_encrypted}])
    )

    Application.put_env(:roadrunner_plug, TestEndpoint,
      adapter: Roadrunner.PhoenixAdapter,
      https: [ip: {127, 0, 0, 1}, port: 0, keyfile: keyfile, certfile: certfile],
      server: true,
      secret_key_base: String.duplicate("a", 64)
    )

    on_exit(fn -> Application.delete_env(:roadrunner_plug, TestEndpoint) end)

    start_supervised!(TestEndpoint)
    {:ok, {_ip, port}} = TestEndpoint.server_info(:https)
    {:ok, port: port}
  end

  test "reports where it listens over HTTPS", %{port: port} do
    assert {:ok, {{127, 0, 0, 1}, ^port}} = TestEndpoint.server_info(:https)
    assert port > 0
    assert {:error, :no_server_found} = TestEndpoint.server_info(:http)
  end

  test "serves the endpoint's plugs over TLS", %{port: port} do
    {:ok, sock} =
      :ssl.connect(~c"127.0.0.1", port, [:binary, active: false, verify: :verify_none], 5000)

    :ok = :ssl.send(sock, "GET /hello HTTP/1.1\r\nhost: localhost\r\nconnection: close\r\n\r\n")
    response = recv_all(sock, "")

    assert response =~ ~r/\AHTTP\/1.1 200 /
    assert response =~ ~r/\r\ncontent-type: text\/plain; charset=utf-8\r\n/i
    assert String.ends_with?(response, "\r\n\r\nhello from phoenix")
  end

  defp recv_all(sock, acc) do
    case :ssl.recv(sock, 0, 5000) do
      {:ok, data} -> recv_all(sock, acc <> data)
      {:error, :closed} -> acc
    end
  end
end
