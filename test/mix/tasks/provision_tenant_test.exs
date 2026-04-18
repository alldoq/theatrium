defmodule Mix.Tasks.Atrium.ProvisionTenantTest do
  use Atrium.DataCase, async: false
  alias Atrium.Tenants

  setup do
    # Triplex provisions schemas via spawned :proc_lib processes that cannot use
    # the SQL sandbox. Switch to :auto mode for the duration of the test.
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)

    on_exit(fn ->
      _ = Triplex.drop("task_test_mcl")
      Atrium.Repo.delete_all(Atrium.Tenants.Tenant)
      Atrium.Repo.delete_all(Atrium.Audit.GlobalEvent)
      Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :manual)
    end)

    :ok
  end

  test "creates and provisions a tenant from CLI args" do
    Mix.Tasks.Atrium.ProvisionTenant.run(["--slug", "task_test_mcl", "--name", "MCL"])

    tenant = Tenants.get_tenant_by_slug("task_test_mcl")
    assert tenant
    assert tenant.status == "active"
    assert Triplex.exists?("task_test_mcl")
  end

  test "exits with non-zero status on invalid slug" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Atrium.ProvisionTenant.run(["--slug", "INVALID", "--name", "x"])
    end
  end
end
