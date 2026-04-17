defmodule Atrium.TenantsTest do
  use Atrium.DataCase, async: true
  alias Atrium.Tenants
  alias Atrium.Tenants.Tenant

  describe "create_tenant_record/1" do
    test "inserts a tenant with status provisioning" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      assert tenant.status == "provisioning"
      assert tenant.slug == "mcl"
    end

    test "rejects duplicate slug" do
      {:ok, _} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      {:error, changeset} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL2"})
      assert "has already been taken" in errors_on(changeset).slug
    end
  end

  describe "get_tenant_by_slug/1" do
    test "returns tenant when present" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      assert %Tenant{id: id} = Tenants.get_tenant_by_slug("mcl")
      assert id == tenant.id
    end

    test "returns nil when missing" do
      assert Tenants.get_tenant_by_slug("nope") == nil
    end
  end

  describe "update_status/2" do
    test "transitions tenant through statuses" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      {:ok, tenant} = Tenants.update_status(tenant, "active")
      assert tenant.status == "active"
      {:ok, tenant} = Tenants.update_status(tenant, "suspended")
      assert tenant.status == "suspended"
    end

    test "returns error changeset for invalid status" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      {:error, changeset} = Tenants.update_status(tenant, "invalid")
      assert errors_on(changeset)[:status]
    end
  end

  describe "update_tenant/2" do
    test "updates allowed fields" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      {:ok, updated} = Tenants.update_tenant(tenant, %{name: "MCL Ltd", theme: %{"primary" => "#FF0000"}})
      assert updated.name == "MCL Ltd"
      assert updated.theme["primary"] == "#FF0000"
    end
  end

  describe "list_active_tenants/0" do
    test "returns only active tenants" do
      {:ok, mcl} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      {:ok, _} = Tenants.create_tenant_record(%{slug: "alldoq", name: "ALLDOQ"})
      {:ok, _} = Tenants.update_status(mcl, "active")
      slugs = Tenants.list_active_tenants() |> Enum.map(& &1.slug)
      assert slugs == ["mcl"]
    end
  end
end
