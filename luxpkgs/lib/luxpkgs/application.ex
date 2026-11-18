defmodule Luxpkgs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        LuxpkgsWeb.Telemetry,
        Luxpkgs.Vault,
        Luxpkgs.Repo,
        {DNSCluster, query: Application.get_env(:luxpkgs, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Luxpkgs.PubSub},
        {LuxpkgsWeb.RateLimit, clean_period: :timer.minutes(5)},
        Supervisor.child_spec(
          {Cachex, name: :search_cache, limit: 1_000},
          id: :search_cache
        ),
        Supervisor.child_spec(
          {Cachex, name: :totp_backup_codes, limit: 1_000},
          id: :totp_backup_codes_cache
        ),
        Supervisor.child_spec(
          {Cachex, name: :totp_setup, limit: 1_000},
          id: :totp_setup_cache
        )
      ] ++ atproto_children() ++ [LuxpkgsWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Luxpkgs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # The atproto client is optional so environments without a client key still boot.
  defp atproto_children do
    case Application.get_env(:luxpkgs, :atproto) do
      nil ->
        []

      config ->
        [
          Luxpkgs.AtpOauthStore,
          {Latch, Keyword.put(config, :name, Luxpkgs.AtpOauth.Client)}
        ]
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LuxpkgsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
