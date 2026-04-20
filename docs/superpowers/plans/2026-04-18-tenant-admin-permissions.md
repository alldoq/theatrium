# Tenant Admin — User & Section Permissions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give designated tenant admins a UI to invite users, manage section permissions (view/edit/approve), and toggle admin status — all within the tenant app, no iex required.

**Architecture:** Add `is_admin` boolean to the tenant `users` table via a tenant migration. A new `RequireTenantAdmin` plug gates a `/admin` scope. Three HEEx views (user list, invite, user detail with permission grid) backed by a single `TenantAdmin.UserController`. Permission sync computes a diff against current ACLs and calls the existing `Atrium.Authorization` functions.

**Tech Stack:** Elixir/Phoenix 1.8, Ecto, PostgreSQL schema-per-tenant (Triplex), server-rendered HEEx, existing `Atrium.Authorization` context, `Atrium.Audit` for event logging.

---

## File Structure

**New files:**
- `priv/repo/tenant_migrations/20260422000010_add_is_admin_to_users.exs` — adds `is_admin` column
- `lib/atrium_web/plugs/require_tenant_admin.ex` — 403 unless `current_user.is_admin`
- `lib/atrium_web/controllers/tenant_admin/user_controller.ex` — index, new, create, show, update_permissions, toggle_admin, suspend, restore
- `lib/atrium_web/controllers/tenant_admin/user_html.ex` — embed_templates
- `lib/atrium_web/controllers/tenant_admin/user_html/index.html.heex`
- `lib/atrium_web/controllers/tenant_admin/user_html/new.html.heex`
- `lib/atrium_web/controllers/tenant_admin/user_html/show.html.heex`
- `test/atrium_web/controllers/tenant_admin/user_controller_test.exs`

**Modified files:**
- `lib/atrium/accounts/user.ex` — add `is_admin` field + `admin_changeset/2`
- `lib/atrium/accounts.ex` — add `set_admin/3`
- `lib/atrium_web/router.ex` — add `:require_tenant_admin` pipeline + `/admin` scope
- `lib/atrium_web/components/layouts/app.html.heex` — Admin sidebar entry

---

## Task 1: Migration + User Schema

**Files:**
- Create: `priv/repo/tenant_migrations/20260422000010_add_is_admin_to_users.exs`
- Modify: `lib/atrium/accounts/user.ex`
- Modify: `lib/atrium/accounts.ex`
- Test: `test/atrium/accounts_test.exs` (new file, schema test only)

- [ ] **Step 1: Write failing test**

```elixir
# test/atrium/accounts_test.exs
defmodule Atrium.Accounts.AdminTest do
  use Atrium.TenantCase, async: false
  alias Atrium.Accounts

  defp create_user(prefix) do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "admin_test_#{System.unique_integer([:positive])}@example.com",
      name: "Test User"
    })
    user
  end

  describe "set_admin/3" do
    test "sets is_admin to true", %{tenant_prefix: prefix} do
      user = create_user(prefix)
      assert user.is_admin == false
      {:ok, updated} = Accounts.set_admin(prefix, user, true)
      assert updated.is_admin == true
    end

    test "sets is_admin to false", %{tenant_prefix: prefix} do
      user = create_user(prefix)
      {:ok, user} = Accounts.set_admin(prefix, user, true)
      {:ok, updated} = Accounts.set_admin(prefix, user, false)
      assert updated.is_admin == false
    end

    test "logs user.admin_changed audit event", %{tenant_prefix: prefix} do
      user = create_user(prefix)
      {:ok, _} = Accounts.set_admin(prefix, user, true)
      events = Atrium.Audit.history_for(prefix, "User", user.id)
      assert Enum.any?(events, &(&1.action == "user.admin_changed"))
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/accounts_test.exs 2>&1 | head -10
```
Expected: compile error — `is_admin` not defined on User.

- [ ] **Step 3: Create migration**

```elixir
# priv/repo/tenant_migrations/20260422000010_add_is_admin_to_users.exs
defmodule Atrium.Repo.TenantMigrations.AddIsAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_admin, :boolean, null: false, default: false
    end
  end
end
```

- [ ] **Step 4: Add `is_admin` field to User schema**

In `lib/atrium/accounts/user.ex`, add the field after `field :last_login_at`:

```elixir
field :is_admin, :boolean, default: false
```

Add `admin_changeset/2` before the `statuses/0` function:

```elixir
def admin_changeset(user, is_admin) do
  change(user, is_admin: is_admin)
end
```

- [ ] **Step 5: Add `set_admin/3` to `lib/atrium/accounts.ex`**

Add after `restore_user/2`:

```elixir
def set_admin(prefix, %User{} = user, is_admin) when is_boolean(is_admin) do
  with {:ok, updated} <- user |> User.admin_changeset(is_admin) |> Repo.update(prefix: prefix),
       {:ok, _} <- Audit.log(prefix, "user.admin_changed", %{
         actor: :system,
         resource: {"User", updated.id},
         changes: %{"is_admin" => [user.is_admin, is_admin]}
       }) do
    {:ok, updated}
  end
end
```

Check that `Audit` is already aliased in `accounts.ex` — look at the top of the file and add `alias Atrium.Audit` if missing.

- [ ] **Step 6: Run migration**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix ecto.migrate 2>&1 | tail -5
```
Expected: "Already up" for the public schema (migration is tenant-only). The column will be added to tenant schemas when Triplex migrates them. For the test tenant, migrations run automatically via `TenantCase`.

- [ ] **Step 7: Run tests**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/accounts_test.exs 2>&1 | tail -5
```
Expected: 3 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add priv/repo/tenant_migrations/20260422000010_add_is_admin_to_users.exs lib/atrium/accounts/user.ex lib/atrium/accounts.ex test/atrium/accounts_test.exs && git commit -m "feat(tenant-admin): add is_admin to users, set_admin/3 context function"
```

---

## Task 2: RequireTenantAdmin Plug + Router Wiring

**Files:**
- Create: `lib/atrium_web/plugs/require_tenant_admin.ex`
- Modify: `lib/atrium_web/router.ex`
- Test: `test/atrium_web/plugs/require_tenant_admin_test.exs`

- [ ] **Step 1: Write failing plug test**

```elixir
# test/atrium_web/plugs/require_tenant_admin_test.exs
defmodule AtriumWeb.Plugs.RequireTenantAdminTest do
  use AtriumWeb.ConnCase, async: true

  alias AtriumWeb.Plugs.RequireTenantAdmin

  defp conn_with_user(is_admin) do
    build_conn()
    |> assign(:current_user, %Atrium.Accounts.User{
        id: Ecto.UUID.generate(),
        email: "u@test.com",
        name: "U",
        status: "active",
        is_admin: is_admin
      })
  end

  test "passes when current_user.is_admin is true" do
    conn = conn_with_user(true) |> RequireTenantAdmin.call([])
    refute conn.halted
  end

  test "returns 403 when current_user.is_admin is false" do
    conn = conn_with_user(false) |> RequireTenantAdmin.call([])
    assert conn.halted
    assert conn.status == 403
  end

  test "returns 403 when current_user is nil" do
    conn = build_conn() |> assign(:current_user, nil) |> RequireTenantAdmin.call([])
    assert conn.halted
    assert conn.status == 403
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium_web/plugs/require_tenant_admin_test.exs 2>&1 | head -10
```
Expected: compile error — `RequireTenantAdmin` not defined.

- [ ] **Step 3: Create the plug**

```elixir
# lib/atrium_web/plugs/require_tenant_admin.ex
defmodule AtriumWeb.Plugs.RequireTenantAdmin do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %{is_admin: true} ->
        conn

      _ ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(403, "Forbidden")
        |> halt()
    end
  end
end
```

- [ ] **Step 4: Run plug tests**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium_web/plugs/require_tenant_admin_test.exs 2>&1 | tail -5
```
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Add pipeline + scope to router**

In `lib/atrium_web/router.ex`, add a new pipeline after the `:authenticated` pipeline:

```elixir
pipeline :require_tenant_admin do
  plug AtriumWeb.Plugs.RequireTenantAdmin
end
```

Then add a new scope inside the tenant scope (after the existing authenticated scope that ends at the document routes):

```elixir
scope "/admin", AtriumWeb.TenantAdmin, as: :tenant_admin do
  pipe_through [:browser, :tenant, :authenticated, :require_tenant_admin]

  get  "/users",                    UserController, :index
  get  "/users/new",                UserController, :new
  post "/users",                    UserController, :create
  get  "/users/:id",                UserController, :show
  post "/users/:id/permissions",    UserController, :update_permissions
  post "/users/:id/toggle_admin",   UserController, :toggle_admin
  post "/users/:id/suspend",        UserController, :suspend
  post "/users/:id/restore",        UserController, :restore
end
```

- [ ] **Step 6: Verify router compiles**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix compile 2>&1 | grep -E "error|warning" | grep -v "^$" | head -10
```
Expected: no errors (warnings about undefined controller are fine at this stage).

- [ ] **Step 7: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add lib/atrium_web/plugs/require_tenant_admin.ex lib/atrium_web/router.ex test/atrium_web/plugs/require_tenant_admin_test.exs && git commit -m "feat(tenant-admin): RequireTenantAdmin plug + /admin router scope"
```

---

## Task 3: UserController + Templates

**Files:**
- Create: `lib/atrium_web/controllers/tenant_admin/user_controller.ex`
- Create: `lib/atrium_web/controllers/tenant_admin/user_html.ex`
- Create: `lib/atrium_web/controllers/tenant_admin/user_html/index.html.heex`
- Create: `lib/atrium_web/controllers/tenant_admin/user_html/new.html.heex`
- Create: `lib/atrium_web/controllers/tenant_admin/user_html/show.html.heex`
- Test: `test/atrium_web/controllers/tenant_admin/user_controller_test.exs`

- [ ] **Step 1: Write controller tests**

```elixir
# test/atrium_web/controllers/tenant_admin/user_controller_test.exs
defmodule AtriumWeb.TenantAdmin.UserControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Accounts, Authorization}

  @tenant_slug "admintest"

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)
    {:ok, tenant} = Atrium.Tenants.create_tenant_record(%{slug: @tenant_slug, name: "AdminTest"})
    {:ok, tenant} = Atrium.Tenants.Provisioner.provision(tenant)
    prefix = Triplex.to_prefix(@tenant_slug)

    {:ok, %{user: admin}} = Accounts.invite_user(prefix, %{email: "admin@t.com", name: "Admin"})
    Accounts.activate_user(prefix, admin.invitation_token_raw, "password123456")
    admin = Accounts.get_user(prefix, admin.id)
    {:ok, admin} = Accounts.set_admin(prefix, admin, true)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)
      Triplex.drop(@tenant_slug)
      t = Atrium.Tenants.get_tenant_by_slug(@tenant_slug)
      if t, do: Atrium.Repo.delete(t)
    end)

    {:ok, prefix: prefix, admin: admin, tenant: tenant}
  end

  defp authed_conn(admin) do
    # Build a conn with a real session cookie for the admin user
    # Use ConnCase's test helper: build_conn with host + session
    build_conn()
    |> Map.put(:host, "#{@tenant_slug}.localhost")
    |> assign(:current_user, admin)
    |> assign(:tenant, %Atrium.Tenants.Tenant{slug: @tenant_slug, name: "AdminTest", enabled_sections: [], status: "active"})
    |> assign(:tenant_prefix, "tenant_#{@tenant_slug}")
    |> assign(:nav, [])
  end

  describe "GET /admin/users" do
    test "renders user list for admin", %{admin: admin} do
      conn = authed_conn(admin) |> get("/admin/users")
      assert html_response(conn, 200) =~ "Users"
    end

    test "returns 403 for non-admin", %{prefix: prefix} do
      {:ok, %{user: user}} = Accounts.invite_user(prefix, %{email: "plain@t.com", name: "Plain"})
      conn = authed_conn(user) |> get("/admin/users")
      assert response(conn, 403)
    end
  end

  describe "POST /admin/users" do
    test "creates user and redirects to show", %{admin: admin} do
      conn = authed_conn(admin) |> post("/admin/users", %{"user" => %{"name" => "New User", "email" => "new@t.com", "is_admin" => "false", "sections" => %{}}})
      assert redirected_to(conn) =~ "/admin/users/"
    end
  end
end
```

Note: if `invitation_token_raw` is not a field on the User struct, check how `invite_user` returns the token — it returns `%{user: user, token: raw_token}`. Adjust the test setup to use the token from the tuple directly:

```elixir
{:ok, %{user: admin, token: token}} = Accounts.invite_user(prefix, %{email: "admin@t.com", name: "Admin"})
Accounts.activate_user(prefix, token, "password123456")
admin = Accounts.get_user(prefix, admin.id)
{:ok, admin} = Accounts.set_admin(prefix, admin, true)
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium_web/controllers/tenant_admin/user_controller_test.exs 2>&1 | head -10
```
Expected: compile error — `TenantAdmin.UserController` not defined.

- [ ] **Step 3: Create `user_html.ex`**

```elixir
# lib/atrium_web/controllers/tenant_admin/user_html.ex
defmodule AtriumWeb.TenantAdmin.UserHTML do
  use AtriumWeb, :html

  embed_templates "user_html/*"
end
```

- [ ] **Step 4: Create `user_controller.ex`**

```elixir
# lib/atrium_web/controllers/tenant_admin/user_controller.ex
defmodule AtriumWeb.TenantAdmin.UserController do
  use AtriumWeb, :controller

  alias Atrium.{Accounts, Authorization, Audit}
  alias Atrium.Authorization.SectionRegistry

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    users = Accounts.list_users(prefix)
    render(conn, :index, users: users)
  end

  def new(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    sections = enabled_sections(conn)
    render(conn, :new, sections: sections, changeset: Accounts.change_user(%Accounts.UserInviteParams{}))
  end

  def create(conn, %{"user" => params}) do
    prefix = conn.assigns.tenant_prefix
    actor = conn.assigns.current_user

    case Accounts.invite_user(prefix, %{name: params["name"], email: params["email"]}) do
      {:ok, %{user: user}} ->
        if params["is_admin"] == "true" do
          Accounts.set_admin(prefix, user, true)
        end

        desired = decode_section_params(params["sections"] || %{})
        sync_permissions(prefix, user, desired, actor)

        conn
        |> put_flash(:info, "Invitation sent to #{user.email}")
        |> redirect(to: ~p"/admin/users/#{user.id}")

      {:error, changeset} ->
        sections = enabled_sections(conn)
        render(conn, :new, sections: sections, changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = Accounts.get_user!(prefix, id)
    sections = enabled_sections(conn)
    current_grants = load_user_grants(prefix, user.id)
    render(conn, :show, user: user, sections: sections, current_grants: current_grants)
  end

  def update_permissions(conn, %{"id" => id, "sections" => section_params}) do
    prefix = conn.assigns.tenant_prefix
    actor = conn.assigns.current_user
    user = Accounts.get_user!(prefix, id)
    desired = decode_section_params(section_params)
    sync_permissions(prefix, user, desired, actor)

    conn
    |> put_flash(:info, "Permissions updated")
    |> redirect(to: ~p"/admin/users/#{user.id}")
  end

  def update_permissions(conn, %{"id" => id}) do
    # No sections submitted — clear all
    prefix = conn.assigns.tenant_prefix
    actor = conn.assigns.current_user
    user = Accounts.get_user!(prefix, id)
    sync_permissions(prefix, user, MapSet.new(), actor)

    conn
    |> put_flash(:info, "Permissions updated")
    |> redirect(to: ~p"/admin/users/#{user.id}")
  end

  def toggle_admin(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = Accounts.get_user!(prefix, id)
    {:ok, _} = Accounts.set_admin(prefix, user, !user.is_admin)

    conn
    |> put_flash(:info, "Admin status updated")
    |> redirect(to: ~p"/admin/users/#{user.id}")
  end

  def suspend(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = Accounts.get_user!(prefix, id)
    {:ok, _} = Accounts.suspend_user(prefix, user)

    conn
    |> put_flash(:info, "User suspended")
    |> redirect(to: ~p"/admin/users/#{user.id}")
  end

  def restore(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = Accounts.get_user!(prefix, id)
    {:ok, _} = Accounts.restore_user(prefix, user)

    conn
    |> put_flash(:info, "User restored")
    |> redirect(to: ~p"/admin/users/#{user.id}")
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp enabled_sections(conn) do
    tenant = conn.assigns.tenant
    enabled = MapSet.new(tenant.enabled_sections)

    SectionRegistry.all()
    |> Enum.filter(&MapSet.member?(enabled, to_string(&1.key)))
  end

  defp decode_section_params(section_params) do
    # section_params is %{"hr" => %{"view" => "true", "edit" => "true"}, "docs" => %{"view" => "true"}}
    for {section_key, caps} <- section_params,
        {cap, "true"} <- caps,
        into: MapSet.new() do
      {section_key, cap}
    end
  end

  defp load_user_grants(prefix, user_id) do
    SectionRegistry.all()
    |> Enum.flat_map(fn s ->
      Authorization.list_section_acls(prefix, to_string(s.key))
    end)
    |> Enum.filter(&(&1.principal_type == "user" and &1.principal_id == user_id))
    |> MapSet.new(&{&1.section_key, &1.capability})
  end

  defp sync_permissions(prefix, user, desired, actor) do
    current = load_user_grants(prefix, user.id)

    to_grant = MapSet.difference(desired, current)
    to_revoke = MapSet.difference(current, desired)

    Enum.each(to_grant, fn {section_key, cap} ->
      Authorization.grant_section(prefix, section_key, {:user, user.id}, cap, actor.id)
    end)

    Enum.each(to_revoke, fn {section_key, cap} ->
      Authorization.revoke_section(prefix, section_key, {:user, user.id}, cap)
    end)

    unless MapSet.equal?(desired, current) do
      Audit.log(prefix, "user.permissions_updated", %{
        actor: {:user, actor.id},
        resource: {"User", user.id},
        changes: %{
          "granted" => Enum.map(to_grant, fn {s, c} -> "#{s}:#{c}" end),
          "revoked" => Enum.map(to_revoke, fn {s, c} -> "#{s}:#{c}" end)
        }
      })
    end
  end
end
```

Note: `Accounts.get_user!/2` may not exist — check `lib/atrium/accounts.ex`. If only `get_user/2` exists (returns nil), add a bang version to `accounts.ex`:

```elixir
def get_user!(prefix, id) do
  Repo.get!(User, id, prefix: prefix)
end
```

Also add `change_user/1` to accounts.ex for the new form changeset:
```elixir
def change_user(%User{} = user \\ %User{}) do
  User.invite_changeset(user, %{})
end
```

- [ ] **Step 5: Create `index.html.heex`**

```heex
<%# lib/atrium_web/controllers/tenant_admin/user_html/index.html.heex %>
<div class="atrium-anim">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:24px">
    <div>
      <div class="atrium-page-eyebrow">Admin</div>
      <h1 class="atrium-page-title">Users</h1>
    </div>
    <a href={~p"/admin/users/new"} class="atrium-btn atrium-btn-primary">
      <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round">
        <path d="M8 3v10M3 8h10"/>
      </svg>
      Invite user
    </a>
  </div>

  <div class="atrium-card">
    <table class="atrium-table">
      <thead>
        <tr>
          <th>Name</th>
          <th>Email</th>
          <th>Status</th>
          <th>Role</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <%= for user <- @users do %>
          <tr>
            <td style="font-weight:500"><%= user.name %></td>
            <td style="font-family:'IBM Plex Mono',monospace;font-size:.8125rem;color:var(--text-secondary)"><%= user.email %></td>
            <td>
              <span class={"atrium-badge atrium-badge-#{user.status}"}>
                <%= user.status %>
              </span>
            </td>
            <td>
              <%= if user.is_admin do %>
                <span class="atrium-badge" style="background:var(--blue-50);color:var(--blue-600)">Admin</span>
              <% end %>
            </td>
            <td style="text-align:right">
              <a href={~p"/admin/users/#{user.id}"} class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.8125rem">Manage</a>
            </td>
          </tr>
        <% end %>
        <%= if @users == [] do %>
          <tr><td colspan="5" style="padding:32px;text-align:center;color:var(--text-tertiary)">No users yet.</td></tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

- [ ] **Step 6: Create `new.html.heex`**

```heex
<%# lib/atrium_web/controllers/tenant_admin/user_html/new.html.heex %>
<div class="atrium-anim" style="max-width:600px">
  <div style="margin-bottom:20px">
    <a href={~p"/admin/users"} style="font-size:.8125rem;color:var(--text-tertiary)">← Users</a>
  </div>

  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Admin</div>
    <h1 class="atrium-page-title">Invite user</h1>
  </div>

  <form action={~p"/admin/users"} method="post">
    <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />

    <div class="atrium-card" style="margin-bottom:16px">
      <div class="atrium-card-header"><div class="atrium-card-title">Details</div></div>
      <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:16px">
        <div>
          <label class="atrium-label">Name</label>
          <input type="text" name="user[name]" class="atrium-input" required />
        </div>
        <div>
          <label class="atrium-label">Email</label>
          <input type="email" name="user[email]" class="atrium-input" required />
        </div>
        <div style="display:flex;align-items:center;gap:8px">
          <input type="checkbox" name="user[is_admin]" value="true" id="is_admin" style="accent-color:var(--blue-500);width:15px;height:15px" />
          <label for="is_admin" style="font-size:.875rem;color:var(--text-secondary);cursor:pointer">Grant admin access</label>
        </div>
      </div>
    </div>

    <div class="atrium-card" style="margin-bottom:24px">
      <div class="atrium-card-header">
        <div class="atrium-card-title">Section access</div>
        <div style="font-size:.8125rem;color:var(--text-tertiary)">Optional — can be changed later</div>
      </div>
      <div class="atrium-card-body">
        <div style="display:grid;grid-template-columns:1fr auto auto auto;gap:0;border:1px solid var(--border);border-radius:var(--radius);overflow:hidden">
          <div style="padding:8px 12px;font-family:'IBM Plex Mono',monospace;font-size:.625rem;letter-spacing:.08em;text-transform:uppercase;color:var(--text-tertiary);border-bottom:1px solid var(--border)">Section</div>
          <%= for cap <- ["view", "edit", "approve"] do %>
            <div style="padding:8px 12px;font-family:'IBM Plex Mono',monospace;font-size:.625rem;letter-spacing:.08em;text-transform:uppercase;color:var(--text-tertiary);border-bottom:1px solid var(--border);text-align:center"><%= cap %></div>
          <% end %>
          <%= for section <- @sections do %>
            <div style="padding:10px 12px;font-size:.875rem;color:var(--text-primary);border-bottom:1px solid var(--border-subtle)"><%= section.name %></div>
            <%= for cap <- ["view", "edit", "approve"] do %>
              <div style="padding:10px 12px;text-align:center;border-bottom:1px solid var(--border-subtle)">
                <input type="checkbox" name={"user[sections][#{section.key}][#{cap}]"} value="true" style="accent-color:var(--blue-500);width:15px;height:15px" />
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>

    <div style="display:flex;gap:8px">
      <button type="submit" class="atrium-btn atrium-btn-primary">Send invitation</button>
      <a href={~p"/admin/users"} class="atrium-btn atrium-btn-ghost">Cancel</a>
    </div>
  </form>
</div>
```

- [ ] **Step 7: Create `show.html.heex`**

```heex
<%# lib/atrium_web/controllers/tenant_admin/user_html/show.html.heex %>
<div class="atrium-anim" style="max-width:680px">
  <div style="margin-bottom:20px">
    <a href={~p"/admin/users"} style="font-size:.8125rem;color:var(--text-tertiary)">← Users</a>
  </div>

  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:24px">
    <div>
      <div class="atrium-page-eyebrow">Admin</div>
      <h1 class="atrium-page-title"><%= @user.name %></h1>
      <div style="font-size:.875rem;color:var(--text-secondary);margin-top:2px"><%= @user.email %></div>
    </div>
    <div style="display:flex;gap:8px;align-items:center;margin-top:8px">
      <span class={"atrium-badge atrium-badge-#{@user.status}"}><%= @user.status %></span>
      <%= if @user.is_admin do %>
        <span class="atrium-badge" style="background:var(--blue-50);color:var(--blue-600)">Admin</span>
      <% end %>
    </div>
  </div>

  <%# Actions card %>
  <div class="atrium-card" style="margin-bottom:16px">
    <div class="atrium-card-header"><div class="atrium-card-title">Actions</div></div>
    <div class="atrium-card-body" style="display:flex;gap:8px;flex-wrap:wrap">
      <form action={~p"/admin/users/#{@user.id}/toggle_admin"} method="post" style="display:inline">
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <button type="submit" class="atrium-btn atrium-btn-ghost">
          <%= if @user.is_admin, do: "Remove admin", else: "Make admin" %>
        </button>
      </form>

      <%= if @user.status == "active" do %>
        <form action={~p"/admin/users/#{@user.id}/suspend"} method="post" style="display:inline">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <button type="submit" class="atrium-btn atrium-btn-ghost" style="color:var(--color-error)">Suspend</button>
        </form>
      <% end %>

      <%= if @user.status == "suspended" do %>
        <form action={~p"/admin/users/#{@user.id}/restore"} method="post" style="display:inline">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <button type="submit" class="atrium-btn atrium-btn-primary">Restore</button>
        </form>
      <% end %>
    </div>
  </div>

  <%# Permissions card %>
  <form action={~p"/admin/users/#{@user.id}/permissions"} method="post">
    <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
    <div class="atrium-card" style="margin-bottom:16px">
      <div class="atrium-card-header">
        <div class="atrium-card-title">Section permissions</div>
      </div>
      <div class="atrium-card-body">
        <div style="display:grid;grid-template-columns:1fr auto auto auto;gap:0;border:1px solid var(--border);border-radius:var(--radius);overflow:hidden">
          <div style="padding:8px 12px;font-family:'IBM Plex Mono',monospace;font-size:.625rem;letter-spacing:.08em;text-transform:uppercase;color:var(--text-tertiary);border-bottom:1px solid var(--border)">Section</div>
          <%= for cap <- ["view", "edit", "approve"] do %>
            <div style="padding:8px 12px;font-family:'IBM Plex Mono',monospace;font-size:.625rem;letter-spacing:.08em;text-transform:uppercase;color:var(--text-tertiary);border-bottom:1px solid var(--border);text-align:center"><%= cap %></div>
          <% end %>
          <%= for section <- @sections do %>
            <% key = to_string(section.key) %>
            <div style="padding:10px 12px;font-size:.875rem;color:var(--text-primary);border-bottom:1px solid var(--border-subtle)"><%= section.name %></div>
            <%= for cap <- ["view", "edit", "approve"] do %>
              <div style="padding:10px 12px;text-align:center;border-bottom:1px solid var(--border-subtle)">
                <input
                  type="checkbox"
                  name={"sections[#{key}][#{cap}]"}
                  value="true"
                  checked={MapSet.member?(@current_grants, {key, cap})}
                  style="accent-color:var(--blue-500);width:15px;height:15px"
                />
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    <button type="submit" class="atrium-btn atrium-btn-primary">Save permissions</button>
  </form>
</div>
```

- [ ] **Step 8: Run controller tests**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium_web/controllers/tenant_admin/user_controller_test.exs 2>&1 | tail -10
```
Expected: tests pass. If `get_user!/2` is missing, add it to `accounts.ex` as described in Step 4. If `change_user/1` is needed, add it too.

- [ ] **Step 9: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add lib/atrium_web/controllers/tenant_admin/ test/atrium_web/controllers/tenant_admin/ && git commit -m "feat(tenant-admin): UserController + index/new/show templates"
```

---

## Task 4: Sidebar Entry + Smoke Test

**Files:**
- Modify: `lib/atrium_web/components/layouts/app.html.heex`

- [ ] **Step 1: Add Admin sidebar entry**

In `lib/atrium_web/components/layouts/app.html.heex`, find the Audit Log sidebar entry block and add after it:

```heex
    <%= if assigns[:current_user] && @current_user.is_admin do %>
      <div class="atrium-sidebar-section">
        <a href={~p"/admin/users"} class="atrium-sidebar-item">
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75">
            <circle cx="8" cy="5" r="2.5" stroke-linecap="round"/>
            <path d="M2.5 13c0-3 2.5-4.5 5.5-4.5s5.5 1.5 5.5 4.5" stroke-linecap="round"/>
          </svg>
          Admin
        </a>
      </div>
    <% end %>
```

- [ ] **Step 2: Verify compile**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix compile 2>&1 | grep error | head -5
```
Expected: no errors.

- [ ] **Step 3: Run full test suite**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1 | tail -10
```
Expected: all tests pass (or pre-existing failures only — no new failures).

- [ ] **Step 4: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add lib/atrium_web/components/layouts/app.html.heex && git commit -m "feat(tenant-admin): add Admin sidebar entry for is_admin users"
```

---

## Task 5: Make First Admin via iex + Verify

This task is a one-time manual step to promote the existing user to admin so the UI can be used going forward.

- [ ] **Step 1: Promote user to admin in iex**

```elixir
prefix = "tenant_testdbg123"
user = Atrium.Accounts.list_users(prefix) |> hd()
Atrium.Accounts.set_admin(prefix, user, true)
```

- [ ] **Step 2: Visit `/admin/users` in the browser**

Log in as that user and navigate to `/admin/users`. The Admin entry should appear in the sidebar. The user list should show. Inviting a new user with sections checked should create the user and ACLs.

- [ ] **Step 3: Tag milestone**

```bash
cd /Users/marcinwalczak/Kod/atrium && git tag tenant-admin-complete
```
