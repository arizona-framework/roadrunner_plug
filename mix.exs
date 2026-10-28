defmodule Roadrunner.Plug.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/arizona-framework/roadrunner_plug"

  def project do
    [
      app: :roadrunner_plug,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Run Plug and Phoenix apps on the Roadrunner HTTP server.",
      package: package(),
      docs: docs(),
      name: "Roadrunner.Plug",
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:roadrunner, "~> 0.13"},
      {:plug, "~> 1.16"},
      {:websock, "~> 0.5"},
      # Phoenix stays out of this app's runtime applications, and the tests
      # start it: WebSockAdapter lists roadrunner_plug as an optional
      # dependency, so starting Phoenix from here would start this app
      # inside itself.
      {:phoenix, "~> 1.7", only: :test, runtime: false},
      # The first release that knows Roadrunner, for the socket test.
      {:websock_adapter, "~> 0.7", only: :test, runtime: false},
      {:jason, "~> 1.4", only: :test},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/roadrunner_plug",
        "Issues" => "#{@source_url}/issues",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Roadrunner" => "https://github.com/arizona-framework/roadrunner",
        "Sponsor" => "https://github.com/sponsors/williamthome"
      },
      files: ~w(lib mix.exs README.md LICENSE.md CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE.md"],
      source_ref: @version,
      source_url: @source_url
    ]
  end
end
