defmodule Roadrunner.Plug.WebSock do
  @moduledoc false
  # Runs a `WebSock` handler as a roadrunner WebSocket handler. The state is
  # `{websock, websock_state}`, or `{websock, websock_state, stop_reason}`
  # once the handler stopped with a reason other than `:normal`, so
  # `terminate/2` reports it instead of roadrunner's `normal`.

  @behaviour :roadrunner_ws_handler

  require Logger

  # WebSockAdapter's documented defaults, which the listener's would
  # otherwise replace: no compression, a 60 s idle timeout.
  @defaults %{compress: false, idle_timeout: 60_000}

  # The longest close reason a close frame carries: a control frame's 125
  # payload bytes less the 2-byte code (RFC 6455 §5.5).
  @max_close_reason 123

  @doc "WebSock upgrade options as roadrunner's (`:roadrunner_ws_handler.upgrade_opts/0`)."
  @spec upgrade_opts(keyword()) :: map()
  def upgrade_opts(opts) do
    Enum.reduce(opts, @defaults, fn
      {:timeout, :infinity}, acc ->
        Map.put(acc, :idle_timeout, :infinity)

      {:timeout, ms}, acc when is_integer(ms) and ms > 0 ->
        Map.put(acc, :idle_timeout, ms)

      {:compress, compress}, acc when is_boolean(compress) ->
        Map.put(acc, :compress, compress)

      # WebSock's 0 means no cap; roadrunner's would refuse every frame.
      # The message cap follows, so one frame of that size is a message
      # roadrunner takes.
      {:max_frame_size, size}, acc when is_integer(size) and size > 0 ->
        Map.merge(acc, %{max_frame_size: size, max_message_size: size})

      {:fullsweep_after, n}, acc ->
        Map.put(acc, :fullsweep_after, n)

      {:max_heap_size, size}, acc ->
        Map.put(acc, :max_heap_size, size)

      # `validate_utf8` (roadrunner always validates), `active_n` and
      # `deflate_options` have no counterpart.
      _other, acc ->
        acc
    end)
  end

  @impl true
  def init({websock, state}), do: call(websock, state, fn -> websock.init(state) end)

  @impl true
  def handle_frame(%{opcode: opcode, payload: data}, {websock, state}) do
    call(websock, state, fn -> websock.handle_in({data, opcode: opcode}, state) end)
  end

  @impl true
  def handle_control(%{opcode: opcode, payload: data}, {websock, state}) do
    # roadrunner already answered a ping; the handler only observes.
    if function_exported?(websock, :handle_control, 2) do
      call(websock, state, fn -> websock.handle_control({data, opcode: opcode}, state) end)
    else
      {:ok, {websock, state}}
    end
  end

  @impl true
  def handle_info(message, {websock, state}) do
    call(websock, state, fn -> websock.handle_info(message, state) end)
  end

  @impl true
  def handle_drain(_deadline, {websock, state}) do
    # The listener is draining: `terminate/2` gets `:shutdown`.
    {:close, 1001, "", {websock, state}}
  end

  @impl true
  def terminate(reason, {websock, state}), do: terminate_websock(websock, reason, state)

  def terminate(_reason, {websock, state, stop_reason}),
    do: terminate_websock(websock, stop_reason, state)

  # A callback that raises closes the session with 1011 and its
  # `terminate/2` gets `{:error, reason}` with the last state it returned,
  # as Bandit does; the crash is logged here, since the session goes on to
  # close cleanly.
  defp call(websock, state, callback) do
    result(callback.(), websock)
  catch
    kind, reason ->
      Logger.error(
        "WebSock handler #{inspect(websock)} crashed: " <>
          Exception.format(kind, reason, __STACKTRACE__)
      )

      {:close, 1011, "", {websock, state, {:error, reason}}}
  end

  defp terminate_websock(websock, reason, state) do
    if function_exported?(websock, :terminate, 2), do: websock.terminate(reason, state)
  end

  # The close codes for a stop without one follow Bandit's: 1000 for a
  # normal stop, 1012 (service restart) for `{:shutdown, :restart}`, 1011
  # (internal error) otherwise.
  defp result({:ok, state}, websock), do: {:ok, {websock, state}}
  defp result({:push, messages, state}, websock), do: {:reply, frames(messages), {websock, state}}

  defp result({:reply, _status, messages, state}, websock),
    do: {:reply, frames(messages), {websock, state}}

  defp result({:stop, {:shutdown, :restart}, state}, websock),
    do: close(:normal, 1012, [], websock, state)

  defp result({:stop, {:shutdown, :disconnected}, state}, websock),
    do: close(:normal, 1000, [], websock, state)

  defp result({:stop, :normal, state}, websock), do: close(:normal, 1000, [], websock, state)
  defp result({:stop, reason, state}, websock), do: close(reason, 1011, [], websock, state)

  defp result({:stop, reason, detail, state}, websock),
    do: close(reason, detail, [], websock, state)

  defp result({:stop, reason, detail, messages, state}, websock),
    do: close(reason, detail, frames(messages), websock, state)

  defp close(reason, detail, frames, websock, state) do
    {code, text} = close_detail(detail)

    {:close, sendable_code(code, reason), close_text(text), frames,
     stop_state(reason, websock, state)}
  end

  # roadrunner refuses to send a code a server may not (1004-1006, 1015,
  # unassigned ranges): one of those becomes 1000 for a normal stop, 1011
  # otherwise, instead of crashing the session.
  defp sendable_code(code, _reason)
       when code in 1000..1003 or code in 1007..1014 or code in 3000..4999,
       do: code

  defp sendable_code(_code, :normal), do: 1000
  defp sendable_code(_code, _reason), do: 1011

  # A reason must be UTF-8 that fits the frame: an invalid one is dropped, a
  # long one cut at a character boundary.
  defp close_text(text) do
    text = IO.iodata_to_binary(text)

    cond do
      not String.valid?(text) -> ""
      byte_size(text) <= @max_close_reason -> text
      true -> text |> binary_part(0, @max_close_reason) |> trim_partial_char()
    end
  end

  defp trim_partial_char(text) do
    if String.valid?(text),
      do: text,
      else: trim_partial_char(binary_part(text, 0, byte_size(text) - 1))
  end

  defp stop_state(:normal, websock, state), do: {websock, state}
  defp stop_state(reason, websock, state), do: {websock, state, {:error, reason}}

  defp close_detail({code, nil}), do: {code, ""}
  defp close_detail({code, text}), do: {code, text}
  defp close_detail(code) when is_integer(code), do: {code, ""}

  defp frames(messages) when is_list(messages), do: Enum.map(messages, &frame/1)
  defp frames(message), do: [frame(message)]

  defp frame({opcode, nil}), do: {opcode, ""}
  defp frame({opcode, data}), do: {opcode, data}
end
