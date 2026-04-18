defmodule AtriumWeb.Plugs.RequireTenantAdminTest do
  use AtriumWeb.ConnCase, async: true

  alias AtriumWeb.Plugs.RequireTenantAdmin

  defp conn_with_user(is_admin) do
    build_conn()
    |> assign(:current_user, %Atrium.Accounts.User{
        id: Ecto.UUID.generate(),
        email: "u@test.com",
        name: "U",
        status: "active",
        is_admin: is_admin
      })
  end

  test "passes when current_user.is_admin is true" do
    conn = conn_with_user(true) |> RequireTenantAdmin.call([])
    refute conn.halted
  end

  test "returns 403 when current_user.is_admin is false" do
    conn = conn_with_user(false) |> RequireTenantAdmin.call([])
    assert conn.halted
    assert conn.status == 403
  end

  test "returns 403 when current_user is nil" do
    conn = build_conn() |> assign(:current_user, nil) |> RequireTenantAdmin.call([])
    assert conn.halted
    assert conn.status == 403
  end
end
