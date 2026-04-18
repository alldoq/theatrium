defmodule AtriumWeb.SuperAdmin.TenantControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.SuperAdmins
  alias Atrium.Tenants

  setup %{conn: conn} do
    {:ok, sa} =
      SuperAdmins.create_super_admin(%{
        email: "sa_tenant@atrium.example",
        name: "Ops",
        password: "correct-horse-battery-staple"
      })

    conn =
      conn
      |> Map.put(:host, "admin.atrium.example")
      |> init_test_session(%{super_admin_id: sa.id})

    on_exit(fn ->
      _ = Triplex.drop("ctrl_test_mcl")
    end)

    {:ok, conn: conn, sa: sa}
  end

  test "index lists tenants", %{conn: conn} do
    {:ok, _} = Tenants.create_tenant_record(%{slug: "ctrl_test_mcl", name: "MCL"})
    conn = get(conn, "/super/tenants")
    assert html_response(conn, 200) =~ "ctrl_test_mcl"
  end

  test "POST /super/tenants creates and provisions", %{conn: conn} do
    conn =
      post(conn, "/super/tenants", %{
        "tenant" => %{"slug" => "ctrl_test_mcl", "name" => "MCL"}
      })

    assert redirected_to(conn) =~ "/super/tenants/"
    assert %{status: "active"} = Tenants.get_tenant_by_slug("ctrl_test_mcl")
  end

  test "POST /super/tenants renders form with errors on invalid slug", %{conn: conn} do
    conn =
      post(conn, "/super/tenants", %{
        "tenant" => %{"slug" => "INVALID", "name" => "x"}
      })

    assert html_response(conn, 200) =~ "lowercase"
  end
end
