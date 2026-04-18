defmodule Atrium.AuthorizationTest do
  use Atrium.TenantCase
  alias Atrium.Accounts
  alias Atrium.Authorization

  defp make_user(prefix, email) do
    {:ok, %{user: user, token: raw}} = Accounts.invite_user(prefix, %{email: email, name: email})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    user
  end

  describe "groups and memberships" do
    test "creates a group and adds a member", %{tenant_prefix: prefix} do
      {:ok, group} = Authorization.create_group(prefix, %{slug: "marketing", name: "Marketing"})
      user = make_user(prefix, "a@e.co")
      {:ok, _m} = Authorization.add_member(prefix, user, group)
      assert [%{id: gid}] = Authorization.list_groups_for_user(prefix, user)
      assert gid == group.id
    end

    test "removing membership revokes group", %{tenant_prefix: prefix} do
      {:ok, g} = Authorization.create_group(prefix, %{slug: "marketing", name: "Marketing"})
      u = make_user(prefix, "a@e.co")
      {:ok, _} = Authorization.add_member(prefix, u, g)
      :ok = Authorization.remove_member(prefix, u, g)
      assert [] = Authorization.list_groups_for_user(prefix, u)
    end
  end

  describe "ACL grants" do
    test "grant and list section ACL", %{tenant_prefix: prefix} do
      {:ok, group} = Authorization.create_group(prefix, %{slug: "x", name: "X"})
      {:ok, _} = Authorization.grant_section(prefix, "news", {:group, group.id}, :view)

      rows = Authorization.list_section_acls(prefix, "news")
      assert length(rows) == 1
    end

    test "revoke removes the ACL", %{tenant_prefix: prefix} do
      {:ok, group} = Authorization.create_group(prefix, %{slug: "x", name: "X"})
      {:ok, _} = Authorization.grant_section(prefix, "news", {:group, group.id}, :view)
      :ok = Authorization.revoke_section(prefix, "news", {:group, group.id}, :view)
      assert Authorization.list_section_acls(prefix, "news") == []
    end

    test "subsection grant", %{tenant_prefix: prefix} do
      {:ok, _ss} = Authorization.create_subsection(prefix, %{section_key: "hr", slug: "staff-docs", name: "Staff docs"})
      {:ok, group} = Authorization.create_group(prefix, %{slug: "pc", name: "PC"})
      {:ok, _} = Authorization.grant_subsection(prefix, "hr", "staff-docs", {:group, group.id}, :view)
      assert [_] = Authorization.list_subsection_acls(prefix, "hr", "staff-docs")
    end

    test "rejects subsection on a section that does not support them", %{tenant_prefix: prefix} do
      {:error, cs} = Authorization.create_subsection(prefix, %{section_key: "home", slug: "x", name: "X"})
      assert %{section_key: ["section does not support subsections"]} = errors_on(cs)
    end
  end
end
