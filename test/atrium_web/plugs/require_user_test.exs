defmodule AtriumWeb.Plugs.RequireUserTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.Accounts
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner
  alias AtriumWeb.Plugs.RequireUser

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "req_user_test", name: "Test"})
    {:ok, tenant} = Provisioner.provision(tenant)
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :manual)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Atrium.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, {:shared, self()})

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)
      _ = Triplex.drop("req_user_test")
      t = Atrium.Tenants.get_tenant_by_slug("req_user_test")
      if t, do: Atrium.Repo.delete(t)
      Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :manual)
    end)

    prefix = Triplex.to_prefix(tenant.slug)

    {:ok, %{user: _u, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    {:ok, %{token: session_token}} = Accounts.create_session(prefix, user, %{})

    conn =
      conn
      |> Map.put(:host, "req_user_test.atrium.example")
      |> Plug.Test.init_test_session(%{})
      |> assign(:tenant, tenant)
      |> assign(:tenant_prefix, prefix)

    {:ok, conn: conn, user: user, session_token: session_token}
  end

  test "assigns current_user when session cookie is valid", %{conn: conn, user: user, session_token: token} do
    conn = conn |> Plug.Test.put_req_cookie("_atrium_session", token) |> fetch_cookies() |> RequireUser.call([])
    assert conn.assigns.current_user.id == user.id
  end

  test "redirects to /login when no session", %{conn: conn} do
    conn = RequireUser.call(conn, [])
    assert conn.halted
    assert redirected_to(conn) == "/login"
  end

  test "redirects when session is invalid", %{conn: conn} do
    conn = conn |> Plug.Test.put_req_cookie("_atrium_session", "bogus") |> fetch_cookies() |> RequireUser.call([])
    assert conn.halted
    assert redirected_to(conn) == "/login"
  end
end
