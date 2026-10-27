defmodule Roadrunner.Plug.MixProject do
  use Mix.Project

  def project do
    [
      app: :roadrunner_plug,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # The send shape, conn_info and the WebSocket upgrade options are on
      # roadrunner's main branch, not in a release yet.
      {:roadrunner, path: "../roadrunner", manager: :rebar3},
      {:plug, "~> 1.16"},
      {:websock, "~> 0.5"},
      {:phoenix, "~> 1.7", only: :test},
      {:jason, "~> 1.4", only: :test}
    ]
  end
end
