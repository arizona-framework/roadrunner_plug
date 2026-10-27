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

    try do
      req |> Adapter.conn() |> plug.call(opts) |> maybe_send()
    catch
      kind, reason ->
        # As Plug's other servers: answer with the exception's status
        # (`Plug.Exception`, e.g. 413 or 400) when nothing went out yet. A
        # 5xx raises on, so roadrunner logs it; a 4xx is the client's, so
        # the request stops quietly (`{:shutdown, _}`). Either way the
        # connection closes, as the body's state is unknown.
        case send_error(kind, reason, req) do
          status when status >= 500 -> :erlang.raise(kind, reason, __STACKTRACE__)
          status -> exit({:shutdown, {:plug_status, status}})
        end
    else
      conn ->
        :ok = maybe_upgrade(conn)
        :ok = Adapter.flush_sent()
        Adapter.request(conn)
    end
  end

  # The exception's Plug status, sent unless the plug already answered.
  defp send_error(kind, reason, req) do
    case Exception.normalize(kind, reason) do
      %Plug.Conn.WrapperError{conn: %Plug.Conn{state: state}, reason: inner}
      when state not in [:unset, :set] ->
        Plug.Exception.status(inner)

      %Plug.Conn.WrapperError{reason: inner} ->
        reply_status(Plug.Exception.status(inner), req)

      exception ->
        reply_status(Plug.Exception.status(exception), req)
    end
  end

  # Nothing to send if the plug already did (a raise after a response).
  defp reply_status(status, req) do
    _ = :roadrunner_send.reply(status, [{"content-length", "0"}], "", req)
    status
  catch
    :error, :already_sent -> status
  end

  defp maybe_upgrade(%Plug.Conn{state: :upgraded} = conn), do: Adapter.upgrade(conn)
  defp maybe_upgrade(%Plug.Conn{}), do: :ok

  # As Plug's other servers: a conn the plug set but did not send goes out
  # now, one with nothing set is a bug.
  defp maybe_send(%Plug.Conn{state: :unset}), do: raise(Plug.Conn.NotSentError)
  defp maybe_send(%Plug.Conn{state: :set} = conn), do: Plug.Conn.send_resp(conn)
  defp maybe_send(%Plug.Conn{} = conn), do: conn
end
