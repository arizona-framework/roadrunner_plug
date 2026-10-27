defmodule Roadrunner.Plug do
  @moduledoc """
  Run a Plug on [Roadrunner](https://hexdocs.pm/roadrunner).

  Add it to a supervision tree with the plug to serve:

      children = [
        {Roadrunner.Plug, plug: MyApp.Router, port: 4000}
      ]

  Options:

    * `:plug` - the plug to run, as `Module` or `{Module, opts}`. Its
      `init/1` runs once, when the listener starts.
    * `:port` - the TCP port to listen on (default `4000`; `0` lets the
      system pick one, see `port/1`).
    * `:ip` - the local address to bind (default: all interfaces).
    * `:scheme` - `:http` (default) or `:https`.
    * `:name` - the listener's registered name (default derived from the
      plug module).
    * `:roadrunner` - any other `:roadrunner_listener` option, as a map
      (`protocols`, `ws`, `max_clients`, ...). Request bodies are read on
      demand (`body_buffering: :manual`), so `Plug.Parsers` sets their
      limits.

  With `scheme: :https`, the TLS options are either `:tls` (`:ssl` server
  options as given) or Plug's (`:keyfile`, `:certfile`, `:key`, `:cert`,
  `:cacertfile`, `:password`, `:cipher_suite`, `:otp_app`, ...), resolved by
  `Plug.SSL.configure/1` the way Phoenix's `:https` endpoint config expects.
  """

  @doc "A child spec that starts the listener under a supervisor."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: {__MODULE__, name(opts)}, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  @doc "Start the listener, linked to the caller."
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    :roadrunner_listener.start_link(name(opts), listener_opts(opts))
  end

  @doc "The port the listener named `name` bound."
  @spec port(atom()) :: :inet.port_number()
  def port(name), do: :roadrunner_listener.port(name)

  @doc false
  @spec name(keyword()) :: atom()
  def name(opts) do
    Keyword.get_lazy(opts, :name, fn -> Module.concat(__MODULE__, plug_module(opts)) end)
  end

  @own_keys [:plug, :port, :ip, :scheme, :tls, :name, :roadrunner, :display_plug]

  @doc false
  @spec listener_opts(keyword()) :: map()
  def listener_opts(opts) do
    %{
      port: Keyword.get(opts, :port, 4000),
      routes: {Roadrunner.Plug.Handler, plug(opts)},
      body_buffering: :manual
    }
    |> put_opt(opts, :ip)
    |> put_tls(Keyword.get(opts, :scheme, :http), opts)
    |> Map.merge(Keyword.get(opts, :roadrunner, %{}))
  end

  defp plug(opts) do
    case Keyword.fetch!(opts, :plug) do
      {module, plug_opts} -> {module, plug_opts}
      module when is_atom(module) -> {module, []}
    end
  end

  defp plug_module(opts), do: opts |> plug() |> elem(0)

  defp put_opt(map, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Map.put(map, key, value)
      :error -> map
    end
  end

  defp put_tls(map, :http, _opts), do: map

  defp put_tls(map, :https, opts) do
    case Keyword.fetch(opts, :tls) do
      {:ok, tls} -> Map.put(map, :tls, tls)
      :error -> Map.put(map, :tls, plug_ssl(Keyword.drop(opts, @own_keys)))
    end
  end

  defp plug_ssl(ssl_opts) do
    case Plug.SSL.configure(ssl_opts) do
      {:ok, tls} -> tls
      {:error, message} -> raise ArgumentError, "could not configure TLS: " <> message
    end
  end
end
