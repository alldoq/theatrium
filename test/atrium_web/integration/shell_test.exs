defmodule AtriumWeb.Integration.ShellTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.Accounts
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup %{conn: conn} do
    {:ok, t} = Tenants.create_tenant_record(%{slug: "shell_test", name: "Shell Test", enabled_sections: ~w(home news compliance)})
    {:ok, t} = Provisioner.provision(t)
    prefix = Triplex.to_prefix(t.slug)

    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    {:ok, %{token: st}} = Accounts.create_session(prefix, user, %{})

    on_exit(fn -> _ = Triplex.drop("shell_test") end)

    conn =
      conn
      |> Map.put(:host, "shell_test.atrium.example")
      |> Plug.Test.put_req_cookie("_atrium_session", st)
      |> fetch_cookies()

    {:ok, conn: conn}
  end

  test "home page renders with themed nav showing home + news", %{conn: conn} do
    conn = get(conn, "/")
    body = html_response(conn, 200)
    assert body =~ "Home"
    assert body =~ "News"
    refute body =~ "Departments"
  end
end
