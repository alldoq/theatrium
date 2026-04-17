defmodule AtriumWeb.PasswordResetControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.Accounts
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup %{conn: conn} do
    {:ok, t} = Tenants.create_tenant_record(%{slug: "pr_test", name: "PR"})
    on_exit(fn -> _ = Triplex.drop("pr_test") end)
    {:ok, t} = Provisioner.provision(t)
    prefix = Triplex.to_prefix(t.slug)
    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, _} = Accounts.activate_user(prefix, raw, "superSecret1234!")

    conn = Map.put(conn, :host, "pr_test.atrium.example")
    {:ok, conn: conn, prefix: prefix}
  end

  test "GET /password-reset/new renders form", %{conn: conn} do
    conn = get(conn, "/password-reset/new")
    assert html_response(conn, 200) =~ "Reset"
  end

  test "POST /password-reset always redirects (no account enumeration)", %{conn: conn} do
    conn1 = post(conn, "/password-reset", %{"email" => "a@e.co"})
    assert redirected_to(conn1) == "/login"
    conn2 = post(conn, "/password-reset", %{"email" => "unknown@e.co"})
    assert redirected_to(conn2) == "/login"
  end

  test "full reset round-trip", %{conn: conn, prefix: prefix} do
    {:ok, %{token: raw}} = Accounts.request_password_reset(prefix, "a@e.co")
    conn = post(conn, "/password-reset/#{raw}", %{"password" => "newSuperSecret1234!"})
    assert redirected_to(conn) == "/login"
    assert {:ok, _} = Accounts.authenticate_by_password(prefix, "a@e.co", "newSuperSecret1234!")
  end

  test "POST with invalid token shows error", %{conn: conn} do
    conn = post(conn, "/password-reset/bogus", %{"password" => "newSuperSecret1234!"})
    assert html_response(conn, 404) =~ "invalid" || html_response(conn, 404) =~ "expired"
  end
end
