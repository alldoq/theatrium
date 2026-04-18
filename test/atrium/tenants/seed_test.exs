defmodule Atrium.Tenants.SeedTest do
  use Atrium.DataCase, async: false
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner
  alias Atrium.Authorization

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)

    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "seed_test", name: "Seed Test"})

    on_exit(fn ->
      _ = Triplex.drop("seed_test")
      _ = Atrium.Repo.delete(tenant)
      Atrium.Repo.delete_all(Atrium.Audit.GlobalEvent)
      Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :manual)
    end)

    {:ok, tenant: tenant}
  end

  test "provisioning seeds system groups and default ACLs", %{tenant: tenant} do
    {:ok, _} = Provisioner.provision(tenant)
    prefix = Triplex.to_prefix(tenant.slug)

    # system groups
    for slug <- ~w(all_staff super_users people_and_culture it finance communications compliance_officers) do
      assert Authorization.get_group_by_slug(prefix, slug), "expected system group #{slug}"
    end

    # default ACLs for e.g. :news from SectionRegistry
    comms = Authorization.get_group_by_slug(prefix, "communications")
    news_acls = Authorization.list_section_acls(prefix, "news")
    assert Enum.any?(news_acls, fn a -> a.principal_type == "group" and a.principal_id == comms.id and a.capability == "edit" end)
  end
end
