defmodule Roadrunner.Plug.Handler do
  @moduledoc false
  # The roadrunner handler that runs a plug. It answers every request with
  # a `{send, [], Fun}` response, and the fun runs the plug: the adapter
  # sends as the plug calls `send_resp/3`, `send_chunked/2` and the rest.

  @behaviour :roadrunner_handler

  alias Roadrunner.Plug.Adapter

  @impl true
  def init_route({plug, opts}), do: {plug, plug.init(opts)}

  @impl true
  def handle(req), do: {{:send, [], &__MODULE__.run/1}, req}

  @doc false
  @spec run(:roadrunner_req.request()) :: :roadrunner_req.request()
  def run(req) do
    {plug, opts} = :roadrunner_req.state(req)
    conn = req |> Adapter.conn() |> plug.call(opts) |> maybe_send()
    :ok = Adapter.flush_sent()
    Adapter.request(conn)
  end

  # As Plug's other servers: a conn the plug set but did not send goes out
  # now, one with nothing set is a bug.
  defp maybe_send(%Plug.Conn{state: :unset}), do: raise(Plug.Conn.NotSentError)
  defp maybe_send(%Plug.Conn{state: :set} = conn), do: Plug.Conn.send_resp(conn)
  defp maybe_send(%Plug.Conn{} = conn), do: conn
end
