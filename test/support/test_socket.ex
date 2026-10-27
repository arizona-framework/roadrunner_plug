defmodule Roadrunner.Plug.TestSocket do
  @moduledoc false
  # A Phoenix socket on `Roadrunner.Plug.TestEndpoint`: Channels and LiveView
  # reach WebSockets through it, by way of WebSockAdapter.

  use Phoenix.Socket

  channel("room:*", Roadrunner.Plug.TestChannel)

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end

defmodule Roadrunner.Plug.TestChannel do
  @moduledoc false
  # Replies to a "ping" with its payload, then pushes it back.

  use Phoenix.Channel

  @impl true
  def join("room:" <> _room, _params, socket), do: {:ok, socket}

  @impl true
  def handle_in("ping", payload, socket) do
    push(socket, "pushed", payload)
    {:reply, {:ok, payload}, socket}
  end
end
