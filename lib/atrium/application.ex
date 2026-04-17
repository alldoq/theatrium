defmodule Atrium.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AtriumWeb.Telemetry,
      Atrium.Repo,
      {DNSCluster, query: Application.get_env(:atrium, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Atrium.PubSub},
      Atrium.Vault,
      {Oban, Application.fetch_env!(:atrium, Oban)},
      AtriumWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Atrium.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AtriumWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
