defmodule AtriumWeb.SuperAdmin.SessionControllerTest do
  use AtriumWeb.ConnCase, async: true
  alias Atrium.SuperAdmins

  setup %{conn: conn} do
    {:ok, sa} =
      SuperAdmins.create_super_admin(%{
        email: "sa_sess@atrium.example",
        name: "Ops",
        password: "correct-horse-battery-staple"
      })

    conn = Map.put(conn, :host, "admin.atrium.example")
    {:ok, conn: conn, sa: sa}
  end

  test "GET /super/login renders the form", %{conn: conn} do
    conn = get(conn, "/super/login")
    assert html_response(conn, 200) =~ "Sign in"
  end

  test "POST /super/login with correct credentials redirects to dashboard and sets session", %{conn: conn, sa: sa} do
    conn = post(conn, "/super/login", %{"email" => "sa_sess@atrium.example", "password" => "correct-horse-battery-staple"})
    assert redirected_to(conn) == "/super"
    assert get_session(conn, :super_admin_id) == sa.id
  end

  test "POST /super/login with wrong password renders form with error", %{conn: conn} do
    conn = post(conn, "/super/login", %{"email" => "sa_sess@atrium.example", "password" => "nope"})
    assert html_response(conn, 200) =~ "Invalid"
    refute get_session(conn, :super_admin_id)
  end

  test "writes audit event on login success", %{conn: conn, sa: sa} do
    post(conn, "/super/login", %{"email" => "sa_sess@atrium.example", "password" => "correct-horse-battery-staple"})
    events = Atrium.Audit.list_global(action: "super_admin.login")
    assert Enum.any?(events, fn e -> e.actor_id == sa.id end)
  end

  test "writes audit event on login failure", %{conn: conn} do
    post(conn, "/super/login", %{"email" => "sa_sess@atrium.example", "password" => "wrong"})
    events = Atrium.Audit.list_global(action: "super_admin.login_failed")
    assert Enum.any?(events)
  end

  test "DELETE /super/logout clears the session", %{conn: conn, sa: sa} do
    conn = conn |> init_test_session(%{super_admin_id: sa.id})
    conn = delete(conn, "/super/logout")
    assert redirected_to(conn) == "/super/login"
    refute get_session(conn, :super_admin_id)
  end
end
