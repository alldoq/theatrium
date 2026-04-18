defmodule Atrium.Audit.RetentionSweeperTest do
  use Atrium.TenantCase
  alias Atrium.Audit
  alias Atrium.Audit.RetentionSweeper

  test "sweeps rows older than the tenant's retention window", %{tenant: tenant, tenant_prefix: prefix} do
    {:ok, old} = Audit.log(prefix, "test.old", %{actor: :system})
    # backdate only the specific row
    Atrium.Repo.query!(
      "UPDATE #{Triplex.to_prefix(tenant.slug)}.audit_events SET occurred_at = NOW() - INTERVAL '1000 days' WHERE id = '#{old.id}'"
    )
    {:ok, _new} = Audit.log(prefix, "test.new", %{actor: :system})

    # set retention shorter than 1000 days
    {:ok, _} = Atrium.Tenants.update_tenant(tenant, %{audit_retention_days: 30})
    tenant = Atrium.Tenants.get_tenant!(tenant.id)

    {:ok, purged} = RetentionSweeper.sweep(tenant)
    assert purged == 1

    rows = Audit.list(prefix)
    actions = Enum.map(rows, & &1.action)
    refute "test.old" in actions
    assert Enum.any?(actions, &(&1 == "test.new" or &1 == "audit.retention_swept"))
  end
end
