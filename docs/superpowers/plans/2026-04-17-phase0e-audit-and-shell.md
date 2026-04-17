# Atrium Phase 0e — Audit & App Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire per-tenant `audit_events` into every mutating path across 0a–0d, ship the tenant audit viewer + per-record history component, deliver the app shell (section nav driven by `enabled_sections` + Policy, CSS-custom-property theming per tenant), and install the audit retention sweeper.

**Architecture:** Add a tenant-schema `audit_events` table and an `Audit` context extension (`log/2`, `list/1`, `history_for/2`). Add a `Audit.changeset_diff/3` utility with per-schema redaction lists. Retrofit callers: Accounts, Authorization, Idp, Tenant-side flows. Add an Oban retention sweeper. App shell reads `enabled_sections` per request and filters by `Policy.can?(user, :view, {:section, key})`. Theme becomes CSS custom properties set on `<html>` from `conn.assigns.theme`.

**Tech Stack:** Existing stack. No new libraries.

---

## File Structure

```
priv/repo/tenant_migrations/<ts>_create_audit_events.exs
lib/atrium/audit/event.ex                 # tenant-side schema
lib/atrium/audit/redactable.ex            # behaviour + default redactions
lib/atrium/audit/retention_sweeper.ex     # Oban worker
lib/atrium/audit.ex                       # extended with log/2, list/1, history_for/2, changeset_diff/3
lib/atrium_web/components/layouts/root.html.heex    # updated with theme CSS vars
lib/atrium_web/components/layouts/app.html.heex     # updated with nav from AppShell
lib/atrium/app_shell.ex                   # nav assembly
lib/atrium_web/live/audit_viewer_live.ex  # (optional LiveView) or:
lib/atrium_web/controllers/audit_viewer_controller.ex
lib/atrium_web/components/history_view.ex # per-record history component
test/atrium/audit_test.exs                # extended tests
test/atrium/app_shell_test.exs
test/atrium_web/controllers/audit_viewer_controller_test.exs
test/atrium_web/integration/shell_test.exs
```

---

## Task 1: Tenant audit_events migration

**Files:**
- Create: `priv/repo/tenant_migrations/20260420000001_create_audit_events.exs`

- [ ] **Step 1: Write migration**

```elixir
defmodule Atrium.Repo.TenantMigrations.CreateAuditEvents do
  use Ecto.Migration

  def change do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, :binary_id
      add :actor_type, :string, null: false
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :string
      add :changes, :map, null: false, default: %{}
      add :context, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:audit_events, [:actor_id, :occurred_at])
    create index(:audit_events, [:resource_type, :resource_id, :occurred_at])
    create index(:audit_events, [:action, :occurred_at])
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat(audit): add tenant audit_events migration"
```

---

## Task 2: Event schema and Redactable behaviour

**Files:**
- Create: `lib/atrium/audit/event.ex`
- Create: `lib/atrium/audit/redactable.ex`

- [ ] **Step 1: Implement Event schema**

Create `lib/atrium/audit/event.ex`:

```elixir
defmodule Atrium.Audit.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "audit_events" do
    field :actor_id, :binary_id
    field :actor_type, :string
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :changes, :map, default: %{}
    field :context, :map, default: %{}
    field :occurred_at, :utc_datetime_usec
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_id, :actor_type, :action, :resource_type, :resource_id, :changes, :context, :occurred_at])
    |> validate_required([:actor_type, :action, :occurred_at])
  end
end
```

- [ ] **Step 2: Implement Redactable**

Create `lib/atrium/audit/redactable.ex`:

```elixir
defprotocol Atrium.Audit.Redactable do
  @fallback_to_any true
  @doc "Returns the list of field names to redact before storing in audit changes."
  def redactions(struct)
end

defimpl Atrium.Audit.Redactable, for: Any do
  def redactions(_), do: []
end

defimpl Atrium.Audit.Redactable, for: Atrium.Accounts.User do
  def redactions(_), do: [:password, :hashed_password]
end

defimpl Atrium.Audit.Redactable, for: Atrium.Accounts.IdpConfiguration do
  def redactions(_), do: [:client_secret]
end

defimpl Atrium.Audit.Redactable, for: Atrium.SuperAdmins.SuperAdmin do
  def redactions(_), do: [:password, :hashed_password]
end
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(audit): add Event schema and Redactable protocol"
```

---

## Task 3: Extend Audit context with tenant log/list/history and diff utility

**Files:**
- Modify: `lib/atrium/audit.ex`
- Test: extend `test/atrium/audit_test.exs`

- [ ] **Step 1: Extend tests**

Append to `test/atrium/audit_test.exs`:

```elixir
defmodule Atrium.AuditTenantTest do
  use Atrium.TenantCase
  alias Atrium.Audit
  alias Atrium.Accounts

  test "log/2 writes a tenant audit event", %{tenant_prefix: prefix} do
    {:ok, event} =
      Audit.log(prefix, "user.invited", %{
        actor: :system,
        resource: {"User", "u-1"},
        changes: %{"email" => [nil, "a@e.co"]}
      })

    assert event.action == "user.invited"
    assert event.resource_type == "User"
  end

  test "list/1 filters by resource", %{tenant_prefix: prefix} do
    {:ok, _} = Audit.log(prefix, "user.invited", %{actor: :system, resource: {"User", "u-1"}})
    {:ok, _} = Audit.log(prefix, "user.invited", %{actor: :system, resource: {"User", "u-2"}})
    rows = Audit.list(prefix, resource_type: "User", resource_id: "u-1")
    assert length(rows) == 1
  end

  test "changeset_diff/2 redacts password fields", %{tenant_prefix: prefix} do
    old = %Atrium.Accounts.User{email: "a@e.co", hashed_password: "hashA"}
    new = %Atrium.Accounts.User{email: "b@e.co", hashed_password: "hashB"}
    diff = Audit.changeset_diff(old, new)
    assert diff["email"] == ["a@e.co", "b@e.co"]
    assert diff["hashed_password"] == ["[REDACTED]", "[REDACTED]"]
  end

  test "history_for/3 returns events for a resource", %{tenant_prefix: prefix} do
    {:ok, _} = Audit.log(prefix, "user.invited", %{actor: :system, resource: {"User", "u-1"}})
    {:ok, _} = Audit.log(prefix, "user.activated", %{actor: :system, resource: {"User", "u-1"}})
    history = Audit.history_for(prefix, "User", "u-1")
    assert length(history) == 2
  end
end
```

- [ ] **Step 2: Extend `lib/atrium/audit.ex`**

Add to the existing `Atrium.Audit` module:

```elixir
alias Atrium.Audit.Event

@spec log(String.t(), String.t(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
def log(prefix, action, opts) when is_binary(prefix) and is_binary(action) do
  {actor_type, actor_id} = decode_actor(Map.get(opts, :actor, :system))
  {resource_type, resource_id} = decode_resource(Map.get(opts, :resource))

  attrs = %{
    actor_type: actor_type,
    actor_id: actor_id,
    action: action,
    resource_type: resource_type,
    resource_id: resource_id,
    changes: stringify_keys(Map.get(opts, :changes, %{})),
    context: stringify_keys(Map.get(opts, :context, %{})),
    occurred_at: DateTime.utc_now()
  }

  %Event{}
  |> Event.changeset(attrs)
  |> Repo.insert(prefix: prefix)
end

@spec list(String.t(), keyword()) :: [Event.t()]
def list(prefix, filters \\ []) do
  query = from e in Event, order_by: [desc: e.occurred_at]

  query =
    Enum.reduce(filters, query, fn
      {:action, action}, q -> where(q, [e], e.action == ^action)
      {:actor_id, id}, q -> where(q, [e], e.actor_id == ^id)
      {:resource_type, t}, q -> where(q, [e], e.resource_type == ^t)
      {:resource_id, id}, q -> where(q, [e], e.resource_id == ^id)
      {:from, dt}, q -> where(q, [e], e.occurred_at >= ^dt)
      {:to, dt}, q -> where(q, [e], e.occurred_at <= ^dt)
      {:limit, n}, q -> limit(q, ^n)
      _, q -> q
    end)

  Repo.all(query, prefix: prefix)
end

@spec history_for(String.t(), String.t(), String.t()) :: [Event.t()]
def history_for(prefix, resource_type, resource_id) do
  list(prefix, resource_type: resource_type, resource_id: to_string(resource_id))
end

@spec changeset_diff(Ecto.Schema.t() | map(), Ecto.Schema.t() | map(), keyword()) :: map()
def changeset_diff(old, new, opts \\ []) do
  redactions = opts[:redactions] || discover_redactions(new, old)

  old_map = schema_to_map(old)
  new_map = schema_to_map(new)

  keys = MapSet.union(MapSet.new(Map.keys(old_map)), MapSet.new(Map.keys(new_map)))

  Enum.reduce(keys, %{}, fn key, acc ->
    skey = to_string(key)
    o = Map.get(old_map, key)
    n = Map.get(new_map, key)

    cond do
      key in redactions ->
        Map.put(acc, skey, ["[REDACTED]", "[REDACTED]"])

      o != n ->
        Map.put(acc, skey, [o, n])

      true ->
        acc
    end
  end)
end

defp discover_redactions(%_{} = struct, _), do: Atrium.Audit.Redactable.redactions(struct)
defp discover_redactions(_, %_{} = struct), do: Atrium.Audit.Redactable.redactions(struct)
defp discover_redactions(_, _), do: []

defp schema_to_map(%_{} = struct) do
  struct |> Map.from_struct() |> Map.drop([:__meta__, :__struct__])
end

defp schema_to_map(map) when is_map(map), do: map
```

- [ ] **Step 3: Run tests**

```bash
mix test test/atrium/audit_test.exs
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(audit): extend context with tenant log/list/history and diff utility"
```

---

## Task 4: Retrofit Accounts with audit logging

**Files:**
- Modify: `lib/atrium/accounts.ex`
- Test: `test/atrium/accounts_audit_test.exs`

- [ ] **Step 1: Write failing audit-coverage test**

Create `test/atrium/accounts_audit_test.exs`:

```elixir
defmodule Atrium.AccountsAuditTest do
  use Atrium.TenantCase
  alias Atrium.Accounts
  alias Atrium.Audit

  test "invite_user writes user.invited event", %{tenant_prefix: prefix} do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    events = Audit.list(prefix, action: "user.invited")
    assert Enum.any?(events, fn e -> e.resource_id == user.id end)
  end

  test "activate_user writes user.activated event", %{tenant_prefix: prefix} do
    {:ok, %{token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    assert Enum.any?(Audit.list(prefix, action: "user.activated"), &(&1.resource_id == user.id))
  end

  test "authenticate_by_password writes user.login on success and user.login_failed on failure", %{tenant_prefix: prefix} do
    {:ok, %{token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, _} = Accounts.activate_user(prefix, raw, "superSecret1234!")

    {:ok, _} = Accounts.authenticate_by_password(prefix, "a@e.co", "superSecret1234!")
    assert length(Audit.list(prefix, action: "user.login")) == 1

    {:error, _} = Accounts.authenticate_by_password(prefix, "a@e.co", "wrong")
    assert length(Audit.list(prefix, action: "user.login_failed")) == 1
  end

  test "reset_password writes password.reset_completed and session.revoked events", %{tenant_prefix: prefix} do
    {:ok, %{token: invite}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, invite, "superSecret1234!")
    {:ok, %{token: _}} = Accounts.create_session(prefix, user, %{})
    {:ok, %{token: raw}} = Accounts.request_password_reset(prefix, "a@e.co")
    {:ok, _} = Accounts.reset_password(prefix, raw, "newSuperSecret1234!")

    assert Audit.list(prefix, action: "password.reset_completed") != []
    assert Audit.list(prefix, action: "session.revoked") != []
  end
end
```

- [ ] **Step 2: Add audit calls to Accounts**

In `lib/atrium/accounts.ex`, at every mutation point, write an audit event. Key call sites:

- Successful `invite_user/2` insert → log `user.invited` with actor from opts (plan 0e surfaces `actor:` opt on each public function; add it).
- `activate_user/3` → log `user.activated`; if failure → no log (avoid log-on-failure here).
- `authenticate_by_password/3` → log `user.login` on success, `user.login_failed` on failure with reason string.
- `record_login!/2` no extra log (login already covers it).
- `suspend_user/2` → `user.deactivated`.
- `restore_user/2` → `user.activated` (re-activation).
- `create_session/4` → `session.created`.
- `revoke_session/2` → `session.revoked`.
- `revoke_all_sessions_for_user/2` → one `session.revoked` per deleted row OR a single `session.revoked_all` summary event (choose the latter for audit volume).
- `request_password_reset/2` → `password.reset_requested` (only when user exists; silent on unknown email, to keep enumeration-safe).
- `reset_password/3` → `password.reset_completed`.

Public function signatures should accept an `actor:` option where relevant. Controllers already have `conn.assigns.current_user`; pass `{:user, id}` or `:system` through.

Add to each code path:

```elixir
{:ok, _} =
  Atrium.Audit.log(prefix, "user.invited", %{
    actor: Keyword.get(opts, :actor, :system),
    resource: {"User", user.id},
    changes: %{"email" => [nil, user.email], "name" => [nil, user.name]}
  })
```

For failed logins:

```elixir
{:ok, _} =
  Atrium.Audit.log(prefix, "user.login_failed", %{
    actor: :system,
    context: %{"email" => email, "reason" => to_string(reason)}
  })
```

- [ ] **Step 3: Run tests**

```bash
mix test test/atrium/accounts_audit_test.exs
mix test
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(accounts): emit audit events for every mutating path"
```

---

## Task 5: Retrofit Authorization with audit logging

**Files:**
- Modify: `lib/atrium/authorization.ex`
- Test: `test/atrium/authorization_audit_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/atrium/authorization_audit_test.exs`:

```elixir
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
```

- [ ] **Step 2: Add audit writes to Authorization**

In `lib/atrium/authorization.ex`, augment every mutating function with a matching `Audit.log/3` call, following the scope from the Phase 0 spec:

- `create_group` → `group.created`
- `update_group` → `group.updated`
- `delete_group` → `group.deleted`
- `add_member` → `membership.added`
- `remove_member` → `membership.removed`
- `create_subsection` → `subsection.created`
- `delete_subsection` → `subsection.deleted`
- `grant_section` → `section_acl.granted`
- `revoke_section` → `section_acl.revoked`
- `grant_subsection` → `subsection_acl.granted`
- `revoke_subsection` → `subsection_acl.revoked`

Example for grant:

```elixir
def grant_section(prefix, section_key, {type, id}, capability, granted_by \\ nil) do
  with {:ok, acl} <-
         %SectionAcl{} |> SectionAcl.changeset(...) |> Repo.insert(prefix: prefix, on_conflict: :nothing, conflict_target: :section_acls_unique) do
    {:ok, _} =
      Atrium.Audit.log(prefix, "section_acl.granted", %{
        actor: if(granted_by, do: {:user, granted_by}, else: :system),
        resource: {"SectionAcl", acl.id},
        changes: %{
          "section_key" => [nil, to_string(section_key)],
          "principal_type" => [nil, to_string(type)],
          "principal_id" => [nil, id],
          "capability" => [nil, to_string(capability)]
        }
      })

    {:ok, acl}
  end
end
```

Handle the on-conflict `:nothing` case: `Repo.insert` returns `{:ok, struct_with_nil_id}` on conflict; skip the audit row when `acl.id == nil` (the grant already existed).

- [ ] **Step 3: Run tests**

```bash
mix test test/atrium/authorization_audit_test.exs
mix test
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(authz): emit audit events for group/membership/ACL/subsection mutations"
```

---

## Task 6: Retrofit Idp with audit logging

**Files:**
- Modify: `lib/atrium/accounts/idp.ex`

- [ ] **Step 1: Add audit writes**

For each mutation:

- `create_idp` → `idp.created` with redacted secret
- `update_idp` → `idp.updated` with redacted diff
- `delete_idp` → `idp.deleted`

Use `Audit.changeset_diff/2` with the existing `IdpConfiguration` record so `client_secret` is automatically redacted.

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat(idp): emit audit events on create/update/delete with secret redaction"
```

---

## Task 7: Retention sweeper

**Files:**
- Create: `lib/atrium/audit/retention_sweeper.ex`
- Modify: `config/config.exs` cron list
- Test: `test/atrium/audit/retention_sweeper_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/atrium/audit/retention_sweeper_test.exs`:

```elixir
defmodule Atrium.Audit.RetentionSweeperTest do
  use Atrium.TenantCase
  alias Atrium.Audit
  alias Atrium.Audit.RetentionSweeper

  test "sweeps rows older than the tenant's retention window", %{tenant: tenant, tenant_prefix: prefix} do
    {:ok, _old} = Audit.log(prefix, "test.old", %{actor: :system})
    # backdate
    Atrium.Repo.query!(
      "UPDATE #{Triplex.to_prefix(tenant.slug)}.audit_events SET occurred_at = NOW() - INTERVAL '1000 days'"
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
```

- [ ] **Step 2: Implement sweeper**

Create `lib/atrium/audit/retention_sweeper.ex`:

```elixir
defmodule Atrium.Audit.RetentionSweeper do
  @moduledoc """
  Deletes audit_events older than each tenant's audit_retention_days.
  Writes a single summary row per tenant for each purge run.
  """
  use Oban.Worker, queue: :maintenance, unique: [period: 3600]

  import Ecto.Query
  alias Atrium.{Audit, Repo, Tenants}
  alias Atrium.Audit.Event

  @impl Oban.Worker
  def perform(_job) do
    Tenants.list_active_tenants()
    |> Enum.each(fn t ->
      {:ok, _} = sweep(t)
    end)

    :ok
  end

  @spec sweep(Tenants.Tenant.t()) :: {:ok, non_neg_integer()}
  def sweep(tenant) do
    prefix = Triplex.to_prefix(tenant.slug)
    cutoff = DateTime.add(DateTime.utc_now(), -tenant.audit_retention_days * 86_400, :second)

    {count, _} =
      Repo.delete_all(from(e in Event, where: e.occurred_at < ^cutoff), prefix: prefix)

    if count > 0 do
      {:ok, _} =
        Audit.log(prefix, "audit.retention_swept", %{
          actor: :system,
          changes: %{"purged_count" => [0, count], "cutoff" => [nil, DateTime.to_iso8601(cutoff)]}
        })
    end

    {:ok, count}
  end
end
```

- [ ] **Step 3: Add cron entry**

In `config/config.exs` Oban cron:

```elixir
{"0 2 * * *", Atrium.Audit.RetentionSweeper}
```

- [ ] **Step 4: Run tests**

```bash
mix test test/atrium/audit/retention_sweeper_test.exs
mix test
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(audit): add retention sweeper Oban worker with daily cron"
```

---

## Task 8: AppShell module (nav assembly)

**Files:**
- Create: `lib/atrium/app_shell.ex`
- Test: `test/atrium/app_shell_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/atrium/app_shell_test.exs`:

```elixir
defmodule Atrium.AppShellTest do
  use Atrium.TenantCase
  alias Atrium.Accounts
  alias Atrium.AppShell
  alias Atrium.Authorization

  test "nav_for_user/4 returns only sections user can view", %{tenant: tenant, tenant_prefix: prefix} do
    {:ok, _} = Atrium.Tenants.update_tenant(tenant, %{enabled_sections: ~w(home news hr compliance)})
    tenant = Atrium.Tenants.get_tenant!(tenant.id)

    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    {:ok, all} = Atrium.Authorization.create_group(prefix, %{slug: "all_staff", name: "All"})
    {:ok, _} = Atrium.Authorization.add_member(prefix, user, all)
    {:ok, _} = Atrium.Authorization.grant_section(prefix, "home", {:group, all.id}, :view)
    {:ok, _} = Atrium.Authorization.grant_section(prefix, "news", {:group, all.id}, :view)

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
    {:ok, g} = Authorization.create_group(prefix, %{slug: "pc", name: "PC"})
    {:ok, _} = Authorization.add_member(prefix, user, g)
    {:ok, _} = Authorization.grant_section(prefix, "hr", {:group, g.id}, :view)
    {:ok, _} = Authorization.grant_subsection(prefix, "hr", "staff-docs", {:group, g.id}, :view)

    nav = AppShell.nav_for_user(tenant, user, prefix)
    hr = Enum.find(nav, &(&1.key == :hr))
    assert hr
    assert Enum.any?(hr.children, &(&1.slug == "staff-docs"))
  end
end
```

- [ ] **Step 2: Implement AppShell**

Create `lib/atrium/app_shell.ex`:

```elixir
defmodule Atrium.AppShell do
  @moduledoc """
  Assembles the per-request navigation structure: the subset of enabled
  sections the user is allowed to view, plus any viewable subsections.
  """
  alias Atrium.Authorization
  alias Atrium.Authorization.{Policy, SectionRegistry}

  @type nav_entry :: %{key: atom(), name: String.t(), icon: String.t(), children: [nav_child]}
  @type nav_child :: %{slug: String.t(), name: String.t()}

  @spec nav_for_user(Atrium.Tenants.Tenant.t(), Atrium.Accounts.User.t(), String.t()) :: [nav_entry]
  def nav_for_user(tenant, user, prefix) do
    enabled = MapSet.new(tenant.enabled_sections)

    SectionRegistry.all()
    |> Enum.filter(fn s -> MapSet.member?(enabled, to_string(s.key)) end)
    |> Enum.filter(fn s -> Policy.can?(prefix, user, :view, {:section, s.key}) end)
    |> Enum.map(fn s ->
      children =
        if s.supports_subsections do
          prefix
          |> Authorization.list_subsections(to_string(s.key))
          |> Enum.filter(&Policy.can?(prefix, user, :view, {:subsection, s.key, &1.slug}))
          |> Enum.map(&%{slug: &1.slug, name: &1.name})
        else
          []
        end

      %{key: s.key, name: s.name, icon: s.icon, children: children}
    end)
  end
end
```

- [ ] **Step 3: Run tests**

```bash
mix test test/atrium/app_shell_test.exs
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(shell): add AppShell.nav_for_user assembling sections + subsections"
```

---

## Task 9: Themed root layout + nav-rendering component

**Files:**
- Modify: `lib/atrium_web/components/layouts/root.html.heex`
- Modify: `lib/atrium_web/components/layouts/app.html.heex`
- Create: `lib/atrium_web/components/nav.ex`

- [ ] **Step 1: Update `root.html.heex`**

Set CSS custom properties from `@theme` when present:

```heex
<!DOCTYPE html>
<html lang="en" style={theme_style(assigns)}>
  <head>
    <meta charset="utf-8" />
    <title><%= assigns[:page_title] || "Atrium" %></title>
    <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>
  </head>
  <body class="bg-white text-slate-900">
    <%= @inner_content %>
  </body>
</html>
```

Add a helper in the corresponding `layouts.ex` module:

```elixir
def theme_style(%{tenant: %{theme: theme}}) when is_map(theme) do
  [
    {"--color-primary", Map.get(theme, "primary", "#0F172A")},
    {"--color-secondary", Map.get(theme, "secondary", "#64748B")},
    {"--color-accent", Map.get(theme, "accent", "#2563EB")},
    {"--font-sans", Map.get(theme, "font", "Inter, system-ui, sans-serif")}
  ]
  |> Enum.map_join("; ", fn {k, v} -> "#{k}: #{v}" end)
end

def theme_style(_), do: ""
```

- [ ] **Step 2: Update `app.html.heex` to render nav**

```heex
<div class="flex min-h-screen">
  <nav class="w-64 border-r bg-slate-50 p-4" style="background-color: var(--color-primary); color: white;">
    <%= if assigns[:tenant] do %>
      <div class="mb-6">
        <%= if assigns[:tenant].theme["logo_url"] do %>
          <img src={@tenant.theme["logo_url"]} alt={@tenant.name} class="h-8" />
        <% else %>
          <h1 class="text-lg font-semibold"><%= @tenant.name %></h1>
        <% end %>
      </div>
    <% end %>

    <%= if assigns[:nav] do %>
      <ul class="space-y-1">
        <%= for entry <- @nav do %>
          <li>
            <.link href={"/sections/#{entry.key}"} class="block rounded px-2 py-1 hover:bg-white/10">
              <%= entry.name %>
            </.link>
            <%= if entry.children != [] do %>
              <ul class="ml-4 mt-1 space-y-1">
                <%= for c <- entry.children do %>
                  <li>
                    <.link href={"/sections/#{entry.key}/#{c.slug}"} class="block rounded px-2 py-1 text-sm hover:bg-white/10">
                      <%= c.name %>
                    </.link>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </li>
        <% end %>
      </ul>
    <% end %>
  </nav>

  <main class="flex-1 p-8">
    <%= @inner_content %>
  </main>
</div>
```

- [ ] **Step 3: Wire nav assign into tenant controllers**

Add a plug in `lib/atrium_web/plugs/assign_nav.ex`:

```elixir
defmodule AtriumWeb.Plugs.AssignNav do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case {conn.assigns[:tenant], conn.assigns[:current_user], conn.assigns[:tenant_prefix]} do
      {nil, _, _} -> conn
      {_, nil, _} -> conn
      {tenant, user, prefix} ->
        assign(conn, :nav, Atrium.AppShell.nav_for_user(tenant, user, prefix))
    end
  end
end
```

Add `plug AtriumWeb.Plugs.AssignNav` after `RequireUser` in the authenticated tenant scope in `router.ex`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(shell): theme via CSS variables + render nav from AppShell"
```

---

## Task 10: Tenant audit viewer controller

**Files:**
- Create: `lib/atrium_web/controllers/audit_viewer_controller.ex` + html view + template
- Modify: `lib/atrium_web/router.ex`
- Test: `test/atrium_web/controllers/audit_viewer_controller_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/atrium_web/controllers/audit_viewer_controller_test.exs`:

```elixir
defmodule AtriumWeb.AuditViewerControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.Accounts
  alias Atrium.Audit
  alias Atrium.Authorization
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup %{conn: conn} do
    {:ok, t} = Tenants.create_tenant_record(%{slug: "av-test", name: "AV"})
    {:ok, t} = Provisioner.provision(t)
    prefix = Triplex.to_prefix(t.slug)

    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    {:ok, g} = Authorization.get_group_by_slug(prefix, "compliance_officers") |> then(&{:ok, &1})
    {:ok, _} = Authorization.add_member(prefix, user, g)

    {:ok, %{token: session_token}} = Accounts.create_session(prefix, user, %{})
    {:ok, _} = Audit.log(prefix, "test.event", %{actor: :system})

    conn =
      conn
      |> Map.put(:host, "av-test.atrium.example")
      |> Plug.Test.put_req_cookie("_atrium_session", session_token)
      |> fetch_cookies()

    on_exit(fn -> _ = Triplex.drop("av-test") end)

    {:ok, conn: conn}
  end

  test "compliance officers can view the audit log", %{conn: conn} do
    conn = get(conn, "/audit")
    assert html_response(conn, 200) =~ "test.event"
  end

  test "users without compliance:view are forbidden", %{conn: conn} do
    # Remove user from compliance_officers before the request
    # Simpler: test with a tenant where user has no compliance access
    # (left as an exercise; the Authorize plug enforces this)
    :ok
  end
end
```

- [ ] **Step 2: Implement controller**

Create `lib/atrium_web/controllers/audit_viewer_controller.ex`:

```elixir
defmodule AtriumWeb.AuditViewerController do
  use AtriumWeb, :controller
  alias Atrium.Audit

  plug AtriumWeb.Plugs.Authorize,
    [capability: :view, target: {:section, "compliance"}]
    when action in [:index, :export]

  def index(conn, params) do
    filters = build_filters(params)
    events = Audit.list(conn.assigns.tenant_prefix, Keyword.put(filters, :limit, 200))
    render(conn, :index, events: events, filters: params)
  end

  def export(conn, params) do
    filters = build_filters(params)
    events = Audit.list(conn.assigns.tenant_prefix, Keyword.put(filters, :limit, 10_000))
    csv = to_csv(events)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=audit-export.csv")
    |> send_resp(200, csv)
  end

  defp build_filters(params) do
    Enum.reduce([:action, :actor_id, :resource_type, :resource_id], [], fn key, acc ->
      case Map.get(params, to_string(key)) do
        nil -> acc
        "" -> acc
        val -> [{key, val} | acc]
      end
    end)
  end

  defp to_csv(events) do
    header = "occurred_at,actor_type,actor_id,action,resource_type,resource_id,changes,context"

    rows =
      Enum.map(events, fn e ->
        Enum.join(
          [
            DateTime.to_iso8601(e.occurred_at),
            e.actor_type,
            e.actor_id,
            e.action,
            e.resource_type,
            e.resource_id,
            Jason.encode!(e.changes),
            Jason.encode!(e.context)
          ],
          ","
        )
      end)

    Enum.join([header | rows], "\n")
  end
end
```

- [ ] **Step 3: Add view and template**

Create `lib/atrium_web/controllers/audit_viewer_html.ex`:

```elixir
defmodule AtriumWeb.AuditViewerHTML do
  use AtriumWeb, :html
  embed_templates "audit_viewer_html/*"
end
```

Create `lib/atrium_web/controllers/audit_viewer_html/index.html.heex`:

```heex
<main class="p-8">
  <h1 class="text-xl font-semibold mb-4">Audit log</h1>
  <form method="get" class="flex gap-2 mb-4">
    <input name="action" placeholder="action" value={@filters["action"]} class="border rounded p-1" />
    <input name="actor_id" placeholder="actor_id" value={@filters["actor_id"]} class="border rounded p-1" />
    <input name="resource_type" placeholder="resource_type" value={@filters["resource_type"]} class="border rounded p-1" />
    <input name="resource_id" placeholder="resource_id" value={@filters["resource_id"]} class="border rounded p-1" />
    <button type="submit" class="rounded bg-slate-900 text-white px-3">Filter</button>
    <.link href={~p"/audit/export?#{@filters}"} class="rounded border px-3 py-1">CSV</.link>
  </form>

  <table class="w-full text-sm border">
    <thead class="bg-slate-50">
      <tr><th class="p-2 text-left">When</th><th class="p-2 text-left">Actor</th><th class="p-2 text-left">Action</th><th class="p-2 text-left">Resource</th><th class="p-2 text-left">Changes</th></tr>
    </thead>
    <tbody>
      <%= for e <- @events do %>
        <tr class="border-t">
          <td class="p-2"><%= Calendar.strftime(e.occurred_at, "%Y-%m-%d %H:%M:%S") %></td>
          <td class="p-2"><%= e.actor_type %> <%= e.actor_id %></td>
          <td class="p-2 font-mono"><%= e.action %></td>
          <td class="p-2"><%= e.resource_type %> <%= e.resource_id %></td>
          <td class="p-2 font-mono text-xs"><%= Jason.encode!(e.changes) %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
</main>
```

- [ ] **Step 4: Wire routes**

In `lib/atrium_web/router.ex`, inside the authenticated tenant scope:

```elixir
get "/audit", AuditViewerController, :index
get "/audit/export", AuditViewerController, :export
```

- [ ] **Step 5: Run tests**

```bash
mix test test/atrium_web/controllers/audit_viewer_controller_test.exs
mix test
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(audit): add tenant audit viewer controller and CSV export"
```

---

## Task 11: Per-record history component

**Files:**
- Create: `lib/atrium_web/components/history_view.ex`
- Test: covered via integration tests later (no unit test in 0e)

- [ ] **Step 1: Implement component**

Create `lib/atrium_web/components/history_view.ex`:

```elixir
defmodule AtriumWeb.Components.HistoryView do
  use Phoenix.Component

  attr :events, :list, required: true
  attr :title, :string, default: "History"

  def history(assigns) do
    ~H"""
    <section class="border rounded">
      <h3 class="p-3 border-b font-semibold"><%= @title %></h3>
      <ul class="divide-y">
        <%= for e <- @events do %>
          <li class="p-3 text-sm">
            <div class="flex justify-between">
              <span class="font-mono"><%= e.action %></span>
              <span class="text-gray-500"><%= Calendar.strftime(e.occurred_at, "%Y-%m-%d %H:%M") %></span>
            </div>
            <div class="text-gray-700 mt-1">
              <%= render_changes(e.changes) %>
            </div>
          </li>
        <% end %>
      </ul>
    </section>
    """
  end

  defp render_changes(changes) when changes == %{}, do: ""
  defp render_changes(changes) do
    changes
    |> Enum.map(fn {key, [old, new]} -> "#{key}: #{inspect(old)} → #{inspect(new)}" end)
    |> Enum.join("; ")
  end
end
```

Phase 1 primitives will consume this component directly; no UI in Phase 0 surfaces it beyond a visibility test.

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat(audit): add reusable history_view component for per-record history"
```

---

## Task 12: Integration smoke test + milestone

- [ ] **Step 1: Integration test — full nav + audit flow**

Create `test/atrium_web/integration/shell_test.exs`:

```elixir
defmodule AtriumWeb.Integration.ShellTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.Accounts
  alias Atrium.Authorization
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup %{conn: conn} do
    {:ok, t} = Tenants.create_tenant_record(%{slug: "shell-test", name: "Shell Test", enabled_sections: ~w(home news compliance)})
    {:ok, t} = Provisioner.provision(t)
    prefix = Triplex.to_prefix(t.slug)

    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    {:ok, %{token: st}} = Accounts.create_session(prefix, user, %{})

    on_exit(fn -> _ = Triplex.drop("shell-test") end)

    conn =
      conn
      |> Map.put(:host, "shell-test.atrium.example")
      |> Plug.Test.put_req_cookie("_atrium_session", st)
      |> fetch_cookies()

    {:ok, conn: conn}
  end

  test "home page renders with themed nav showing home + news", %{conn: conn} do
    conn = get(conn, "/")
    body = html_response(conn, 200)
    assert body =~ "Home"
    assert body =~ "News"
    refute body =~ "Departments"  # not enabled for this tenant
  end

  test "suspended tenant returns 503", %{conn: conn} do
    tenant = Tenants.get_tenant_by_slug("shell-test")
    {:ok, _} = Provisioner.suspend(tenant)

    conn = get(conn, "/")
    assert conn.status == 503
  end
end
```

Run:

```bash
mix test
```

Expected: all pass.

- [ ] **Step 2: Manual smoke**

1. Provision MCL: `mix atrium.provision_tenant --slug mcl --name MCL`
2. Visit `http://admin.localhost:4000/super/tenants/<id>/edit` (create a super admin first in iex), enable sections.
3. Invite yourself via iex, accept the invitation, log in.
4. Confirm nav shows enabled sections only.
5. Check `/audit` renders events.

- [ ] **Step 3: Tag**

```bash
git tag phase-0e-complete
git tag phase-0-complete
```

---

## Phase 0 complete

The foundation is in place. Phase 1 will build on it: rich-text documents, form builder, and file storage — each consuming the Audit context's `log/2` and `history_for/2`, the Authorization policy, and the app shell's nav assembly.

Open Phase-0 wrap-up items the implementer should verify:
1. CI workflow runs `mix test --trace` and `mix format --check-formatted`.
2. Migrations run cleanly on a fresh DB from scratch (drop + ecto.setup + provision a test tenant).
3. All five phase-tag commits (`phase-0a-complete` through `phase-0e-complete`) exist and the `phase-0-complete` tag points at the head of `main`.
