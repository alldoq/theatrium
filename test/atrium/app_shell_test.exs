defmodule Atrium.AppShellTest do
  use Atrium.TenantCase
  alias Atrium.Accounts
  alias Atrium.AppShell
  alias Atrium.Authorization

  test "nav_for_user/3 returns only sections user can view", %{tenant: tenant, tenant_prefix: prefix} do
    {:ok, _} = Atrium.Tenants.update_tenant(tenant, %{enabled_sections: ~w(home news hr compliance)})
    tenant = Atrium.Tenants.get_tenant!(tenant.id)

    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")

    # all_staff has seeded :view on all sections — revoke hr and compliance so only home/news remain
    all_staff = Authorization.get_group_by_slug(prefix, "all_staff")
    :ok = Authorization.revoke_section(prefix, "hr", {:group, all_staff.id}, :view)
    :ok = Authorization.revoke_section(prefix, "compliance", {:group, all_staff.id}, :view)
    # ensure home and news grants exist (seeded, but be explicit)
    {:ok, _} = Authorization.grant_section(prefix, "home", {:group, all_staff.id}, :view)
    {:ok, _} = Authorization.grant_section(prefix, "news", {:group, all_staff.id}, :view)

    nav = AppShell.nav_for_user(tenant, user, prefix)
    keys = nav |> Enum.map(& &1.key) |> Enum.map(&to_string/1)
    assert "home" in keys
    assert "news" in keys
    refute "hr" in keys
    refute "compliance" in keys
  end

  test "subsections are included when user can view them", %{tenant: tenant, tenant_prefix: prefix} do
    {:ok, _} = Atrium.Tenants.update_tenant(tenant, %{enabled_sections: ~w(hr)})
    tenant = Atrium.Tenants.get_tenant!(tenant.id)

    {:ok, _} = Authorization.create_subsection(prefix, %{section_key: "hr", slug: "staff-docs", name: "Staff"})
    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    {:ok, g} = Authorization.create_group(prefix, %{slug: "pc_nav", name: "PC nav"})
    {:ok, _} = Authorization.add_member(prefix, user, g)
    {:ok, _} = Authorization.grant_section(prefix, "hr", {:group, g.id}, :view)
    {:ok, _} = Authorization.grant_subsection(prefix, "hr", "staff-docs", {:group, g.id}, :view)

    nav = AppShell.nav_for_user(tenant, user, prefix)
    hr = Enum.find(nav, &(&1.key == :hr))
    assert hr
    assert Enum.any?(hr.children, &(&1.slug == "staff-docs"))
  end
end
