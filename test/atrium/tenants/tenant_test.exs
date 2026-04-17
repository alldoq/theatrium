defmodule Atrium.Tenants.TenantTest do
  use Atrium.DataCase, async: true
  alias Atrium.Tenants.Tenant

  describe "create_changeset/2" do
    test "requires slug, name" do
      changeset = Tenant.create_changeset(%Tenant{}, %{})
      refute changeset.valid?
      assert %{slug: ["can't be blank"], name: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates slug format (lowercase, underscores, must start with letter)" do
      for bad <- ["MCL", "mcl!", "-mcl", "1mcl", "mcl-"] do
        changeset = Tenant.create_changeset(%Tenant{}, %{slug: bad, name: "x"})
        refute changeset.valid?, "expected #{inspect(bad)} to be invalid"
      end

      for good <- ["mcl", "alldoq", "brand_one", "b1"] do
        changeset = Tenant.create_changeset(%Tenant{}, %{slug: good, name: "x"})
        assert changeset.valid?, "expected #{inspect(good)} to be valid, got #{inspect(errors_on(changeset))}"
      end
    end

    test "defaults status to provisioning" do
      changeset = Tenant.create_changeset(%Tenant{}, %{slug: "mcl", name: "MCL"})
      assert get_field(changeset, :status) == "provisioning"
    end
  end

  describe "status_changeset/2" do
    test "valid statuses produce a valid changeset" do
      tenant = %Tenant{slug: "mcl", name: "MCL", status: "provisioning"}
      for status <- Tenant.statuses() do
        changeset = Tenant.status_changeset(tenant, status)
        assert changeset.valid?, "expected #{inspect(status)} to be valid"
      end
    end

    test "invalid status produces an invalid changeset" do
      tenant = %Tenant{slug: "mcl", name: "MCL", status: "provisioning"}
      changeset = Tenant.status_changeset(tenant, "invalid")
      refute changeset.valid?
      assert errors_on(changeset)[:status]
    end
  end

  describe "update_changeset/2" do
    test "does not allow changing slug" do
      tenant = %Tenant{slug: "mcl", name: "MCL", status: "active"}
      changeset = Tenant.update_changeset(tenant, %{slug: "new"})
      assert get_field(changeset, :slug) == "mcl"
    end

    test "allows updating theme via map" do
      tenant = %Tenant{slug: "mcl", name: "MCL", status: "active"}
      changeset = Tenant.update_changeset(tenant, %{theme: %{"primary" => "#FF0000"}})
      assert changeset.valid?
    end
  end
end
