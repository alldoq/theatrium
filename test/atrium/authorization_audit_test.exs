defmodule Atrium.AuthorizationAuditTest do
  use Atrium.TenantCase
  alias Atrium.Accounts
  alias Atrium.Audit
  alias Atrium.Authorization

  test "grant and revoke section ACL produces audit events", %{tenant_prefix: prefix} do
    {:ok, g} = Authorization.create_group(prefix, %{slug: "writers", name: "W"})
    {:ok, _} = Authorization.grant_section(prefix, "news", {:group, g.id}, :view)
    :ok = Authorization.revoke_section(prefix, "news", {:group, g.id}, :view)

    actions = Audit.list(prefix) |> Enum.map(& &1.action)
    assert "group.created" in actions
    assert "section_acl.granted" in actions
    assert "section_acl.revoked" in actions
  end

  test "membership add and remove produces events", %{tenant_prefix: prefix} do
    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, u} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    {:ok, g} = Authorization.create_group(prefix, %{slug: "x", name: "X"})
    {:ok, _} = Authorization.add_member(prefix, u, g)
    :ok = Authorization.remove_member(prefix, u, g)

    actions = Audit.list(prefix) |> Enum.map(& &1.action)
    assert "membership.added" in actions
    assert "membership.removed" in actions
  end
end
