defmodule Atrium.Tenants.ProvisionerTest do
  use Atrium.DataCase, async: false
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup do
    on_exit(fn ->
      # Clean up any tenant schemas created by tests
      for slug <- ~w(pr_test_mcl pr_test_fail) do
        _ = Triplex.drop(slug)
      end
    end)

    :ok
  end

  describe "provision/1" do
    test "creates tenant schema and marks tenant active" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "pr_test_mcl", name: "MCL"})
      assert {:ok, provisioned} = Provisioner.provision(tenant)
      assert provisioned.status == "active"
      assert Triplex.exists?("pr_test_mcl")
    end

    test "writes audit_events_global entry on success" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "pr_test_mcl", name: "MCL"})
      {:ok, _} = Provisioner.provision(tenant)

      events = Atrium.Audit.list_global(action: "tenant.created")
      assert Enum.any?(events, fn e -> e.resource_id == tenant.id end)
    end

    test "rolls back tenant status when schema creation fails" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "pr_test_fail", name: "Fail"})
      Triplex.create("pr_test_fail")  # pre-create to force failure

      assert {:error, _reason} = Provisioner.provision(tenant)
      refreshed = Tenants.get_tenant!(tenant.id)
      assert refreshed.status == "provisioning"
    end
  end

  describe "suspend/1 and resume/1" do
    test "transitions an active tenant and audits both events" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "pr_test_mcl", name: "MCL"})
      {:ok, tenant} = Provisioner.provision(tenant)

      {:ok, suspended} = Provisioner.suspend(tenant)
      assert suspended.status == "suspended"

      {:ok, resumed} = Provisioner.resume(suspended)
      assert resumed.status == "active"

      actions = Atrium.Audit.list_global() |> Enum.map(& &1.action) |> Enum.uniq()
      assert "tenant.suspended" in actions
      assert "tenant.resumed" in actions
    end
  end
end
