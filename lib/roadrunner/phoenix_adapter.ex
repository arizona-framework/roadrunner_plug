defmodule Roadrunner.PhoenixAdapter do
  @moduledoc """
  A Phoenix endpoint adapter that serves the endpoint with Roadrunner.

      # config/config.exs
      config :my_app, MyAppWeb.Endpoint,
        adapter: Roadrunner.PhoenixAdapter,
        url: [host: "localhost"]

  The endpoint's `:http` and `:https` keyword lists are `Roadrunner.Plug`
  options: `:ip` and `:port` as in a generated Phoenix app, the TLS keys
  (`:keyfile`, `:certfile`, ...) under `:https`, and `:roadrunner` for any
  other listener option.
  """

  @doc false
  @spec child_specs(module(), keyword()) :: [Supervisor.child_spec()]
  def child_specs(endpoint, config) do
    otp_app = Keyword.fetch!(config, :otp_app)
    plug = resolve_plug(config[:code_reloader], endpoint)

    for scheme <- [:http, :https], opts = config[scheme] do
      [plug: plug, scheme: scheme, name: name(endpoint, scheme)]
      |> Keyword.merge(tls_base(scheme, otp_app))
      |> Keyword.merge(opts)
      |> Roadrunner.Plug.child_spec()
      |> Supervisor.child_spec(id: {endpoint, scheme})
    end
  end

  @doc "The address and port the endpoint's `scheme` listener is bound to."
  @spec server_info(module(), :http | :https) ::
          {:ok, {:inet.ip_address(), :inet.port_number()}} | {:error, term()}
  def server_info(endpoint, scheme) do
    name = name(endpoint, scheme)

    case Process.whereis(name) do
      nil ->
        {:error, :no_server_found}

      _pid ->
        ip = Keyword.get(endpoint.config(scheme) || [], :ip, {0, 0, 0, 0})
        {:ok, {ip, Roadrunner.Plug.port(name)}}
    end
  end

  defp name(endpoint, scheme), do: Module.concat([endpoint, Roadrunner, scheme])

  # Relative `:keyfile` / `:certfile` paths resolve against the app's dir.
  defp tls_base(:http, _otp_app), do: []
  defp tls_base(:https, otp_app), do: [otp_app: otp_app]

  # As Phoenix's own adapters: with the code reloader on, requests go
  # through the plug that waits for a reload in progress.
  defp resolve_plug(code_reload?, endpoint) do
    if code_reload? && Code.ensure_loaded?(Phoenix.Endpoint.SyncCodeReloadPlug) &&
         function_exported?(Phoenix.Endpoint.SyncCodeReloadPlug, :call, 2) do
      {Phoenix.Endpoint.SyncCodeReloadPlug, {endpoint, []}}
    else
      endpoint
    end
  end
end
