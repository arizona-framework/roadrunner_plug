# Roadrunner.Plug

[![CI](https://github.com/arizona-framework/roadrunner_plug/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/arizona-framework/roadrunner_plug/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/roadrunner_plug.svg)](https://hex.pm/packages/roadrunner_plug)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/roadrunner_plug/)
[![License](https://img.shields.io/hexpm/l/roadrunner_plug.svg)](https://github.com/arizona-framework/roadrunner_plug/blob/main/LICENSE.md)

Run [Plug](https://hexdocs.pm/plug) and [Phoenix](https://hexdocs.pm/phoenix)
apps on [Roadrunner](https://github.com/arizona-framework/roadrunner), the
pure-Erlang HTTP/1.1, HTTP/2, HTTP/3 and WebSocket server.

## Requirements

Requires **OTP 27+** and **Elixir 1.18+**.

## 🚧 Status

Roadrunner.Plug is in `0.x`. The core is functional and covered by tests,
but the API may change between minor versions. Pin an exact version in your
deps if you need stability across upgrades.

## Installation

Add `roadrunner_plug` to your deps in `mix.exs` (latest version on
[Hex](https://hex.pm/packages/roadrunner_plug)):

```elixir
def deps do
  [
    {:roadrunner_plug, ">= 0.0.0"}
  ]
end
```

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
- Phoenix Channels and LiveView over WebSocket, with `websock_adapter` 0.7
  or later (`mix deps.update websock_adapter` in an existing app)

## Sponsors

Roadrunner.Plug is open source and maintained on personal time. If you or your company find it useful,
consider [sponsoring](https://github.com/sponsors/williamthome).

I also accept coffees ☕

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/williamthome)

<a href="https://github.com/sponsors/williamthome">
  <img
    src="https://raw.githubusercontent.com/williamthome/williamthome/sponsorkit/sponsors.svg"
    alt="Sponsors"
  />
</a>

## License

Copyright (c) 2026 [William Fank Thomé](https://github.com/williamthome)

Roadrunner.Plug is open-source under the Apache 2.0 License on
[GitHub](https://github.com/arizona-framework/roadrunner_plug).

See [LICENSE.md](https://github.com/arizona-framework/roadrunner_plug/blob/main/LICENSE.md) for more information.
