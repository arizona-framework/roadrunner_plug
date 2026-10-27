defmodule Roadrunner.Plug.TLSTest do
  use ExUnit.Case, async: false

  alias Roadrunner.Plug.TestPlug

  setup_all do
    key = fn -> {:rsa, 2048, 65537} |> :public_key.generate_key() end

    certs =
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

    {:ok, certs: certs}
  end

  setup %{certs: certs} do
    name = :"roadrunner_plug_tls_#{System.unique_integer([:positive])}"
    server = [{:verify, :verify_peer} | certs.server_config]

    start_supervised!(
      {Roadrunner.Plug,
       plug: {TestPlug, report: self()}, port: 0, name: name, scheme: :https, tls: server}
    )

    {:ok, port: Roadrunner.Plug.port(name)}
  end

  test "the conn sees TLS and the client certificate", %{port: port, certs: certs} do
    client =
      [:binary, active: false, verify: :verify_none] ++
        Keyword.delete(certs.client_config, :verify)

    {:ok, sock} = :ssl.connect(~c"127.0.0.1", port, client, 5000)
    :ok = :ssl.send(sock, "GET /info HTTP/1.1\r\nhost: localhost\r\nconnection: close\r\n\r\n")
    assert_receive {:info, info}, 5000

    assert %{scheme: :https, port: 443, host: "localhost"} = info
    assert info.peer_data.ssl_cert == Keyword.fetch!(certs.client_config, :cert)
    assert Keyword.has_key?(info.ssl_data, :protocol)
  end
end
