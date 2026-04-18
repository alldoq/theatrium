defmodule AtriumWeb.Plugs.AuthorizeTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.Accounts
  alias Atrium.Authorization
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner
  alias AtriumWeb.Plugs.Authorize

  setup %{conn: conn} do
    {:ok, t} = Tenants.create_tenant_record(%{slug: "authz_test", name: "A"})
    {:ok, t} = Provisioner.provision(t)
    prefix = Triplex.to_prefix(t.slug)

    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")

    conn =
      conn
      |> assign(:tenant, t)
      |> assign(:tenant_prefix, prefix)
      |> assign(:current_user, user)

    on_exit(fn -> _ = Triplex.drop("authz_test") end)
    {:ok, conn: conn, user: user, prefix: prefix}
  end

  test "allows when user has capability", %{conn: conn, user: user, prefix: prefix} do
    {:ok, _} = Authorization.grant_section(prefix, "news", {:user, user.id}, :view)
    conn = Authorize.call(conn, capability: :view, target: {:section, "news"})
    refute conn.halted
  end

  test "denies with 403 when user does not have capability", %{conn: conn} do
    conn = Authorize.call(conn, capability: :edit, target: {:section, "news"})
    assert conn.status == 403
    assert conn.halted
  end
end
