ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :manual)

# Start OIDC mock server for integration tests
children = [
  {Plug.Cowboy, scheme: :http, plug: Atrium.Test.OidcMock, options: [port: 4100]},
  %{
    id: Atrium.Test.OidcMock.Agent,
    start: {Agent, :start_link, [fn -> %{} end, [name: Atrium.Test.OidcMock.Agent]]}
  }
]
{:ok, _} = Supervisor.start_link(children, strategy: :one_for_one, name: Atrium.Test.MockSupervisor)
