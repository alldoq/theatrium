defmodule AtriumWeb.InvitationControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.Accounts
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup %{conn: conn} do
    {:ok, t} = Tenants.create_tenant_record(%{slug: "inv_test", name: "Inv"})
    on_exit(fn -> _ = Triplex.drop("inv_test") end)
    {:ok, t} = Provisioner.provision(t)
    prefix = Triplex.to_prefix(t.slug)

    {:ok, %{user: user, token: raw}} = Accounts.invite_user(prefix, %{email: "new@e.co", name: "New"})

    conn = Map.put(conn, :host, "inv_test.atrium.example")

    {:ok, conn: conn, user: user, token: raw}
  end

  test "GET /invitations/:token renders activation form", %{conn: conn, token: token} do
    conn = get(conn, "/invitations/#{token}")
    assert html_response(conn, 200) =~ "Set your password"
  end

  test "POST /invitations/:token activates user and logs them in", %{conn: conn, token: token} do
    conn = post(conn, "/invitations/#{token}", %{"password" => "superSecret1234!"})
    assert redirected_to(conn) == "/"
    assert conn.resp_cookies["_atrium_session"]
  end

  test "POST /invitations/:token with invalid token returns 404", %{conn: conn} do
    conn = post(conn, "/invitations/not-real", %{"password" => "superSecret1234!"})
    assert html_response(conn, 404) =~ "invalid or expired"
  end

  test "GET /invitations/:token always renders form regardless of token validity", %{conn: conn} do
    conn = get(conn, "/invitations/not-real")
    assert html_response(conn, 200) =~ "Set your password"
  end
end
