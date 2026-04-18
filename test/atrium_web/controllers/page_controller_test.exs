defmodule AtriumWeb.PageControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "page_test", name: "Page Test"})
    {:ok, tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop("page_test") end)
    {:ok, tenant: tenant}
  end

  test "GET / redirects to /login when unauthenticated", %{conn: conn} do
    conn = conn |> Map.put(:host, "page_test.atrium.example") |> get("/")
    assert redirected_to(conn) == "/login"
  end
end
