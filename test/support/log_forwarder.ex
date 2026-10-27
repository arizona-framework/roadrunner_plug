defmodule Roadrunner.Plug.LogForwarder do
  @moduledoc false
  # A `:logger` handler that sends each event's message to a test pid, so a
  # test waits for a log line instead of racing `capture_log/1`.

  @doc "Forward log events to the calling process until the test ends."
  def attach do
    id = :"log_forwarder_#{System.unique_integer([:positive])}"
    :ok = :logger.add_handler(id, __MODULE__, %{config: %{pid: self()}})
    ExUnit.Callbacks.on_exit(fn -> :logger.remove_handler(id) end)
  end

  @doc false
  def log(%{msg: msg}, %{config: %{pid: pid}}), do: send(pid, {:logged, msg})
end
