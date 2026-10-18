defmodule Luxpkgs.MixProject do
  use Mix.Project

  def project do
    [
      app: :luxpkgs,
      version: "0.5.1",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Luxpkgs.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:bcrypt_elixir, "~> 3.0"},
      {:dns_cluster, "~> 0.1.1"},
      {:ecto_sql, "~> 3.10"},
      {:esbuild, "~> 0.9", runtime: Mix.env() == :dev},
      {:floki, ">= 0.30.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:mdex, "~> 0.13"},
      {:phoenix_html_sanitizer, "~> 1.2"},
      {:phoenix, "~> 1.8.0-rc.0", override: true},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:live_debugger, "~> 1.0", only: :dev},
      {:postgrex, ">= 0.0.0"},
      {:req, "~> 0.5"},
      {:swoosh, "~> 1.16"},
      {:tablerone, "~> 1.0"},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:ueberauth_github, "~> 0.8"},
      {:guardian, "~> 2.3"},
      {:open_api_spex, "~> 3.6"},
      {:flop, "~> 0.26"},
      {:flop_phoenix, "~> 0.25"},
      {:tidewave, "~> 0.5", only: :dev},
      {:hammer, "~> 7.0"},
      {:cachex, "~> 3.6"},
      {:excoveralls, "~> 0.18", only: :test},
      {:nimble_totp, "~> 1.0"},
      {:cloak_ecto, "~> 1.3"},
      {:eqrcode, "~> 0.1"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind luxpkgs", "esbuild luxpkgs"],
      "assets.deploy": [
        "tailwind luxpkgs --minify",
        "esbuild luxpkgs --minify",
        "phx.digest"
      ]
    ]
  end
end
