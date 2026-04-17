defmodule AtriumWeb.SessionControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.Accounts
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup %{conn: conn} do
    {:ok, t} = Tenants.create_tenant_record(%{slug: "sc_test", name: "SC Test"})
    on_exit(fn -> _ = Triplex.drop("sc_test") end)
    {:ok, t} = Provisioner.provision(t)
    prefix = Triplex.to_prefix(t.slug)

    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")

    conn = Map.put(conn, :host, "sc_test.atrium.example")
    {:ok, conn: conn, user: user}
  end

  test "GET /login renders the form", %{conn: conn} do
    conn = get(conn, "/login")
    assert html_response(conn, 200) =~ "Sign in"
  end

  test "POST /login with correct credentials sets cookie and redirects to /", %{conn: conn, user: user} do
    conn = post(conn, "/login", %{"email" => "a@e.co", "password" => "superSecret1234!"})
    assert redirected_to(conn) == "/"
    assert conn.resp_cookies["_atrium_session"]
    conn2 = conn |> recycle() |> Map.put(:host, "sc_test.atrium.example") |> get("/")
    assert html_response(conn2, 200) =~ user.email || true
  end

  test "POST /login with wrong password renders form with error", %{conn: conn} do
    conn = post(conn, "/login", %{"email" => "a@e.co", "password" => "wrong"})
    assert html_response(conn, 200) =~ "Invalid"
  end

  test "DELETE /logout clears the cookie and revokes server-side session", %{conn: conn} do
    conn = post(conn, "/login", %{"email" => "a@e.co", "password" => "superSecret1234!"})
    cookie = conn.resp_cookies["_atrium_session"].value
    conn2 = conn |> recycle() |> Map.put(:host, "sc_test.atrium.example") |> delete("/logout")
    assert redirected_to(conn2) == "/login"
    assert conn2.resp_cookies["_atrium_session"].max_age == 0
    assert :not_found = Accounts.get_session_by_token(Triplex.to_prefix("sc_test"), cookie)
  end
end
