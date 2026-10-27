# Roadrunner.Plug

Run [Plug](https://hexdocs.pm/plug) and [Phoenix](https://hexdocs.pm/phoenix)
apps on [Roadrunner](https://github.com/arizona-framework/roadrunner), the
pure-Erlang HTTP/1.1, HTTP/2, HTTP/3 and WebSocket server.

## 🚧 Status

Roadrunner.Plug is in `0.x`. The core is functional and covered by tests,
but the API may change between minor versions. Pin an exact version in your
deps if you need stability across upgrades.

## Plug

Add the listener to your supervision tree:

```elixir
children = [
  {Roadrunner.Plug, plug: MyApp.Router, port: 4000}
]
```

See `Roadrunner.Plug` for the options: `:port`, `:ip`, `:scheme` and TLS,
and `:roadrunner` for any Roadrunner listener option.

## Phoenix

Set the endpoint's adapter:

```elixir
# config/config.exs
config :my_app, MyAppWeb.Endpoint,
  adapter: Roadrunner.PhoenixAdapter,
  url: [host: "localhost"]
```

The `:http` and `:https` settings work as in a generated Phoenix app.

## What works

- Responses: complete, chunked, files and `103 Early Hints`
- Request bodies read on demand, so `Plug.Parsers` sets the limits
- `get_peer_data/1` (with the client's TLS certificate), `get_sock_data/1`,
  `get_ssl_data/1` and `get_http_protocol/1`
- WebSocket upgrades through `Plug.Conn.upgrade_adapter/3` with a `WebSock`
  handler, over HTTP/1.1
- Phoenix endpoints, including the code reloader

Phoenix Channels and LiveView reach WebSockets through `WebSockAdapter`,
which only knows the servers it lists, so they need Roadrunner to be added
there first.

## License

Copyright (c) 2026 [William Fank Thomé](https://github.com/williamthome)

Roadrunner.Plug is open-source under the Apache 2.0 License on
[GitHub](https://github.com/arizona-framework/roadrunner_plug).

See [LICENSE.md](https://github.com/arizona-framework/roadrunner_plug/blob/main/LICENSE.md) for more information.
