defmodule Roadrunner.Plug.WebSock do
  @moduledoc false
  # Runs a `WebSock` handler as a roadrunner WebSocket handler. The state is
  # `{websock, websock_state}`, or `{websock, websock_state, stop_reason}`
  # once the handler stopped with a reason other than `:normal`, so
  # `terminate/2` reports it instead of roadrunner's `normal`.

  @behaviour :roadrunner_ws_handler

  @doc "WebSock upgrade options as roadrunner's (`:roadrunner_ws_handler.upgrade_opts/0`)."
  @spec upgrade_opts(keyword()) :: map()
  def upgrade_opts(opts) do
    Enum.reduce(opts, %{}, fn
      {:timeout, :infinity}, acc ->
        Map.put(acc, :idle_timeout, :infinity)

      {:timeout, ms}, acc when is_integer(ms) and ms > 0 ->
        Map.put(acc, :idle_timeout, ms)

      {:compress, compress}, acc when is_boolean(compress) ->
        Map.put(acc, :compress, compress)

      # WebSock's 0 means no cap; roadrunner's would refuse every frame.
      {:max_frame_size, size}, acc when is_integer(size) and size > 0 ->
        Map.put(acc, :max_frame_size, size)

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
  def init({websock, state}), do: result(websock.init(state), websock)

  @impl true
  def handle_frame(%{opcode: opcode, payload: data}, {websock, state}) do
    result(websock.handle_in({data, opcode: opcode}, state), websock)
  end

  @impl true
  def handle_control(%{opcode: opcode, payload: data}, {websock, state}) do
    # roadrunner already answered a ping; the handler only observes.
    if function_exported?(websock, :handle_control, 2) do
      result(websock.handle_control({data, opcode: opcode}, state), websock)
    else
      {:ok, {websock, state}}
    end
  end

  @impl true
  def handle_info(message, {websock, state}) do
    result(websock.handle_info(message, state), websock)
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
    {:close, code, text, frames, stop_state(reason, websock, state)}
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
