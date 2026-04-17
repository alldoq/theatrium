defmodule AtriumWeb.Plugs.TenantResolverTest do
  use AtriumWeb.ConnCase, async: false
  alias AtriumWeb.Plugs.TenantResolver
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "resolver_test", name: "Test"})
    {:ok, tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop("resolver_test") end)
    {:ok, tenant: tenant}
  end

  describe "call/2" do
    test "resolves tenant by subdomain and assigns tenant + prefix", %{conn: conn, tenant: tenant} do
      conn =
        conn
        |> Map.put(:host, "resolver_test.atrium.example")
        |> TenantResolver.call([])

      assert conn.assigns.tenant.id == tenant.id
      assert conn.assigns.tenant_prefix == Triplex.to_prefix("resolver_test")
    end

    test "returns 404 for unknown subdomain", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "nope.atrium.example")
        |> TenantResolver.call([])

      assert conn.status == 404
      assert conn.halted
    end

    test "returns 503 for suspended tenant", %{conn: conn, tenant: tenant} do
      {:ok, _} = Provisioner.suspend(tenant)

      conn =
        conn
        |> Map.put(:host, "resolver_test.atrium.example")
        |> TenantResolver.call([])

      assert conn.status == 503
      assert conn.halted
    end

    test "halts for platform host (admin.*)", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "admin.atrium.example")
        |> TenantResolver.call([])

      assert conn.halted
      assert conn.status == 400
    end
  end
end
