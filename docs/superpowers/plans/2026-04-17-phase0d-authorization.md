# Atrium Phase 0d — Authorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add groups, memberships, the section registry (code-defined), runtime subsections, section and subsection ACLs, and the single `Authorization.Policy` module that resolves `can?/3`. Auto-maintain `all_staff` membership. Seed default ACLs on tenant provisioning.

**Architecture:** `Authorization` is a tenant-schema context. Sections are code-declared (one module = one source of truth for the 14 canonical keys and their default ACLs). Subsections live in the DB. ACL tables carry `(principal_type, principal_id, capability)`. The subsection-override rule is: *any* subsection ACL entry for a principal means the subsection is decided entirely by subsection ACLs for that principal; absence falls through to the parent section. The policy resolver is the only module that computes `can?`; every consumer calls it.

**Tech Stack:** Existing 0a–0c foundations. No new libraries.

---

## File Structure

```
lib/atrium/authorization.ex
lib/atrium/authorization/section_registry.ex
lib/atrium/authorization/group.ex
lib/atrium/authorization/membership.ex
lib/atrium/authorization/subsection.ex
lib/atrium/authorization/section_acl.ex
lib/atrium/authorization/subsection_acl.ex
lib/atrium/authorization/policy.ex
priv/repo/tenant_migrations/<ts>_create_groups.exs
priv/repo/tenant_migrations/<ts>_create_memberships.exs
priv/repo/tenant_migrations/<ts>_create_subsections.exs
priv/repo/tenant_migrations/<ts>_create_section_acls.exs
priv/repo/tenant_migrations/<ts>_create_subsection_acls.exs
lib/atrium/accounts/all_staff.ex            # auto-membership callback
lib/atrium/tenants/seed.ex                  # group + ACL seeds run at provision time
lib/atrium_web/plugs/authorize.ex           # thin wrapper around Policy for controllers
test/atrium/authorization/policy_test.exs
test/atrium/authorization_test.exs
test/atrium/authorization/section_registry_test.exs
test/atrium/accounts/all_staff_test.exs
test/atrium/tenants/seed_test.exs
test/atrium_web/plugs/authorize_test.exs
```

---

## Task 1: Tenant migrations for groups, memberships, subsections, ACLs

**Files:**
- Create: 5 migrations in `priv/repo/tenant_migrations/`

- [ ] **Step 1: Write migrations**

Create `priv/repo/tenant_migrations/20260419000001_create_groups.exs`:

```elixir
defmodule Atrium.Repo.TenantMigrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :kind, :string, null: false, default: "custom"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:groups, [:slug])
  end
end
```

Create `priv/repo/tenant_migrations/20260419000002_create_memberships.exs`:

```elixir
defmodule Atrium.Repo.TenantMigrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:memberships, [:user_id, :group_id])
    create index(:memberships, [:group_id])
  end
end
```

Create `priv/repo/tenant_migrations/20260419000003_create_subsections.exs`:

```elixir
defmodule Atrium.Repo.TenantMigrations.CreateSubsections do
  use Ecto.Migration

  def change do
    create table(:subsections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :section_key, :string, null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:subsections, [:section_key, :slug])
  end
end
```

Create `priv/repo/tenant_migrations/20260419000004_create_section_acls.exs`:

```elixir
defmodule Atrium.Repo.TenantMigrations.CreateSectionAcls do
  use Ecto.Migration

  def change do
    create table(:section_acls, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :section_key, :string, null: false
      add :principal_type, :string, null: false
      add :principal_id, :binary_id, null: false
      add :capability, :string, null: false
      add :granted_by, :binary_id
      add :granted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:section_acls, [:section_key, :principal_type, :principal_id, :capability],
      name: :section_acls_unique)
    create index(:section_acls, [:principal_type, :principal_id])
  end
end
```

Create `priv/repo/tenant_migrations/20260419000005_create_subsection_acls.exs`:

```elixir
defmodule Atrium.Repo.TenantMigrations.CreateSubsectionAcls do
  use Ecto.Migration

  def change do
    create table(:subsection_acls, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :section_key, :string, null: false
      add :subsection_slug, :string, null: false
      add :principal_type, :string, null: false
      add :principal_id, :binary_id, null: false
      add :capability, :string, null: false
      add :granted_by, :binary_id
      add :granted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:subsection_acls,
      [:section_key, :subsection_slug, :principal_type, :principal_id, :capability],
      name: :subsection_acls_unique)
    create index(:subsection_acls, [:principal_type, :principal_id])
    create index(:subsection_acls, [:section_key, :subsection_slug])
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat(authz): add tenant migrations for groups, memberships, subsections, acls"
```

---

## Task 2: SectionRegistry (the 14 canonical sections)

**Files:**
- Create: `lib/atrium/authorization/section_registry.ex`
- Test: `test/atrium/authorization/section_registry_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/atrium/authorization/section_registry_test.exs`:

```elixir
defmodule Atrium.Authorization.SectionRegistryTest do
  use ExUnit.Case, async: true
  alias Atrium.Authorization.SectionRegistry

  test "all/0 returns exactly 14 sections" do
    assert length(SectionRegistry.all()) == 14
  end

  test "each section has the required keys" do
    for s <- SectionRegistry.all() do
      assert Map.has_key?(s, :key)
      assert Map.has_key?(s, :name)
      assert Map.has_key?(s, :default_capabilities)
      assert Map.has_key?(s, :supports_subsections)
      assert Map.has_key?(s, :default_acls)
    end
  end

  test "keys are the canonical intranet keys" do
    expected = ~w(home news directory hr departments docs tools projects helpdesk learning events social compliance feedback)a
    actual = SectionRegistry.all() |> Enum.map(& &1.key) |> Enum.sort()
    assert actual == Enum.sort(expected)
  end

  test "get/1 returns a section by key" do
    assert %{key: :hr} = SectionRegistry.get(:hr)
    assert SectionRegistry.get(:nonexistent) == nil
  end

  test "capabilities/0 returns exactly [:view, :edit, :approve]" do
    assert SectionRegistry.capabilities() == [:view, :edit, :approve]
  end
end
```

- [ ] **Step 2: Run to fail**

```bash
mix test test/atrium/authorization/section_registry_test.exs
```

Expected: FAIL.

- [ ] **Step 3: Implement SectionRegistry**

Create `lib/atrium/authorization/section_registry.ex`:

```elixir
defmodule Atrium.Authorization.SectionRegistry do
  @moduledoc """
  The code-defined catalogue of the 14 canonical intranet sections, their
  default capabilities, and the default ACLs seeded on tenant provisioning.

  This is the single source of truth. Adding a 15th section is a code change
  plus (optionally) a default-ACLs-seed migration for existing tenants.
  """

  @capabilities [:view, :edit, :approve]

  @sections [
    %{
      key: :home,
      name: "Home",
      icon: "home",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :super_users, :edit}]
    },
    %{
      key: :news,
      name: "News & Announcements",
      icon: "megaphone",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :communications, :edit}, {:group, :communications, :approve}]
    },
    %{
      key: :directory,
      name: "Employee Directory",
      icon: "users",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :people_and_culture, :edit}]
    },
    %{
      key: :hr,
      name: "HR & People Services",
      icon: "heart",
      supports_subsections: true,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :people_and_culture, :edit}, {:group, :people_and_culture, :approve}]
    },
    %{
      key: :departments,
      name: "Departments & Teams",
      icon: "building",
      supports_subsections: true,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}]
    },
    %{
      key: :docs,
      name: "Documents & Knowledge Base",
      icon: "book",
      supports_subsections: true,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}]
    },
    %{
      key: :tools,
      name: "Tools & Applications",
      icon: "wrench",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :super_users, :edit}]
    },
    %{
      key: :projects,
      name: "Projects & Collaboration",
      icon: "kanban",
      supports_subsections: true,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}]
    },
    %{
      key: :helpdesk,
      name: "IT Support / Help Desk",
      icon: "life-buoy",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :it, :edit}, {:group, :it, :approve}]
    },
    %{
      key: :learning,
      name: "Learning & Development",
      icon: "graduation-cap",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :people_and_culture, :edit}]
    },
    %{
      key: :events,
      name: "Events & Calendar",
      icon: "calendar",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}]
    },
    %{
      key: :social,
      name: "Social / Community",
      icon: "chat",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :all_staff, :edit}]
    },
    %{
      key: :compliance,
      name: "Compliance & Policies",
      icon: "shield",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :compliance_officers, :edit}, {:group, :compliance_officers, :approve}]
    },
    %{
      key: :feedback,
      name: "Feedback & Surveys",
      icon: "message-circle",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :all_staff, :view}, {:group, :people_and_culture, :edit}, {:group, :people_and_culture, :approve}]
    }
  ]

  @section_keys Enum.map(@sections, & &1.key)

  def all, do: @sections
  def keys, do: @section_keys
  def capabilities, do: @capabilities

  def get(key) when is_atom(key) or is_binary(key) do
    k = if is_binary(key), do: String.to_existing_atom(key), else: key
    Enum.find(@sections, &(&1.key == k))
  rescue
    ArgumentError -> nil
  end
end
```

- [ ] **Step 4: Run test**

```bash
mix test test/atrium/authorization/section_registry_test.exs
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(authz): add SectionRegistry with the 14 canonical sections"
```

---

## Task 3: Group, Membership, Subsection, ACL schemas

**Files:**
- Create: 5 schema files under `lib/atrium/authorization/`

- [ ] **Step 1: Group schema**

Create `lib/atrium/authorization/group.ex`:

```elixir
defmodule Atrium.Authorization.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(system custom)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "groups" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :kind, :string, default: "custom"
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(group, attrs) do
    group
    |> cast(attrs, [:slug, :name, :description, :kind])
    |> validate_required([:slug, :name])
    |> validate_format(:slug, ~r/^[a-z0-9_]+$/, message: "lowercase alphanumeric + underscore")
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint(:slug)
  end

  def update_changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
  end
end
```

- [ ] **Step 2: Membership schema**

Create `lib/atrium/authorization/membership.ex`:

```elixir
defmodule Atrium.Authorization.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "memberships" do
    field :user_id, :binary_id
    field :group_id, :binary_id
    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(m, attrs) do
    m
    |> cast(attrs, [:user_id, :group_id])
    |> validate_required([:user_id, :group_id])
    |> unique_constraint([:user_id, :group_id])
  end
end
```

- [ ] **Step 3: Subsection schema**

Create `lib/atrium/authorization/subsection.ex`:

```elixir
defmodule Atrium.Authorization.Subsection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "subsections" do
    field :section_key, :string
    field :slug, :string
    field :name, :string
    field :description, :string
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(ss, attrs) do
    ss
    |> cast(attrs, [:section_key, :slug, :name, :description])
    |> validate_required([:section_key, :slug, :name])
    |> validate_format(:slug, ~r/^[a-z0-9_-]+$/)
    |> validate_section_supports_subsections()
    |> unique_constraint([:section_key, :slug])
  end

  defp validate_section_supports_subsections(cs) do
    case get_field(cs, :section_key) do
      nil -> cs
      key ->
        section = Atrium.Authorization.SectionRegistry.get(key)
        cond do
          is_nil(section) -> add_error(cs, :section_key, "unknown section")
          not section.supports_subsections -> add_error(cs, :section_key, "section does not support subsections")
          true -> cs
        end
    end
  end
end
```

- [ ] **Step 4: ACL schemas**

Create `lib/atrium/authorization/section_acl.ex`:

```elixir
defmodule Atrium.Authorization.SectionAcl do
  use Ecto.Schema
  import Ecto.Changeset

  @principal_types ~w(user group)
  @capabilities ~w(view edit approve)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "section_acls" do
    field :section_key, :string
    field :principal_type, :string
    field :principal_id, :binary_id
    field :capability, :string
    field :granted_by, :binary_id
    field :granted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(acl, attrs) do
    acl
    |> cast(attrs, [:section_key, :principal_type, :principal_id, :capability, :granted_by])
    |> validate_required([:section_key, :principal_type, :principal_id, :capability])
    |> validate_inclusion(:principal_type, @principal_types)
    |> validate_inclusion(:capability, @capabilities)
    |> validate_known_section()
    |> unique_constraint([:section_key, :principal_type, :principal_id, :capability],
      name: :section_acls_unique)
  end

  defp validate_known_section(cs) do
    case get_field(cs, :section_key) do
      nil -> cs
      key ->
        if Atrium.Authorization.SectionRegistry.get(key),
          do: cs,
          else: add_error(cs, :section_key, "unknown section")
    end
  end
end
```

Create `lib/atrium/authorization/subsection_acl.ex` with the same shape, adding a `subsection_slug` field and validating that the `(section_key, subsection_slug)` pair exists in `subsections`:

```elixir
defmodule Atrium.Authorization.SubsectionAcl do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "subsection_acls" do
    field :section_key, :string
    field :subsection_slug, :string
    field :principal_type, :string
    field :principal_id, :binary_id
    field :capability, :string
    field :granted_by, :binary_id
    field :granted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(acl, attrs) do
    acl
    |> cast(attrs, [:section_key, :subsection_slug, :principal_type, :principal_id, :capability, :granted_by])
    |> validate_required([:section_key, :subsection_slug, :principal_type, :principal_id, :capability])
    |> validate_inclusion(:principal_type, ~w(user group))
    |> validate_inclusion(:capability, ~w(view edit approve))
    |> unique_constraint([:section_key, :subsection_slug, :principal_type, :principal_id, :capability],
      name: :subsection_acls_unique)
  end
end
```

- [ ] **Step 5: Compile and commit**

```bash
mix compile --warnings-as-errors
git add -A
git commit -m "feat(authz): add Group, Membership, Subsection, and ACL schemas"
```

---

## Task 4: Authorization context (groups, memberships, subsections, ACLs)

**Files:**
- Create: `lib/atrium/authorization.ex`
- Test: `test/atrium/authorization_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/atrium/authorization_test.exs`:

```elixir
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
```

- [ ] **Step 2: Run to fail**

```bash
mix test test/atrium/authorization_test.exs
```

Expected: FAIL.

- [ ] **Step 3: Implement context**

Create `lib/atrium/authorization.ex`:

```elixir
defmodule Atrium.Authorization do
  @moduledoc """
  Groups, memberships, subsections, and ACL management for a tenant.

  All permission *decisions* live in `Atrium.Authorization.Policy`.
  """
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Authorization.{Group, Membership, Subsection, SectionAcl, SubsectionAcl}
  alias Atrium.Accounts.User

  # Groups -----------------------------------------------------------------

  def create_group(prefix, attrs) do
    %Group{}
    |> Group.create_changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  def update_group(prefix, %Group{} = group, attrs) do
    group |> Group.update_changeset(attrs) |> Repo.update(prefix: prefix)
  end

  def delete_group(prefix, %Group{kind: "system"}), do: {:error, :cannot_delete_system_group}
  def delete_group(prefix, %Group{} = group), do: Repo.delete(group, prefix: prefix)

  def get_group!(prefix, id), do: Repo.get!(Group, id, prefix: prefix)
  def get_group_by_slug(prefix, slug), do: Repo.get_by(Group, [slug: slug], prefix: prefix)

  def list_groups(prefix) do
    Repo.all(from(g in Group, order_by: [asc: g.name]), prefix: prefix)
  end

  # Memberships ------------------------------------------------------------

  def add_member(prefix, %User{id: uid}, %Group{id: gid}) do
    %Membership{}
    |> Membership.changeset(%{user_id: uid, group_id: gid})
    |> Repo.insert(prefix: prefix, on_conflict: :nothing, conflict_target: [:user_id, :group_id])
  end

  def remove_member(prefix, %User{id: uid}, %Group{id: gid}) do
    {_count, _} =
      Repo.delete_all(
        from(m in Membership, where: m.user_id == ^uid and m.group_id == ^gid),
        prefix: prefix
      )

    :ok
  end

  def list_groups_for_user(prefix, %User{id: uid}) do
    Repo.all(
      from(g in Group,
        join: m in Membership, on: m.group_id == g.id,
        where: m.user_id == ^uid,
        order_by: [asc: g.name]
      ),
      prefix: prefix
    )
  end

  def list_members(prefix, %Group{id: gid}) do
    Repo.all(
      from(u in User,
        join: m in Membership, on: m.user_id == u.id,
        where: m.group_id == ^gid,
        order_by: [asc: u.email]
      ),
      prefix: prefix
    )
  end

  # Subsections ------------------------------------------------------------

  def create_subsection(prefix, attrs) do
    %Subsection{}
    |> Subsection.create_changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  def delete_subsection(prefix, %Subsection{} = ss) do
    Repo.transaction(fn ->
      Repo.delete_all(
        from(a in SubsectionAcl,
          where: a.section_key == ^ss.section_key and a.subsection_slug == ^ss.slug
        ),
        prefix: prefix
      )

      Repo.delete(ss, prefix: prefix)
    end)
  end

  def list_subsections(prefix, section_key) do
    Repo.all(
      from(s in Subsection, where: s.section_key == ^section_key, order_by: [asc: s.name]),
      prefix: prefix
    )
  end

  # Section ACLs -----------------------------------------------------------

  def grant_section(prefix, section_key, principal, capability, granted_by \\ nil)

  def grant_section(prefix, section_key, {type, id}, capability, granted_by) when type in [:user, :group] do
    %SectionAcl{}
    |> SectionAcl.changeset(%{
      section_key: to_string(section_key),
      principal_type: to_string(type),
      principal_id: id,
      capability: to_string(capability),
      granted_by: granted_by
    })
    |> Repo.insert(prefix: prefix, on_conflict: :nothing, conflict_target: :section_acls_unique)
  end

  def revoke_section(prefix, section_key, {type, id}, capability) when type in [:user, :group] do
    {_count, _} =
      Repo.delete_all(
        from(a in SectionAcl,
          where:
            a.section_key == ^to_string(section_key) and
              a.principal_type == ^to_string(type) and
              a.principal_id == ^id and
              a.capability == ^to_string(capability)
        ),
        prefix: prefix
      )

    :ok
  end

  def list_section_acls(prefix, section_key) do
    Repo.all(
      from(a in SectionAcl, where: a.section_key == ^to_string(section_key)),
      prefix: prefix
    )
  end

  # Subsection ACLs --------------------------------------------------------

  def grant_subsection(prefix, section_key, subsection_slug, principal, capability, granted_by \\ nil)

  def grant_subsection(prefix, section_key, subsection_slug, {type, id}, capability, granted_by)
      when type in [:user, :group] do
    %SubsectionAcl{}
    |> SubsectionAcl.changeset(%{
      section_key: to_string(section_key),
      subsection_slug: subsection_slug,
      principal_type: to_string(type),
      principal_id: id,
      capability: to_string(capability),
      granted_by: granted_by
    })
    |> Repo.insert(prefix: prefix, on_conflict: :nothing, conflict_target: :subsection_acls_unique)
  end

  def revoke_subsection(prefix, section_key, subsection_slug, {type, id}, capability)
      when type in [:user, :group] do
    {_count, _} =
      Repo.delete_all(
        from(a in SubsectionAcl,
          where:
            a.section_key == ^to_string(section_key) and
              a.subsection_slug == ^subsection_slug and
              a.principal_type == ^to_string(type) and
              a.principal_id == ^id and
              a.capability == ^to_string(capability)
        ),
        prefix: prefix
      )

    :ok
  end

  def list_subsection_acls(prefix, section_key, subsection_slug) do
    Repo.all(
      from(a in SubsectionAcl,
        where: a.section_key == ^to_string(section_key) and a.subsection_slug == ^subsection_slug
      ),
      prefix: prefix
    )
  end
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/atrium/authorization_test.exs
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(authz): add Authorization context (groups, memberships, subsections, ACLs)"
```

---

## Task 5: Policy resolver

**Files:**
- Create: `lib/atrium/authorization/policy.ex`
- Test: `test/atrium/authorization/policy_test.exs`

- [ ] **Step 1: Write the exhaustive failing test**

Create `test/atrium/authorization/policy_test.exs`:

```elixir
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

  defp mk_group(prefix, slug), do: elem(Authorization.create_group(prefix, %{slug: slug, name: slug}), 1)

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
      refute Policy.can?(prefix, u, :view, {:section, "news"})
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
```

- [ ] **Step 2: Run to fail**

```bash
mix test test/atrium/authorization/policy_test.exs
```

Expected: FAIL.

- [ ] **Step 3: Implement Policy**

Create `lib/atrium/authorization/policy.ex`:

```elixir
defmodule Atrium.Authorization.Policy do
  @moduledoc """
  The single source of truth for "can this user do X on target Y?".

  Rule:
  - principals = [{:user, user.id}] ++ [{:group, gid} for gid in user's groups]
  - For target {:subsection, section, sub}: for each principal, if any
    subsection ACL exists for that principal on that subsection (any capability),
    the subsection decides for that principal (child wins for that principal).
    Otherwise fall through to the section ACL.
  - For target {:section, section}: look up section ACL directly.
  """
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Accounts.User
  alias Atrium.Authorization
  alias Atrium.Authorization.{SectionAcl, SubsectionAcl, SectionRegistry}

  @type target :: {:section, String.t() | atom()} | {:subsection, String.t() | atom(), String.t()}
  @type capability :: :view | :edit | :approve

  @valid_caps [:view, :edit, :approve]

  @spec can?(String.t(), User.t(), capability(), target()) :: boolean()
  def can?(prefix, %User{} = user, capability, target) when capability in @valid_caps do
    section_key =
      case target do
        {:section, k} -> to_string(k)
        {:subsection, k, _} -> to_string(k)
      end

    cap = to_string(capability)

    cond do
      is_nil(SectionRegistry.get(section_key)) ->
        false

      match?({:subsection, _, _}, target) ->
        resolve_subsection(prefix, user, cap, target)

      true ->
        principals = principals_for(prefix, user)
        any_section_grant?(prefix, section_key, principals, cap)
    end
  end

  def can?(_prefix, _user, _capability, _target), do: false

  # Internal ---------------------------------------------------------------

  defp resolve_subsection(prefix, user, cap, {:subsection, section_key, sub_slug}) do
    section_key = to_string(section_key)
    principals = principals_for(prefix, user)

    # For each principal, determine effective ACL set on this subsection.
    Enum.any?(principals, fn principal ->
      case subsection_rows_for(prefix, section_key, sub_slug, principal) do
        [] ->
          # Fall through to parent for this principal
          section_grant?(prefix, section_key, principal, cap)

        rows ->
          # Child decides for this principal
          Enum.any?(rows, &(&1.capability == cap))
      end
    end)
  end

  defp principals_for(prefix, %User{id: id} = user) do
    group_ids = Authorization.list_groups_for_user(prefix, user) |> Enum.map(& &1.id)
    [{"user", id}] ++ Enum.map(group_ids, &{"group", &1})
  end

  defp subsection_rows_for(prefix, section_key, sub_slug, {ptype, pid}) do
    Repo.all(
      from(a in SubsectionAcl,
        where:
          a.section_key == ^section_key and
            a.subsection_slug == ^sub_slug and
            a.principal_type == ^ptype and
            a.principal_id == ^pid,
        select: a
      ),
      prefix: prefix
    )
  end

  defp any_section_grant?(prefix, section_key, principals, cap) do
    Enum.any?(principals, &section_grant?(prefix, section_key, &1, cap))
  end

  defp section_grant?(prefix, section_key, {ptype, pid}, cap) do
    Repo.exists?(
      from(a in SectionAcl,
        where:
          a.section_key == ^section_key and
            a.principal_type == ^ptype and
            a.principal_id == ^pid and
            a.capability == ^cap
      ),
      prefix: prefix
    )
  end
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/atrium/authorization/policy_test.exs
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(authz): add Policy.can?/4 with subsection override semantics"
```

---

## Task 6: Auto-maintain `all_staff` membership

**Files:**
- Create: `lib/atrium/accounts/all_staff.ex`
- Modify: `lib/atrium/accounts.ex` to call the callback on activate/suspend
- Test: `test/atrium/accounts/all_staff_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/atrium/accounts/all_staff_test.exs`:

```elixir
defmodule Atrium.Accounts.AllStaffTest do
  use Atrium.TenantCase
  alias Atrium.Accounts
  alias Atrium.Authorization
  alias Atrium.Authorization.Group

  setup %{tenant_prefix: prefix} do
    {:ok, _} = Authorization.create_group(prefix, %{slug: "all_staff", name: "All staff", kind: "system"})
    :ok
  end

  test "activating a user adds them to all_staff", %{tenant_prefix: prefix} do
    {:ok, %{user: u, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    groups = Authorization.list_groups_for_user(prefix, user)
    assert Enum.any?(groups, &(&1.slug == "all_staff"))
  end

  test "suspending a user removes them from all_staff", %{tenant_prefix: prefix} do
    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    {:ok, _} = Accounts.suspend_user(prefix, user)
    groups = Authorization.list_groups_for_user(prefix, user)
    refute Enum.any?(groups, &(&1.slug == "all_staff"))
  end
end
```

- [ ] **Step 2: Implement the callback**

Create `lib/atrium/accounts/all_staff.ex`:

```elixir
defmodule Atrium.Accounts.AllStaff do
  @moduledoc """
  Keeps the `all_staff` group in sync with active users.
  Called from `Accounts` on activate/suspend/restore.
  """
  alias Atrium.Authorization

  @slug "all_staff"

  def ensure_member(prefix, user) do
    case Authorization.get_group_by_slug(prefix, @slug) do
      nil -> :ok
      group -> Authorization.add_member(prefix, user, group)
    end

    :ok
  end

  def ensure_not_member(prefix, user) do
    case Authorization.get_group_by_slug(prefix, @slug) do
      nil -> :ok
      group -> Authorization.remove_member(prefix, user, group)
    end

    :ok
  end
end
```

- [ ] **Step 3: Wire callbacks into Accounts**

In `lib/atrium/accounts.ex`, after the user is successfully activated in `activate_user/3`, call:

```elixir
:ok = Atrium.Accounts.AllStaff.ensure_member(prefix, user)
```

In `suspend_user/2`, after successful update:

```elixir
:ok = Atrium.Accounts.AllStaff.ensure_not_member(prefix, user)
```

Also add a `restore_user/2` function symmetric to `suspend_user/2` that sets status back to `active` and calls `ensure_member`.

- [ ] **Step 4: Run tests**

```bash
mix test test/atrium/accounts/all_staff_test.exs
```

Expected: pass. Ensure existing 0b auth tests still pass: `mix test`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(accounts): auto-maintain all_staff membership on activate/suspend"
```

---

## Task 7: Tenant seed (system groups + default ACLs at provision time)

**Files:**
- Create: `lib/atrium/tenants/seed.ex`
- Modify: `lib/atrium/tenants/provisioner.ex` to call the seed
- Test: `test/atrium/tenants/seed_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/atrium/tenants/seed_test.exs`:

```elixir
defmodule Atrium.Tenants.SeedTest do
  use Atrium.DataCase, async: false
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner
  alias Atrium.Authorization

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "seed-test", name: "Seed Test"})

    on_exit(fn ->
      _ = Triplex.drop("seed-test")
      _ = Atrium.Repo.delete(tenant)
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
```

- [ ] **Step 2: Implement Seed**

Create `lib/atrium/tenants/seed.ex`:

```elixir
defmodule Atrium.Tenants.Seed do
  @moduledoc """
  Runs when a tenant is first provisioned. Creates the system groups and
  default section ACLs declared by the SectionRegistry.
  """
  alias Atrium.Authorization
  alias Atrium.Authorization.SectionRegistry

  @system_groups [
    %{slug: "all_staff", name: "All staff", description: "Every active user"},
    %{slug: "super_users", name: "Super users", description: "Tenant administrators"},
    %{slug: "people_and_culture", name: "People & Culture", description: "HR team"},
    %{slug: "it", name: "IT", description: "IT team"},
    %{slug: "finance", name: "Finance", description: "Finance team"},
    %{slug: "communications", name: "Communications", description: "Communications team"},
    %{slug: "compliance_officers", name: "Compliance Officers", description: "Compliance"}
  ]

  def run(prefix) do
    seed_groups(prefix)
    seed_default_acls(prefix)
    :ok
  end

  defp seed_groups(prefix) do
    Enum.each(@system_groups, fn attrs ->
      Authorization.create_group(prefix, Map.put(attrs, :kind, "system"))
    end)
  end

  defp seed_default_acls(prefix) do
    Enum.each(SectionRegistry.all(), fn section ->
      Enum.each(section.default_acls, fn
        {:group, group_slug, capability} ->
          case Authorization.get_group_by_slug(prefix, to_string(group_slug)) do
            nil -> :ok
            group ->
              Authorization.grant_section(prefix, to_string(section.key), {:group, group.id}, capability)
          end
      end)
    end)
  end
end
```

- [ ] **Step 3: Call Seed from Provisioner**

In `lib/atrium/tenants/provisioner.ex`, inside `provision/2` immediately after `Triplex.create/1` succeeds and before the activation status update:

```elixir
case Triplex.create(tenant.slug) do
  {:ok, _schema} ->
    prefix = Triplex.to_prefix(tenant.slug)

    case Atrium.Tenants.Seed.run(prefix) do
      :ok ->
        case Tenants.update_status(tenant, "active") do
          # ... existing code
        end

      {:error, reason} ->
        _ = Triplex.drop(tenant.slug)
        {:error, reason}
    end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/atrium/tenants/seed_test.exs
mix test  # full suite
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(tenants): seed system groups and default ACLs on provision"
```

---

## Task 8: Authorize plug

**Files:**
- Create: `lib/atrium_web/plugs/authorize.ex`
- Test: `test/atrium_web/plugs/authorize_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/atrium_web/plugs/authorize_test.exs`:

```elixir
defmodule AtriumWeb.Plugs.AuthorizeTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.Accounts
  alias Atrium.Authorization
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner
  alias AtriumWeb.Plugs.Authorize

  setup %{conn: conn} do
    {:ok, t} = Tenants.create_tenant_record(%{slug: "authz-test", name: "A"})
    {:ok, t} = Provisioner.provision(t)
    prefix = Triplex.to_prefix(t.slug)

    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")

    conn =
      conn
      |> assign(:tenant, t)
      |> assign(:tenant_prefix, prefix)
      |> assign(:current_user, user)

    on_exit(fn -> _ = Triplex.drop("authz-test") end)
    {:ok, conn: conn, user: user, prefix: prefix}
  end

  test "allows when user has capability", %{conn: conn, user: user, prefix: prefix} do
    {:ok, _} = Authorization.grant_section(prefix, "news", {:user, user.id}, :view)
    conn = Authorize.call(conn, capability: :view, target: {:section, "news"})
    refute conn.halted
  end

  test "denies with 403 when user does not have capability", %{conn: conn} do
    conn = Authorize.call(conn, capability: :edit, target: {:section, "news"})
    assert conn.status == 403
    assert conn.halted
  end
end
```

- [ ] **Step 2: Implement plug**

Create `lib/atrium_web/plugs/authorize.ex`:

```elixir
defmodule AtriumWeb.Plugs.Authorize do
  @moduledoc """
  Gates a route on a capability + target pair. Example usage in a controller:

      plug AtriumWeb.Plugs.Authorize, capability: :view, target: {:section, "news"}

  Dynamic targets (e.g. when section comes from a URL param) are supported via
  passing a function: `target: &my_controller_module.target_for/1` that returns
  the target given the conn.
  """
  import Plug.Conn

  alias Atrium.Authorization.Policy

  def init(opts) do
    capability = Keyword.fetch!(opts, :capability)
    target = Keyword.fetch!(opts, :target)
    {capability, target}
  end

  def call(conn, opts) when is_list(opts), do: call(conn, init(opts))

  def call(conn, {capability, target}) do
    resolved_target =
      case target do
        fun when is_function(fun, 1) -> fun.(conn)
        t -> t
      end

    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    if Policy.can?(prefix, user, capability, resolved_target) do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(403, "Forbidden")
      |> halt()
    end
  end
end
```

- [ ] **Step 3: Run tests**

```bash
mix test test/atrium_web/plugs/authorize_test.exs
mix test
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(web): add Authorize plug as thin wrapper around Policy.can?"
```

---

## Task 9: Milestone tag

- [ ] **Step 1: Full test run and tag**

```bash
mix test
git tag phase-0d-complete
```

---

## Plan 0d complete

Plan 0e wires the `Audit` context into every mutating path across Phase 0 contexts, adds the tenant audit viewer and per-record history component, and delivers the app-shell pieces (nav driven by `enabled_sections` + Policy, CSS-custom-property theming).
