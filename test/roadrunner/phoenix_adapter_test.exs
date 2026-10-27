defmodule Roadrunner.PhoenixAdapterTest do
  use ExUnit.Case, async: false

  alias Roadrunner.Plug.TestEndpoint

  setup_all do
    Application.put_env(:roadrunner_plug, TestEndpoint,
      adapter: Roadrunner.PhoenixAdapter,
      http: [ip: {127, 0, 0, 1}, port: 0],
      server: true,
      secret_key_base: String.duplicate("a", 64)
    )

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
end
