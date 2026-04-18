defmodule Atrium.Authorization.PolicyTest do
  use Atrium.TenantCase

  alias Atrium.Accounts
  alias Atrium.Authorization
  alias Atrium.Authorization.Policy

  defp make_user(prefix, email) do
    {:ok, %{user: u, token: raw}} = Accounts.invite_user(prefix, %{email: email, name: email})
    {:ok, u} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    u
  end

  defp mk_group(prefix, slug) do
    case Authorization.get_group_by_slug(prefix, slug) do
      nil -> elem(Authorization.create_group(prefix, %{slug: slug, name: slug}), 1)
      group -> group
    end
  end

  describe "section-only grants" do
    test "direct user grant", %{tenant_prefix: prefix} do
      u = make_user(prefix, "a@e.co")
      {:ok, _} = Authorization.grant_section(prefix, "news", {:user, u.id}, :view)
      assert Policy.can?(prefix, u, :view, {:section, "news"})
      refute Policy.can?(prefix, u, :edit, {:section, "news"})
    end

    test "group grant via membership", %{tenant_prefix: prefix} do
      u = make_user(prefix, "a@e.co")
      g = mk_group(prefix, "writers")
      {:ok, _} = Authorization.add_member(prefix, u, g)
      {:ok, _} = Authorization.grant_section(prefix, "news", {:group, g.id}, :edit)
      assert Policy.can?(prefix, u, :edit, {:section, "news"})
    end

    test "no grant → denied", %{tenant_prefix: prefix} do
      u = make_user(prefix, "a@e.co")
      # all_staff has :view on news via seeded ACLs; test that a capability not granted to all_staff is denied
      refute Policy.can?(prefix, u, :edit, {:section, "news"})
    end
  end

  describe "subsection override rule" do
    setup %{tenant_prefix: prefix} do
      {:ok, _} = Authorization.create_subsection(prefix, %{section_key: "hr", slug: "staff-docs", name: "Staff"})
      :ok
    end

    test "absence of subsection ACL → falls through to section", %{tenant_prefix: prefix} do
      u = make_user(prefix, "a@e.co")
      g = mk_group(prefix, "all_staff")
      {:ok, _} = Authorization.add_member(prefix, u, g)
      {:ok, _} = Authorization.grant_section(prefix, "hr", {:group, g.id}, :view)
      assert Policy.can?(prefix, u, :view, {:subsection, "hr", "staff-docs"})
    end

    test "presence of subsection ACL → child wins for that principal", %{tenant_prefix: prefix} do
      u = make_user(prefix, "a@e.co")
      allstaff = mk_group(prefix, "all_staff")
      pc = mk_group(prefix, "people_and_culture")

      {:ok, _} = Authorization.add_member(prefix, u, allstaff)

      {:ok, _} = Authorization.grant_section(prefix, "hr", {:group, allstaff.id}, :view)
      {:ok, _} = Authorization.grant_subsection(prefix, "hr", "staff-docs", {:group, pc.id}, :view)

      # User is only in all_staff. Because any subsection ACL exists for all_staff? No — the rule is
      # per-PRINCIPAL. Since all_staff has no subsection ACL, the parent ACL applies. Result: grant.
      assert Policy.can?(prefix, u, :view, {:subsection, "hr", "staff-docs"})
    end

    test "subsection grants restrict when the principal itself has a subsection row", %{tenant_prefix: prefix} do
      u = make_user(prefix, "a@e.co")
      allstaff = mk_group(prefix, "all_staff")

      {:ok, _} = Authorization.add_member(prefix, u, allstaff)

      # Parent grants :view to all_staff. Subsection revokes by having an explicit ACL row
      # for all_staff with capability :edit (not :view). Because any subsection ACL row for a
      # principal flips it into "child decides" mode, all_staff now has only :edit on the
      # subsection. The user has no :view on the subsection.
      {:ok, _} = Authorization.grant_section(prefix, "hr", {:group, allstaff.id}, :view)
      {:ok, _} = Authorization.grant_subsection(prefix, "hr", "staff-docs", {:group, allstaff.id}, :edit)

      refute Policy.can?(prefix, u, :view, {:subsection, "hr", "staff-docs"})
      assert Policy.can?(prefix, u, :edit, {:subsection, "hr", "staff-docs"})
    end

    test "mixed principals: one blocked by subsection, another granted by parent", %{tenant_prefix: prefix} do
      u = make_user(prefix, "a@e.co")
      allstaff = mk_group(prefix, "all_staff")
      editors = mk_group(prefix, "editors")

      {:ok, _} = Authorization.add_member(prefix, u, allstaff)
      {:ok, _} = Authorization.add_member(prefix, u, editors)

      # editors has a subsection row for :edit → editors is in "child decides" mode and has only :edit.
      # all_staff has no subsection row → falls through to parent (:view granted at section level).
      {:ok, _} = Authorization.grant_section(prefix, "hr", {:group, allstaff.id}, :view)
      {:ok, _} = Authorization.grant_subsection(prefix, "hr", "staff-docs", {:group, editors.id}, :edit)

      # The user can view via all_staff → grant
      assert Policy.can?(prefix, u, :view, {:subsection, "hr", "staff-docs"})
      # The user can edit via editors → grant
      assert Policy.can?(prefix, u, :edit, {:subsection, "hr", "staff-docs"})
    end
  end

  describe "unknown inputs" do
    test "unknown section → false", %{tenant_prefix: prefix} do
      u = make_user(prefix, "a@e.co")
      refute Policy.can?(prefix, u, :view, {:section, "does-not-exist"})
    end

    test "invalid capability → false", %{tenant_prefix: prefix} do
      u = make_user(prefix, "a@e.co")
      refute Policy.can?(prefix, u, :nuke, {:section, "news"})
    end
  end
end
