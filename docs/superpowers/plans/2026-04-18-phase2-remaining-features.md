# Phase 2: Remaining Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the remaining P0/P1/P2 features in priority order to reach a launchable intranet by 01 June 2026.

**Architecture:** Each feature either adds a new controller/context (Home dashboard, Employee Directory, Tools, form notifications) or wires existing architecture to a UI (form version history, subsection management). All work is within the existing Phoenix + Triplex + Vue 3 island stack. No new dependencies needed except Swoosh (already present) for email dispatch.

**Tech Stack:** Elixir/Phoenix 1.8, Ecto + Triplex (schema-per-tenant), Vue 3 SFC islands, atrium-* CSS design system, Swoosh mailer, Oban (if present, else Task.async), HtmlSanitizeEx

**Build order (matches gap analysis priority):**
- Week 1–2: Task 1 (Home dashboard) → Task 2 (News feed UI)
- Week 2–3: Task 3 (Employee Directory) → Task 4 (Subsection management UI)
- Week 3–4: Task 5 (Form notification email fanout) → Task 6 (Form version history view)
- Week 4–5: Task 7 (Tools launchpad) → Task 8 (Compliance policies view) → Task 9 (IT helpdesk ticket view)
- Week 5–6: Task 10 (Polish + brand instance setup checklist)

**Status tracking:** Update `docs/superpowers/plans/2026-04-18-phase2-remaining-features.md` — check off each `- [ ]` step as it is completed.

---

## File map

| File | Action | Purpose |
|---|---|---|
| `lib/atrium/home.ex` | Create | Announcements + quick links context |
| `lib/atrium/home/announcement.ex` | Create | Announcement schema |
| `lib/atrium/home/quick_link.ex` | Create | QuickLink schema |
| `priv/repo/tenant_migrations/20260501000001_create_announcements.exs` | Create | DB table |
| `priv/repo/tenant_migrations/20260501000002_create_quick_links.exs` | Create | DB table |
| `lib/atrium_web/controllers/home_controller.ex` | Create | Dashboard actions |
| `lib/atrium_web/controllers/home_html.ex` | Create | Template module |
| `lib/atrium_web/controllers/home_html/show.html.heex` | Create | Dashboard page |
| `lib/atrium_web/router.ex` | Modify | Add home route |
| `test/atrium/home_test.exs` | Create | Context tests |
| `lib/atrium/directory.ex` | Create | Directory context (wraps users + groups) |
| `lib/atrium_web/controllers/directory_controller.ex` | Create | Directory actions |
| `lib/atrium_web/controllers/directory_html.ex` | Create | Template module |
| `lib/atrium_web/controllers/directory_html/index.html.heex` | Create | Searchable directory |
| `lib/atrium_web/controllers/directory_html/show.html.heex` | Create | User profile |
| `lib/atrium/accounts/user.ex` | Modify | Add role, department, bio, phone fields |
| `priv/repo/tenant_migrations/20260501000003_add_profile_fields_to_users.exs` | Create | Profile columns |
| `lib/atrium_web/controllers/tenant_admin/user_controller.ex` | Modify | Add profile edit action |
| `lib/atrium_web/controllers/tenant_admin/user_html/edit_profile.html.heex` | Create | Profile edit form |
| `lib/atrium/subsection_manager.ex` | Create | Subsection CRUD facade (already in Authorization, adds UI-friendly wrappers) |
| `lib/atrium_web/controllers/subsection_controller.ex` | Create | Subsection management actions |
| `lib/atrium_web/controllers/subsection_html.ex` | Create | Template module |
| `lib/atrium_web/controllers/subsection_html/index.html.heex` | Create | Subsection list per section |
| `lib/atrium_web/controllers/subsection_html/new.html.heex` | Create | Create subsection form |
| `lib/atrium/notifications/form_mailer.ex` | Create | Email dispatch for form submissions |
| `lib/atrium_web/controllers/form_html/show.html.heex` | Modify | Add form version history panel |
| `lib/atrium/tools.ex` | Create | Tools launchpad context |
| `lib/atrium/tools/tool_link.ex` | Create | ToolLink schema |
| `priv/repo/tenant_migrations/20260501000004_create_tool_links.exs` | Create | DB table |
| `lib/atrium_web/controllers/tools_controller.ex` | Create | Tools launchpad actions |
| `lib/atrium_web/controllers/tools_html.ex` | Create | Template module |
| `lib/atrium_web/controllers/tools_html/index.html.heex` | Create | Launchpad grid |
| `lib/atrium_web/router.ex` | Modify | Add home, directory, subsection, tools routes |

---

## Task 1: Home Dashboard

The current home page is a stub. Build a real dashboard: an announcement feed (editable by admins) and a quick-links grid (editable by admins). All users see both read-only; `super_users` group members see edit controls.

**Files:**
- Create: `lib/atrium/home/announcement.ex`
- Create: `lib/atrium/home/quick_link.ex`
- Create: `lib/atrium/home.ex`
- Create: `priv/repo/tenant_migrations/20260501000001_create_announcements.exs`
- Create: `priv/repo/tenant_migrations/20260501000002_create_quick_links.exs`
- Create: `lib/atrium_web/controllers/home_controller.ex`
- Create: `lib/atrium_web/controllers/home_html.ex`
- Create: `lib/atrium_web/controllers/home_html/show.html.heex`
- Modify: `lib/atrium_web/router.ex`
- Create: `test/atrium/home_test.exs`

- [ ] **Step 1: Write the failing context test**

```elixir
# test/atrium/home_test.exs
defmodule Atrium.HomeTest do
  use Atrium.TenantCase

  alias Atrium.Home

  defp actor(prefix) do
    {:ok, %{user: u}} = Atrium.Accounts.invite_user(prefix, %{
      email: "home_actor_#{System.unique_integer([:positive])}@example.com",
      name: "Actor"
    })
    u
  end

  describe "announcements" do
    test "create and list", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, ann} = Home.create_announcement(prefix, %{title: "Hello", body_html: "<p>hi</p>"}, u)
      assert ann.title == "Hello"
      assert ann.pinned == false
      list = Home.list_announcements(prefix)
      assert Enum.any?(list, &(&1.id == ann.id))
    end

    test "update announcement", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, ann} = Home.create_announcement(prefix, %{title: "Old", body_html: ""}, u)
      {:ok, updated} = Home.update_announcement(prefix, ann, %{title: "New"}, u)
      assert updated.title == "New"
    end

    test "delete announcement", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, ann} = Home.create_announcement(prefix, %{title: "Gone", body_html: ""}, u)
      {:ok, _} = Home.delete_announcement(prefix, ann, u)
      assert Home.list_announcements(prefix) == []
    end

    test "pinned announcements sort first", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, a1} = Home.create_announcement(prefix, %{title: "Normal", body_html: "", pinned: false}, u)
      {:ok, a2} = Home.create_announcement(prefix, %{title: "Pinned", body_html: "", pinned: true}, u)
      list = Home.list_announcements(prefix)
      ids = Enum.map(list, & &1.id)
      assert Enum.find_index(ids, &(&1 == a2.id)) < Enum.find_index(ids, &(&1 == a1.id))
    end
  end

  describe "quick links" do
    test "create and list", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, link} = Home.create_quick_link(prefix, %{label: "HR Portal", url: "https://hr.example.com", icon: "heart", position: 1}, u)
      assert link.label == "HR Portal"
      list = Home.list_quick_links(prefix)
      assert Enum.any?(list, &(&1.id == link.id))
    end

    test "delete quick link", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, link} = Home.create_quick_link(prefix, %{label: "Test", url: "https://example.com", icon: "link", position: 1}, u)
      {:ok, _} = Home.delete_quick_link(prefix, link, u)
      assert Home.list_quick_links(prefix) == []
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/home_test.exs 2>&1 | head -30
```
Expected: compile error — `Atrium.Home` not found.

- [ ] **Step 3: Create the announcement migration**

```elixir
# priv/repo/tenant_migrations/20260501000001_create_announcements.exs
defmodule Atrium.Repo.Migrations.CreateAnnouncements do
  use Ecto.Migration

  def change do
    create table(:announcements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :body_html, :text, default: ""
      add :pinned, :boolean, default: false, null: false
      add :author_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    create index(:announcements, [:inserted_at])
    create index(:announcements, [:pinned])
  end
end
```

- [ ] **Step 4: Create the quick links migration**

```elixir
# priv/repo/tenant_migrations/20260501000002_create_quick_links.exs
defmodule Atrium.Repo.Migrations.CreateQuickLinks do
  use Ecto.Migration

  def change do
    create table(:quick_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :string, null: false
      add :url, :string, null: false
      add :icon, :string, default: "link"
      add :position, :integer, default: 0, null: false
      add :author_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    create index(:quick_links, [:position])
  end
end
```

- [ ] **Step 5: Create the Announcement schema**

```elixir
# lib/atrium/home/announcement.ex
defmodule Atrium.Home.Announcement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "announcements" do
    field :title, :string
    field :body_html, :string, default: ""
    field :pinned, :boolean, default: false
    field :author_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ann, attrs) do
    ann
    |> cast(attrs, [:title, :body_html, :pinned, :author_id])
    |> validate_required([:title, :author_id])
    |> validate_length(:title, min: 1, max: 300)
    |> sanitize()
  end

  def update_changeset(ann, attrs) do
    ann
    |> cast(attrs, [:title, :body_html, :pinned])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 300)
    |> sanitize()
  end

  defp sanitize(cs) do
    case get_change(cs, :body_html) do
      nil -> cs
      html -> put_change(cs, :body_html, HtmlSanitizeEx.basic_html(html))
    end
  end
end
```

- [ ] **Step 6: Create the QuickLink schema**

```elixir
# lib/atrium/home/quick_link.ex
defmodule Atrium.Home.QuickLink do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "quick_links" do
    field :label, :string
    field :url, :string
    field :icon, :string, default: "link"
    field :position, :integer, default: 0
    field :author_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:label, :url, :icon, :position, :author_id])
    |> validate_required([:label, :url, :author_id])
    |> validate_length(:label, min: 1, max: 100)
    |> validate_format(:url, ~r/^https?:\/\//, message: "must start with http:// or https://")
  end

  def update_changeset(link, attrs) do
    link
    |> cast(attrs, [:label, :url, :icon, :position])
    |> validate_required([:label, :url])
    |> validate_length(:label, min: 1, max: 100)
    |> validate_format(:url, ~r/^https?:\/\//, message: "must start with http:// or https://")
  end
end
```

- [ ] **Step 7: Create the Home context**

```elixir
# lib/atrium/home.ex
defmodule Atrium.Home do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Home.{Announcement, QuickLink}

  # Announcements

  def list_announcements(prefix) do
    Repo.all(
      from(a in Announcement, order_by: [desc: a.pinned, desc: a.inserted_at]),
      prefix: prefix
    )
  end

  def get_announcement!(prefix, id), do: Repo.get!(Announcement, id, prefix: prefix)

  def create_announcement(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(stringify(attrs), "author_id", actor_user.id)

    with {:ok, ann} <- %Announcement{} |> Announcement.changeset(attrs_with_author) |> Repo.insert(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "announcement.created", %{actor: {:user, actor_user.id}, resource: {"Announcement", ann.id}}) do
      {:ok, ann}
    end
  end

  def update_announcement(prefix, %Announcement{} = ann, attrs, actor_user) do
    with {:ok, updated} <- ann |> Announcement.update_changeset(attrs) |> Repo.update(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "announcement.updated", %{actor: {:user, actor_user.id}, resource: {"Announcement", updated.id}}) do
      {:ok, updated}
    end
  end

  def delete_announcement(prefix, %Announcement{} = ann, actor_user) do
    with {:ok, deleted} <- Repo.delete(ann, prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "announcement.deleted", %{actor: {:user, actor_user.id}, resource: {"Announcement", deleted.id}}) do
      {:ok, deleted}
    end
  end

  # Quick links

  def list_quick_links(prefix) do
    Repo.all(from(q in QuickLink, order_by: [asc: q.position, asc: q.inserted_at]), prefix: prefix)
  end

  def get_quick_link!(prefix, id), do: Repo.get!(QuickLink, id, prefix: prefix)

  def create_quick_link(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(stringify(attrs), "author_id", actor_user.id)

    with {:ok, link} <- %QuickLink{} |> QuickLink.changeset(attrs_with_author) |> Repo.insert(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "quick_link.created", %{actor: {:user, actor_user.id}, resource: {"QuickLink", link.id}}) do
      {:ok, link}
    end
  end

  def delete_quick_link(prefix, %QuickLink{} = link, actor_user) do
    with {:ok, deleted} <- Repo.delete(link, prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "quick_link.deleted", %{actor: {:user, actor_user.id}, resource: {"QuickLink", deleted.id}}) do
      {:ok, deleted}
    end
  end

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
```

- [ ] **Step 8: Run tests to verify they pass**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/home_test.exs 2>&1
```
Expected: all tests pass.

- [ ] **Step 9: Create the HomeController**

```elixir
# lib/atrium_web/controllers/home_controller.ex
defmodule AtriumWeb.HomeController do
  use AtriumWeb, :controller

  alias Atrium.Home

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "home"}]
       when action in [:show]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "home"}]
       when action in [:create_announcement, :delete_announcement, :create_quick_link, :delete_quick_link]

  def show(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    announcements = Home.list_announcements(prefix)
    quick_links = Home.list_quick_links(prefix)
    render(conn, :show, announcements: announcements, quick_links: quick_links)
  end

  def create_announcement(conn, %{"announcement" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Home.create_announcement(prefix, params, user) do
      {:ok, _} ->
        conn |> put_flash(:info, "Announcement added.") |> redirect(to: ~p"/home")
      {:error, _cs} ->
        conn |> put_flash(:error, "Could not save announcement.") |> redirect(to: ~p"/home")
    end
  end

  def delete_announcement(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    ann = Home.get_announcement!(prefix, id)
    {:ok, _} = Home.delete_announcement(prefix, ann, user)
    conn |> put_flash(:info, "Announcement removed.") |> redirect(to: ~p"/home")
  end

  def create_quick_link(conn, %{"quick_link" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Home.create_quick_link(prefix, params, user) do
      {:ok, _} ->
        conn |> put_flash(:info, "Link added.") |> redirect(to: ~p"/home")
      {:error, _cs} ->
        conn |> put_flash(:error, "Could not save link.") |> redirect(to: ~p"/home")
    end
  end

  def delete_quick_link(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    link = Home.get_quick_link!(prefix, id)
    {:ok, _} = Home.delete_quick_link(prefix, link, user)
    conn |> put_flash(:info, "Link removed.") |> redirect(to: ~p"/home")
  end
end
```

- [ ] **Step 10: Create the HomeHTML module**

```elixir
# lib/atrium_web/controllers/home_html.ex
defmodule AtriumWeb.HomeHTML do
  use AtriumWeb, :html
  embed_templates "home_html/*"
end
```

- [ ] **Step 11: Create the dashboard template**

```heex
<%# lib/atrium_web/controllers/home_html/show.html.heex %>
<div class="atrium-anim">
  <div style="margin-bottom:28px">
    <div class="atrium-page-eyebrow">Home</div>
    <h1 class="atrium-page-title">Welcome to <%= @conn.assigns.tenant.name %></h1>
  </div>

  <%# Quick links %>
  <div class="atrium-card" style="margin-bottom:20px">
    <div class="atrium-card-header" style="display:flex;align-items:center;justify-content:space-between">
      <div class="atrium-card-title">Quick links</div>
      <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :home}) do %>
        <button
          onclick="document.getElementById('add-link-form').style.display = document.getElementById('add-link-form').style.display === 'none' ? 'block' : 'none'"
          class="atrium-btn atrium-btn-ghost"
          style="height:28px;font-size:.8125rem"
        >+ Add link</button>
      <% end %>
    </div>
    <div class="atrium-card-body">
      <%= if @quick_links == [] do %>
        <p style="color:var(--text-tertiary);font-size:.875rem">No quick links yet.</p>
      <% end %>
      <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:10px;margin-bottom:12px">
        <%= for link <- @quick_links do %>
          <div style="position:relative">
            <a href={link.url} target="_blank" rel="noopener noreferrer"
               style="display:flex;flex-direction:column;align-items:center;gap:8px;padding:16px 12px;border:1px solid var(--border);border-radius:var(--radius);background:var(--surface);text-decoration:none;color:var(--text-primary);font-size:.875rem;font-weight:500;text-align:center;transition:border-color .15s,background .15s"
               onmouseover="this.style.borderColor='var(--blue-500)';this.style.background='var(--blue-50)'"
               onmouseout="this.style.borderColor='var(--border)';this.style.background='var(--surface)'">
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75" style="width:20px;height:20px;color:var(--blue-500)">
                <path d="M6.5 3.5H3a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h9a1 1 0 0 0 1-1v-3.5M9.5 2H14v4.5M14 2l-7 7" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
              <%= link.label %>
            </a>
            <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :home}) do %>
              <form method="post" action={~p"/home/quick_links/#{link.id}/delete"} style="position:absolute;top:4px;right:4px">
                <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <button type="submit" style="border:none;background:none;cursor:pointer;padding:2px;color:var(--text-tertiary);line-height:1"
                  onmouseover="this.style.color='var(--color-error,#ef4444)'"
                  onmouseout="this.style.color='var(--text-tertiary)'"
                  title="Remove">
                  <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75" style="width:12px;height:12px">
                    <path d="M2 2l12 12M14 2L2 14" stroke-linecap="round"/>
                  </svg>
                </button>
              </form>
            <% end %>
          </div>
        <% end %>
      </div>
      <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :home}) do %>
        <div id="add-link-form" style="display:none;border-top:1px solid var(--border);padding-top:14px;margin-top:4px">
          <form method="post" action={~p"/home/quick_links"} style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <div>
              <label class="atrium-label">Label</label>
              <input type="text" name="quick_link[label]" class="atrium-input" style="width:160px" placeholder="HR Portal" required />
            </div>
            <div>
              <label class="atrium-label">URL</label>
              <input type="url" name="quick_link[url]" class="atrium-input" style="width:220px" placeholder="https://..." required />
            </div>
            <button type="submit" class="atrium-btn atrium-btn-primary" style="margin-bottom:1px">Add</button>
          </form>
        </div>
      <% end %>
    </div>
  </div>

  <%# Announcements %>
  <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
    <h2 style="font-size:1rem;font-weight:600;color:var(--text-primary)">Announcements</h2>
    <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :home}) do %>
      <button
        onclick="document.getElementById('add-ann-form').style.display = document.getElementById('add-ann-form').style.display === 'none' ? 'block' : 'none'"
        class="atrium-btn atrium-btn-ghost"
        style="height:28px;font-size:.8125rem"
      >+ New announcement</button>
    <% end %>
  </div>

  <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :home}) do %>
    <div id="add-ann-form" style="display:none;margin-bottom:16px">
      <div class="atrium-card">
        <div class="atrium-card-body">
          <form method="post" action={~p"/home/announcements"} style="display:flex;flex-direction:column;gap:12px">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <div>
              <label class="atrium-label">Title</label>
              <input type="text" name="announcement[title]" class="atrium-input" required />
            </div>
            <div>
              <label class="atrium-label">Body (optional)</label>
              <textarea name="announcement[body_html]" class="atrium-input" rows="3" style="resize:vertical"></textarea>
            </div>
            <div style="display:flex;align-items:center;gap:8px">
              <input type="checkbox" name="announcement[pinned]" value="true" id="ann-pinned" style="accent-color:var(--blue-500);width:14px;height:14px" />
              <label for="ann-pinned" style="font-size:.875rem;color:var(--text-secondary)">Pin to top</label>
            </div>
            <div>
              <button type="submit" class="atrium-btn atrium-btn-primary">Post</button>
            </div>
          </form>
        </div>
      </div>
    </div>
  <% end %>

  <%= if @announcements == [] do %>
    <div style="border:2px dashed var(--border);border-radius:var(--radius);padding:40px;text-align:center;color:var(--text-tertiary)">
      <p style="font-size:.875rem">No announcements yet.</p>
    </div>
  <% end %>

  <div style="display:flex;flex-direction:column;gap:12px">
    <%= for ann <- @announcements do %>
      <div class="atrium-card" style={"border-left:3px solid #{if ann.pinned, do: "var(--blue-500)", else: "var(--border)"}"}>
        <div class="atrium-card-body">
          <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px">
            <div style="flex:1;min-width:0">
              <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px">
                <%= if ann.pinned do %>
                  <span style="font-size:.6875rem;font-weight:600;text-transform:uppercase;letter-spacing:.06em;color:var(--blue-500)">Pinned</span>
                <% end %>
                <span style="font-size:.75rem;color:var(--text-tertiary)"><%= Calendar.strftime(ann.inserted_at, "%d %b %Y") %></span>
              </div>
              <div style="font-weight:600;font-size:.9375rem;color:var(--text-primary);margin-bottom:4px"><%= ann.title %></div>
              <%= if ann.body_html && ann.body_html != "" do %>
                <div style="font-size:.875rem;color:var(--text-secondary)"><%= Phoenix.HTML.raw(ann.body_html) %></div>
              <% end %>
            </div>
            <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :home}) do %>
              <form method="post" action={~p"/home/announcements/#{ann.id}/delete"} style="flex-shrink:0">
                <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <button type="submit" class="atrium-topbar-btn" title="Delete"
                  style="color:var(--text-tertiary)"
                  onmouseover="this.style.color='var(--color-error,#ef4444)'"
                  onmouseout="this.style.color='var(--text-tertiary)'">
                  <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75" style="width:14px;height:14px">
                    <path d="M3 4h10M5 4V3a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1M6 7v5M10 7v5M4 4l.667 9a1 1 0 0 0 1 .917h4.666a1 1 0 0 0 1-.917L12 4" stroke-linecap="round" stroke-linejoin="round"/>
                  </svg>
                </button>
              </form>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 12: Add routes**

In `lib/atrium_web/router.ex`, inside the `scope "/" do` + `pipe_through [:authenticated]` block, replace:

```elixir
get "/", PageController, :home
```

with:

```elixir
get "/", PageController, :home
get  "/home",                              HomeController, :show
post "/home/announcements",                HomeController, :create_announcement
post "/home/announcements/:id/delete",     HomeController, :delete_announcement
post "/home/quick_links",                  HomeController, :create_quick_link
post "/home/quick_links/:id/delete",       HomeController, :delete_quick_link
```

- [ ] **Step 13: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add lib/atrium/home.ex lib/atrium/home/ \
        lib/atrium_web/controllers/home_controller.ex \
        lib/atrium_web/controllers/home_html.ex \
        lib/atrium_web/controllers/home_html/ \
        priv/repo/tenant_migrations/20260501000001_create_announcements.exs \
        priv/repo/tenant_migrations/20260501000002_create_quick_links.exs \
        lib/atrium_web/router.ex \
        test/atrium/home_test.exs
git commit -m "feat: home dashboard with announcements and quick links"
```

- [ ] **Step 14: Mark Task 1 complete in this plan** — check all boxes above, update the status tracking header.

---

## Task 2: News Feed UI

The `news` section already works via the generic document flow (`/sections/news/documents`). Build a dedicated news reader view — a card feed instead of a table — so published documents in the news section render as articles. No new DB schema; reuse `Document` with `section_key = "news"`.

**Files:**
- Create: `lib/atrium_web/controllers/news_controller.ex`
- Create: `lib/atrium_web/controllers/news_html.ex`
- Create: `lib/atrium_web/controllers/news_html/index.html.heex`
- Create: `lib/atrium_web/controllers/news_html/show.html.heex`
- Modify: `lib/atrium_web/router.ex`

- [ ] **Step 1: Create the NewsController**

```elixir
# lib/atrium_web/controllers/news_controller.ex
defmodule AtriumWeb.NewsController do
  use AtriumWeb, :controller
  alias Atrium.Documents

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "news"}]
       when action in [:index, :show]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    articles = Documents.list_documents(prefix, "news", status: "approved")
    render(conn, :index, articles: articles)
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    article = Documents.get_document!(prefix, id)
    render(conn, :show, article: article)
  end
end
```

- [ ] **Step 2: Create NewsHTML module**

```elixir
# lib/atrium_web/controllers/news_html.ex
defmodule AtriumWeb.NewsHTML do
  use AtriumWeb, :html
  embed_templates "news_html/*"
end
```

- [ ] **Step 3: Create the news index template**

```heex
<%# lib/atrium_web/controllers/news_html/index.html.heex %>
<div class="atrium-anim">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:28px">
    <div>
      <div class="atrium-page-eyebrow">News</div>
      <h1 class="atrium-page-title">News & Announcements</h1>
    </div>
    <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :news}) do %>
      <a href={~p"/sections/news/documents/new"} class="atrium-btn atrium-btn-primary">Write article</a>
    <% end %>
  </div>

  <%= if @articles == [] do %>
    <div style="border:2px dashed var(--border);border-radius:var(--radius);padding:48px;text-align:center;color:var(--text-tertiary)">
      <p style="font-size:.875rem">No published articles yet.</p>
    </div>
  <% end %>

  <div style="display:flex;flex-direction:column;gap:16px">
    <%= for article <- @articles do %>
      <a href={~p"/news/#{article.id}"} style="text-decoration:none">
        <div class="atrium-card" style="transition:border-color .15s"
          onmouseover="this.style.borderColor='var(--blue-500)'"
          onmouseout="this.style.borderColor='var(--border)'">
          <div class="atrium-card-body">
            <div style="font-size:.75rem;color:var(--text-tertiary);margin-bottom:6px">
              <%= Calendar.strftime(article.inserted_at, "%d %B %Y") %>
            </div>
            <div style="font-size:1.0625rem;font-weight:600;color:var(--text-primary);margin-bottom:6px"><%= article.title %></div>
            <%= if article.body_html && article.body_html != "" do %>
              <div style="font-size:.875rem;color:var(--text-secondary);display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden">
                <%= Phoenix.HTML.raw(article.body_html) %>
              </div>
            <% end %>
            <div style="margin-top:10px;font-size:.8125rem;color:var(--blue-500);font-weight:500">Read more →</div>
          </div>
        </div>
      </a>
    <% end %>
  </div>
</div>
```

- [ ] **Step 4: Create the news article show template**

```heex
<%# lib/atrium_web/controllers/news_html/show.html.heex %>
<div class="atrium-anim" style="max-width:720px">
  <div style="margin-bottom:20px">
    <a href={~p"/news"} style="font-size:.8125rem;color:var(--text-tertiary)">← News</a>
  </div>

  <div style="margin-bottom:28px">
    <div class="atrium-page-eyebrow"><%= Calendar.strftime(@article.inserted_at, "%d %B %Y") %></div>
    <h1 class="atrium-page-title"><%= @article.title %></h1>
    <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :news}) do %>
      <div style="margin-top:10px">
        <a href={~p"/sections/news/documents/#{@article.id}"} class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.8125rem">Manage in editor →</a>
      </div>
    <% end %>
  </div>

  <div class="atrium-card">
    <div class="atrium-card-body prose" style="min-height:80px">
      <%= if @article.body_html && @article.body_html != "" do %>
        <%= Phoenix.HTML.raw(@article.body_html) %>
      <% else %>
        <p style="color:var(--text-tertiary);font-style:italic">No content.</p>
      <% end %>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Add routes**

In `lib/atrium_web/router.ex`, inside the authenticated scope, add:

```elixir
get "/news",      NewsController, :index
get "/news/:id",  NewsController, :show
```

- [ ] **Step 6: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add lib/atrium_web/controllers/news_controller.ex \
        lib/atrium_web/controllers/news_html.ex \
        lib/atrium_web/controllers/news_html/ \
        lib/atrium_web/router.ex
git commit -m "feat: news feed UI — card reader for approved news documents"
```

---

## Task 3: Employee Directory

Build a searchable directory showing all active users with their profile fields (name, email, role, department, phone, bio). Add profile fields via migration. Profile editing is admin-only via existing tenant admin user controller.

**Files:**
- Create: `priv/repo/tenant_migrations/20260501000003_add_profile_fields_to_users.exs`
- Modify: `lib/atrium/accounts/user.ex`
- Create: `lib/atrium_web/controllers/directory_controller.ex`
- Create: `lib/atrium_web/controllers/directory_html.ex`
- Create: `lib/atrium_web/controllers/directory_html/index.html.heex`
- Create: `lib/atrium_web/controllers/directory_html/show.html.heex`
- Modify: `lib/atrium_web/controllers/tenant_admin/user_controller.ex`
- Create: `lib/atrium_web/controllers/tenant_admin/user_html/edit_profile.html.heex`
- Modify: `lib/atrium_web/router.ex`
- Create: `test/atrium/directory_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/atrium/directory_test.exs
defmodule Atrium.DirectoryTest do
  use Atrium.TenantCase
  alias Atrium.Accounts

  defp make_user(prefix, attrs \\ %{}) do
    base = %{
      email: "dir_#{System.unique_integer([:positive])}@example.com",
      name: "Dir User"
    }
    {:ok, %{user: u}} = Accounts.invite_user(prefix, Map.merge(base, attrs))
    u
  end

  describe "profile fields" do
    test "update_profile saves role and department", %{tenant_prefix: prefix} do
      u = make_user(prefix)
      {:ok, updated} = Accounts.update_profile(prefix, u, %{role: "Engineer", department: "IT"})
      assert updated.role == "Engineer"
      assert updated.department == "IT"
    end

    test "list_active_users returns only active users", %{tenant_prefix: prefix} do
      u = make_user(prefix)
      {:ok, active} = Accounts.activate_user(prefix, u, %{password: "password123456"})
      list = Accounts.list_active_users(prefix)
      assert Enum.any?(list, &(&1.id == active.id))
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/directory_test.exs 2>&1 | head -20
```
Expected: compile error — `update_profile` not defined.

- [ ] **Step 3: Create the profile fields migration**

```elixir
# priv/repo/tenant_migrations/20260501000003_add_profile_fields_to_users.exs
defmodule Atrium.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string
      add :department, :string
      add :phone, :string
      add :bio, :text
      add :avatar_url, :string
    end
  end
end
```

- [ ] **Step 4: Add profile fields to User schema**

In `lib/atrium/accounts/user.ex`, add fields after `field :is_admin`:

```elixir
field :role, :string
field :department, :string
field :phone, :string
field :bio, :string
field :avatar_url, :string
```

Add a profile changeset at the end of the module (before the private `put_hashed_password`):

```elixir
def profile_changeset(user, attrs) do
  user
  |> cast(attrs, [:name, :role, :department, :phone, :bio, :avatar_url])
  |> validate_required([:name])
  |> validate_length(:bio, max: 1000)
end
```

- [ ] **Step 5: Add context functions to Atrium.Accounts**

In `lib/atrium/accounts.ex`, add after `set_admin/3`:

```elixir
def update_profile(prefix, %User{} = user, attrs) do
  with {:ok, updated} <- user |> User.profile_changeset(attrs) |> Repo.update(prefix: prefix),
       {:ok, _} <- Audit.log(prefix, "user.profile_updated", %{
         actor: :system,
         resource: {"User", updated.id},
         changes: Audit.changeset_diff(user, updated)
       }) do
    {:ok, updated}
  end
end

def list_active_users(prefix) do
  import Ecto.Query
  Repo.all(
    from(u in User, where: u.status == "active", order_by: [asc: u.name]),
    prefix: prefix
  )
end

def activate_user(prefix, %User{} = user, attrs) do
  with {:ok, updated} <- user |> User.activate_password_changeset(attrs) |> Repo.update(prefix: prefix) do
    {:ok, updated}
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/directory_test.exs 2>&1
```
Expected: all pass.

- [ ] **Step 7: Create DirectoryController**

```elixir
# lib/atrium_web/controllers/directory_controller.ex
defmodule AtriumWeb.DirectoryController do
  use AtriumWeb, :controller
  alias Atrium.Accounts

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "directory"}]
       when action in [:index, :show]

  def index(conn, params) do
    prefix = conn.assigns.tenant_prefix
    users = Accounts.list_active_users(prefix)

    users =
      if q = params["q"] do
        q = String.downcase(q)
        Enum.filter(users, fn u ->
          String.contains?(String.downcase(u.name), q) or
          String.contains?(String.downcase(u.email), q) or
          (u.department && String.contains?(String.downcase(u.department), q)) or
          (u.role && String.contains?(String.downcase(u.role), q))
        end)
      else
        users
      end

    render(conn, :index, users: users, query: params["q"] || "")
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = Atrium.Accounts.get_user!(prefix, id)
    render(conn, :show, profile: user)
  end
end
```

- [ ] **Step 8: Create DirectoryHTML module**

```elixir
# lib/atrium_web/controllers/directory_html.ex
defmodule AtriumWeb.DirectoryHTML do
  use AtriumWeb, :html
  embed_templates "directory_html/*"
end
```

- [ ] **Step 9: Create directory index template**

```heex
<%# lib/atrium_web/controllers/directory_html/index.html.heex %>
<div class="atrium-anim">
  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Directory</div>
    <h1 class="atrium-page-title">Employee Directory</h1>
  </div>

  <form method="get" action={~p"/directory"} style="margin-bottom:20px">
    <div style="position:relative;max-width:400px">
      <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75" style="width:14px;height:14px;position:absolute;left:10px;top:50%;transform:translateY(-50%);color:var(--text-tertiary);pointer-events:none">
        <circle cx="7" cy="7" r="4.5"/><path d="M11 11l2.5 2.5" stroke-linecap="round"/>
      </svg>
      <input type="text" name="q" value={@query} placeholder="Search by name, role, or department…"
             class="atrium-input" style="padding-left:32px" />
    </div>
  </form>

  <%= if @users == [] do %>
    <div style="padding:40px;text-align:center;color:var(--text-tertiary)">
      <%= if @query != "", do: "No results for "#{@query}".", else: "No users yet." %>
    </div>
  <% end %>

  <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px">
    <%= for user <- @users do %>
      <a href={~p"/directory/#{user.id}"} style="text-decoration:none">
        <div class="atrium-card" style="transition:border-color .15s"
          onmouseover="this.style.borderColor='var(--blue-500)'"
          onmouseout="this.style.borderColor='var(--border)'">
          <div class="atrium-card-body" style="display:flex;align-items:center;gap:12px">
            <div class="atrium-user-avatar" style="width:40px;height:40px;font-size:.875rem;flex-shrink:0">
              <%= user.name |> String.split() |> Enum.map(&String.first/1) |> Enum.take(2) |> Enum.join() %>
            </div>
            <div style="min-width:0">
              <div style="font-weight:600;font-size:.875rem;color:var(--text-primary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis"><%= user.name %></div>
              <%= if user.role do %>
                <div style="font-size:.8125rem;color:var(--text-secondary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis"><%= user.role %></div>
              <% end %>
              <%= if user.department do %>
                <div style="font-size:.75rem;color:var(--text-tertiary)"><%= user.department %></div>
              <% end %>
            </div>
          </div>
        </div>
      </a>
    <% end %>
  </div>
</div>
```

- [ ] **Step 10: Create directory show template**

```heex
<%# lib/atrium_web/controllers/directory_html/show.html.heex %>
<div class="atrium-anim" style="max-width:640px">
  <div style="margin-bottom:20px">
    <a href={~p"/directory"} style="font-size:.8125rem;color:var(--text-tertiary)">← Directory</a>
  </div>

  <div class="atrium-card" style="margin-bottom:16px">
    <div class="atrium-card-body" style="display:flex;align-items:center;gap:20px">
      <div class="atrium-user-avatar" style="width:64px;height:64px;font-size:1.25rem;flex-shrink:0">
        <%= @profile.name |> String.split() |> Enum.map(&String.first/1) |> Enum.take(2) |> Enum.join() %>
      </div>
      <div>
        <h1 style="font-size:1.25rem;font-weight:700;color:var(--text-primary);margin-bottom:2px"><%= @profile.name %></h1>
        <%= if @profile.role do %>
          <div style="font-size:.9375rem;color:var(--text-secondary)"><%= @profile.role %></div>
        <% end %>
        <%= if @profile.department do %>
          <div style="font-size:.875rem;color:var(--text-tertiary)"><%= @profile.department %></div>
        <% end %>
      </div>
      <%= if @conn.assigns[:current_user] && @conn.assigns.current_user.is_admin do %>
        <div style="margin-left:auto">
          <a href={~p"/admin/users/#{@profile.id}/profile"} class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.8125rem">Edit profile</a>
        </div>
      <% end %>
    </div>
  </div>

  <div class="atrium-card">
    <div class="atrium-card-header"><div class="atrium-card-title">Contact</div></div>
    <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:10px">
      <div style="display:flex;gap:12px">
        <span style="font-size:.8125rem;color:var(--text-tertiary);width:80px;flex-shrink:0">Email</span>
        <a href={"mailto:#{@profile.email}"} style="font-size:.875rem;color:var(--blue-500)"><%= @profile.email %></a>
      </div>
      <%= if @profile.phone do %>
        <div style="display:flex;gap:12px">
          <span style="font-size:.8125rem;color:var(--text-tertiary);width:80px;flex-shrink:0">Phone</span>
          <span style="font-size:.875rem;color:var(--text-primary)"><%= @profile.phone %></span>
        </div>
      <% end %>
      <%= if @profile.bio do %>
        <div style="display:flex;gap:12px">
          <span style="font-size:.8125rem;color:var(--text-tertiary);width:80px;flex-shrink:0">Bio</span>
          <span style="font-size:.875rem;color:var(--text-primary)"><%= @profile.bio %></span>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

- [ ] **Step 11: Add profile edit action to TenantAdmin.UserController**

In `lib/atrium_web/controllers/tenant_admin/user_controller.ex`, add two actions:

```elixir
def edit_profile(conn, %{"id" => id}) do
  prefix = conn.assigns.tenant_prefix
  user = Atrium.Accounts.get_user!(prefix, id)
  render(conn, :edit_profile, profile_user: user)
end

def update_profile(conn, %{"id" => id, "user" => params}) do
  prefix = conn.assigns.tenant_prefix
  user = Atrium.Accounts.get_user!(prefix, id)

  case Atrium.Accounts.update_profile(prefix, user, params) do
    {:ok, _} ->
      conn |> put_flash(:info, "Profile updated.") |> redirect(to: ~p"/directory/#{id}")
    {:error, _cs} ->
      conn |> put_flash(:error, "Could not update profile.") |> render(:edit_profile, profile_user: user)
  end
end
```

- [ ] **Step 12: Create profile edit template**

```heex
<%# lib/atrium_web/controllers/tenant_admin/user_html/edit_profile.html.heex %>
<div class="atrium-anim" style="max-width:560px">
  <div style="margin-bottom:20px">
    <a href={~p"/admin/users/#{@profile_user.id}"} style="font-size:.8125rem;color:var(--text-tertiary)">← <%= @profile_user.name %></a>
  </div>

  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Admin</div>
    <h1 class="atrium-page-title">Edit profile</h1>
  </div>

  <form method="post" action={~p"/admin/users/#{@profile_user.id}/profile"}>
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
    <input type="hidden" name="_method" value="put" />
    <div class="atrium-card">
      <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:16px">
        <div>
          <label class="atrium-label">Name</label>
          <input type="text" name="user[name]" value={@profile_user.name} class="atrium-input" required />
        </div>
        <div>
          <label class="atrium-label">Role</label>
          <input type="text" name="user[role]" value={@profile_user.role} class="atrium-input" placeholder="e.g. Software Engineer" />
        </div>
        <div>
          <label class="atrium-label">Department</label>
          <input type="text" name="user[department]" value={@profile_user.department} class="atrium-input" placeholder="e.g. Engineering" />
        </div>
        <div>
          <label class="atrium-label">Phone</label>
          <input type="text" name="user[phone]" value={@profile_user.phone} class="atrium-input" placeholder="+44 7700 000000" />
        </div>
        <div>
          <label class="atrium-label">Bio</label>
          <textarea name="user[bio]" class="atrium-input" rows="4" style="resize:vertical"><%= @profile_user.bio %></textarea>
        </div>
      </div>
    </div>
    <div style="margin-top:16px;display:flex;gap:8px">
      <button type="submit" class="atrium-btn atrium-btn-primary">Save</button>
      <a href={~p"/admin/users/#{@profile_user.id}"} class="atrium-btn atrium-btn-ghost">Cancel</a>
    </div>
  </form>
</div>
```

- [ ] **Step 13: Add routes**

In `lib/atrium_web/router.ex`, authenticated scope:

```elixir
get "/directory",      DirectoryController, :index
get "/directory/:id",  DirectoryController, :show
```

Inside the `/admin` scope:

```elixir
get  "/users/:id/profile", UserController, :edit_profile
put  "/users/:id/profile", UserController, :update_profile
```

- [ ] **Step 14: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add priv/repo/tenant_migrations/20260501000003_add_profile_fields_to_users.exs \
        lib/atrium/accounts/user.ex \
        lib/atrium_web/controllers/directory_controller.ex \
        lib/atrium_web/controllers/directory_html.ex \
        lib/atrium_web/controllers/directory_html/ \
        lib/atrium_web/controllers/tenant_admin/user_controller.ex \
        lib/atrium_web/controllers/tenant_admin/user_html/edit_profile.html.heex \
        lib/atrium_web/router.ex \
        test/atrium/directory_test.exs
git commit -m "feat: employee directory with profile fields"
```

---

## Task 4: Subsection Management UI

Admins need a UI to create/delete subsections within sections that support them (hr, departments, docs, projects). The `Atrium.Authorization` context already has `create_subsection/2` and `delete_subsection/2`. Build a controller + templates that sit inside the tenant admin scope.

**Files:**
- Create: `lib/atrium_web/controllers/tenant_admin/subsection_controller.ex`
- Create: `lib/atrium_web/controllers/tenant_admin/subsection_html.ex`
- Create: `lib/atrium_web/controllers/tenant_admin/subsection_html/index.html.heex`
- Create: `lib/atrium_web/controllers/tenant_admin/subsection_html/new.html.heex`
- Modify: `lib/atrium_web/router.ex`

- [ ] **Step 1: Create SubsectionController**

```elixir
# lib/atrium_web/controllers/tenant_admin/subsection_controller.ex
defmodule AtriumWeb.TenantAdmin.SubsectionController do
  use AtriumWeb, :controller
  alias Atrium.Authorization
  alias Atrium.Authorization.{SectionRegistry, Subsection}

  def index(conn, %{"section_key" => section_key}) do
    prefix = conn.assigns.tenant_prefix
    section = SectionRegistry.get(section_key)

    unless section && section.supports_subsections do
      conn |> put_flash(:error, "This section does not support subsections.") |> redirect(to: ~p"/admin/users") |> halt()
    else
      subsections = Authorization.list_subsections(prefix, section_key)
      render(conn, :index, section: section, subsections: subsections, section_key: section_key)
    end
  end

  def new(conn, %{"section_key" => section_key}) do
    section = SectionRegistry.get(section_key)

    unless section && section.supports_subsections do
      conn |> put_flash(:error, "This section does not support subsections.") |> redirect(to: ~p"/admin/users") |> halt()
    else
      render(conn, :new, section: section, section_key: section_key, changeset: Subsection.create_changeset(%Subsection{}, %{}))
    end
  end

  def create(conn, %{"section_key" => section_key, "subsection" => params}) do
    prefix = conn.assigns.tenant_prefix

    attrs = Map.merge(params, %{"section_key" => section_key})

    case Authorization.create_subsection(prefix, attrs) do
      {:ok, _} ->
        conn |> put_flash(:info, "Subsection created.") |> redirect(to: ~p"/admin/sections/#{section_key}/subsections")
      {:error, cs} ->
        section = SectionRegistry.get(section_key)
        conn |> put_status(422) |> render(:new, section: section, section_key: section_key, changeset: cs)
    end
  end

  def delete(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    ss = Atrium.Repo.get!(Atrium.Authorization.Subsection, id, prefix: prefix)

    case Authorization.delete_subsection(prefix, ss) do
      {:ok, _} ->
        conn |> put_flash(:info, "Subsection deleted.") |> redirect(to: ~p"/admin/sections/#{section_key}/subsections")
      {:error, _} ->
        conn |> put_flash(:error, "Could not delete subsection.") |> redirect(to: ~p"/admin/sections/#{section_key}/subsections")
    end
  end
end
```

- [ ] **Step 2: Create SubsectionHTML module**

```elixir
# lib/atrium_web/controllers/tenant_admin/subsection_html.ex
defmodule AtriumWeb.TenantAdmin.SubsectionHTML do
  use AtriumWeb, :html
  embed_templates "subsection_html/*"
end
```

- [ ] **Step 3: Create subsection index template**

```heex
<%# lib/atrium_web/controllers/tenant_admin/subsection_html/index.html.heex %>
<div class="atrium-anim" style="max-width:640px">
  <div style="margin-bottom:20px">
    <a href={~p"/admin/users"} style="font-size:.8125rem;color:var(--text-tertiary)">← Admin</a>
  </div>

  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:24px">
    <div>
      <div class="atrium-page-eyebrow">Admin / <%= @section.name %></div>
      <h1 class="atrium-page-title">Subsections</h1>
    </div>
    <a href={~p"/admin/sections/#{@section_key}/subsections/new"} class="atrium-btn atrium-btn-primary">Add subsection</a>
  </div>

  <div class="atrium-card">
    <table class="atrium-table">
      <thead>
        <tr>
          <th>Name</th>
          <th>Slug</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <%= for ss <- @subsections do %>
          <tr>
            <td style="font-weight:500"><%= ss.name %></td>
            <td style="font-family:'IBM Plex Mono',monospace;font-size:.8125rem;color:var(--text-tertiary)"><%= ss.slug %></td>
            <td style="text-align:right">
              <form method="post" action={~p"/admin/sections/#{@section_key}/subsections/#{ss.id}/delete"} style="display:inline">
                <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <button type="submit" class="atrium-btn atrium-btn-ghost"
                  style="height:28px;font-size:.8125rem;color:var(--color-error)"
                  onclick="return confirm('Delete this subsection? Documents within it will not be deleted.')">Delete</button>
              </form>
            </td>
          </tr>
        <% end %>
        <%= if @subsections == [] do %>
          <tr><td colspan="3" style="padding:32px;text-align:center;color:var(--text-tertiary)">No subsections yet.</td></tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

- [ ] **Step 4: Create subsection new template**

```heex
<%# lib/atrium_web/controllers/tenant_admin/subsection_html/new.html.heex %>
<div class="atrium-anim" style="max-width:480px">
  <div style="margin-bottom:20px">
    <a href={~p"/admin/sections/#{@section_key}/subsections"} style="font-size:.8125rem;color:var(--text-tertiary)">← Subsections</a>
  </div>

  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow"><%= @section.name %></div>
    <h1 class="atrium-page-title">New subsection</h1>
  </div>

  <form method="post" action={~p"/admin/sections/#{@section_key}/subsections"}>
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
    <div class="atrium-card" style="margin-bottom:16px">
      <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:16px">
        <div>
          <label class="atrium-label">Name</label>
          <input type="text" name="subsection[name]" class="atrium-input" placeholder="e.g. Payroll" required />
        </div>
        <div>
          <label class="atrium-label">Slug <span style="color:var(--text-tertiary);font-weight:400">(URL-safe, lowercase)</span></label>
          <input type="text" name="subsection[slug]" class="atrium-input" placeholder="e.g. payroll" pattern="[a-z0-9_-]+" title="Lowercase letters, numbers, hyphens and underscores only" required />
        </div>
        <div>
          <label class="atrium-label">Description <span style="color:var(--text-tertiary);font-weight:400">(optional)</span></label>
          <input type="text" name="subsection[description]" class="atrium-input" />
        </div>
      </div>
    </div>
    <div style="display:flex;gap:8px">
      <button type="submit" class="atrium-btn atrium-btn-primary">Create</button>
      <a href={~p"/admin/sections/#{@section_key}/subsections"} class="atrium-btn atrium-btn-ghost">Cancel</a>
    </div>
  </form>
</div>
```

- [ ] **Step 5: Add routes**

In `lib/atrium_web/router.ex`, inside the `/admin` scope (after existing admin routes):

```elixir
get  "/sections/:section_key/subsections",             SubsectionController, :index
get  "/sections/:section_key/subsections/new",         SubsectionController, :new
post "/sections/:section_key/subsections",             SubsectionController, :create
post "/sections/:section_key/subsections/:id/delete",  SubsectionController, :delete
```

- [ ] **Step 6: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add lib/atrium_web/controllers/tenant_admin/subsection_controller.ex \
        lib/atrium_web/controllers/tenant_admin/subsection_html.ex \
        lib/atrium_web/controllers/tenant_admin/subsection_html/ \
        lib/atrium_web/router.ex
git commit -m "feat: subsection management UI in tenant admin"
```

---

## Task 5: Form Notification Email Fanout

`Form.notification_recipients` stores a list of `%{"type" => "user"|"email", "id" => ..., "email" => ...}` maps. When a submission is created, send an email to each recipient. Use Swoosh (already configured via `Atrium.Mailer`).

**Files:**
- Create: `lib/atrium/notifications/form_mailer.ex`
- Modify: `lib/atrium/forms.ex` — call mailer after submission insert

- [ ] **Step 1: Check Mailer is configured**

```bash
cd /Users/marcinwalczak/Kod/atrium && grep -r "Atrium.Mailer\|Swoosh" lib/atrium/mailer.ex config/ 2>&1 | head -20
```
Expected: see `defmodule Atrium.Mailer do use Swoosh.Mailer`.

- [ ] **Step 2: Create the FormMailer**

```elixir
# lib/atrium/notifications/form_mailer.ex
defmodule Atrium.Notifications.FormMailer do
  import Swoosh.Email

  alias Atrium.Mailer

  @doc """
  Sends a notification to all recipients listed on the form when a new submission arrives.
  recipients is a list of maps: %{"type" => "user"|"email", "email" => "addr@example.com", "name" => "Name"}
  """
  def notify_submission(form, submission, recipients) do
    Enum.each(recipients, fn recipient ->
      to_email = recipient["email"]
      to_name = recipient["name"] || recipient["email"]

      if to_email && to_email != "" do
        email =
          new()
          |> to({to_name, to_email})
          |> from({"Atrium", "no-reply@atrium.app"})
          |> subject("New submission: #{form.title}")
          |> html_body("""
          <p>A new submission has been received for <strong>#{form.title}</strong>.</p>
          <p>Submitted at: #{Calendar.strftime(submission.submitted_at || DateTime.utc_now(), "%d %b %Y %H:%M UTC")}</p>
          <p>Please log in to Atrium to review and action this submission.</p>
          """)
          |> text_body("New submission received for #{form.title}. Please log in to Atrium to review it.")

        case Mailer.deliver(email) do
          {:ok, _} -> :ok
          {:error, reason} -> require Logger; Logger.warning("FormMailer: failed to deliver to #{to_email}: #{inspect(reason)}")
        end
      end
    end)
  end
end
```

- [ ] **Step 3: Wire the mailer into form submission creation**

In `lib/atrium/forms.ex`, find the `create_submission/4` function. After the submission is successfully inserted (inside the `with` success branch or after the transaction), add:

```elixir
# After {:ok, submission} <- insert submission:
Task.start(fn ->
  Atrium.Notifications.FormMailer.notify_submission(form, submission, form.notification_recipients)
end)
```

The exact diff depends on the current `create_submission` implementation. Read `lib/atrium/forms.ex` and locate the function, then add the `Task.start` call after the `{:ok, submission}` is bound and before returning it. Do not block the transaction on email delivery.

- [ ] **Step 4: Verify compile**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix compile 2>&1
```
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add lib/atrium/notifications/form_mailer.ex lib/atrium/forms.ex
git commit -m "feat: form submission email notifications to recipients"
```

---

## Task 6: Form Version History View

The `form_html/show.html.heex` already has a version history table. The `Atrium.Forms` context already has `list_versions/2`. What's missing: the `FormController#show` action needs to also fetch and pass the form audit history (like DocumentController does), and the show template needs an audit history panel styled like the document show page.

**Files:**
- Modify: `lib/atrium_web/controllers/form_controller.ex` — add `history` to show assigns
- Modify: `lib/atrium_web/controllers/form_html/show.html.heex` — add audit history panel

- [ ] **Step 1: Update FormController show to pass history**

In `lib/atrium_web/controllers/form_controller.ex`, find the `show/2` action. It currently renders `versions`. Add `history`:

```elixir
def show(conn, %{"section_key" => section_key, "id" => id}) do
  prefix = conn.assigns.tenant_prefix
  form = Forms.get_form!(prefix, id)
  versions = Forms.list_versions(prefix, form.id)
  history = Atrium.Audit.history_for(prefix, "Form", form.id)
  render(conn, :show, form: form, versions: versions, history: history, section_key: section_key)
end
```

- [ ] **Step 2: Add audit history panel to form show template**

In `lib/atrium_web/controllers/form_html/show.html.heex`, the existing template already has an `assigns[:history]` guard. Verify it renders correctly by checking the template already has:

```heex
<%= if assigns[:history] && @history != [] do %>
```

If the guard is present, no template change is needed — just the controller fix in Step 1 is sufficient.

- [ ] **Step 3: Verify compile and run existing tests**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/ 2>&1 | tail -10
```
Expected: tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add lib/atrium_web/controllers/form_controller.ex
git commit -m "feat: form audit history wired to show page"
```

---

## Task 7: Tools Launchpad

A simple grid of external links (name, URL, icon, description) managed by admins. No section-level workflow needed — just create/delete. Uses the `tools` section ACL for access.

**Files:**
- Create: `priv/repo/tenant_migrations/20260501000004_create_tool_links.exs`
- Create: `lib/atrium/tools/tool_link.ex`
- Create: `lib/atrium/tools.ex`
- Create: `lib/atrium_web/controllers/tools_controller.ex`
- Create: `lib/atrium_web/controllers/tools_html.ex`
- Create: `lib/atrium_web/controllers/tools_html/index.html.heex`
- Modify: `lib/atrium_web/router.ex`

- [ ] **Step 1: Create tool links migration**

```elixir
# priv/repo/tenant_migrations/20260501000004_create_tool_links.exs
defmodule Atrium.Repo.Migrations.CreateToolLinks do
  use Ecto.Migration

  def change do
    create table(:tool_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :string, null: false
      add :url, :string, null: false
      add :description, :string
      add :icon, :string, default: "link"
      add :position, :integer, default: 0, null: false
      add :author_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    create index(:tool_links, [:position])
  end
end
```

- [ ] **Step 2: Create ToolLink schema**

```elixir
# lib/atrium/tools/tool_link.ex
defmodule Atrium.Tools.ToolLink do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tool_links" do
    field :label, :string
    field :url, :string
    field :description, :string
    field :icon, :string, default: "link"
    field :position, :integer, default: 0
    field :author_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(tool, attrs) do
    tool
    |> cast(attrs, [:label, :url, :description, :icon, :position, :author_id])
    |> validate_required([:label, :url, :author_id])
    |> validate_length(:label, min: 1, max: 100)
    |> validate_format(:url, ~r/^https?:\/\//, message: "must start with http:// or https://")
  end
end
```

- [ ] **Step 3: Create Tools context**

```elixir
# lib/atrium/tools.ex
defmodule Atrium.Tools do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Tools.ToolLink

  def list_tool_links(prefix) do
    Repo.all(from(t in ToolLink, order_by: [asc: t.position, asc: t.inserted_at]), prefix: prefix)
  end

  def get_tool_link!(prefix, id), do: Repo.get!(ToolLink, id, prefix: prefix)

  def create_tool_link(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(stringify(attrs), "author_id", actor_user.id)

    with {:ok, link} <- %ToolLink{} |> ToolLink.changeset(attrs_with_author) |> Repo.insert(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_link.created", %{actor: {:user, actor_user.id}, resource: {"ToolLink", link.id}}) do
      {:ok, link}
    end
  end

  def delete_tool_link(prefix, %ToolLink{} = link, actor_user) do
    with {:ok, deleted} <- Repo.delete(link, prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_link.deleted", %{actor: {:user, actor_user.id}, resource: {"ToolLink", deleted.id}}) do
      {:ok, deleted}
    end
  end

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
```

- [ ] **Step 4: Create ToolsController**

```elixir
# lib/atrium_web/controllers/tools_controller.ex
defmodule AtriumWeb.ToolsController do
  use AtriumWeb, :controller
  alias Atrium.Tools

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "tools"}]
       when action in [:index]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "tools"}]
       when action in [:create_tool, :delete_tool]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    tools = Tools.list_tool_links(prefix)
    render(conn, :index, tools: tools)
  end

  def create_tool(conn, %{"tool" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Tools.create_tool_link(prefix, params, user) do
      {:ok, _} -> conn |> put_flash(:info, "Tool added.") |> redirect(to: ~p"/tools")
      {:error, _} -> conn |> put_flash(:error, "Could not save tool.") |> redirect(to: ~p"/tools")
    end
  end

  def delete_tool(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    link = Tools.get_tool_link!(prefix, id)
    {:ok, _} = Tools.delete_tool_link(prefix, link, user)
    conn |> put_flash(:info, "Tool removed.") |> redirect(to: ~p"/tools")
  end
end
```

- [ ] **Step 5: Create ToolsHTML module**

```elixir
# lib/atrium_web/controllers/tools_html.ex
defmodule AtriumWeb.ToolsHTML do
  use AtriumWeb, :html
  embed_templates "tools_html/*"
end
```

- [ ] **Step 6: Create tools launchpad template**

```heex
<%# lib/atrium_web/controllers/tools_html/index.html.heex %>
<div class="atrium-anim">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:28px">
    <div>
      <div class="atrium-page-eyebrow">Tools</div>
      <h1 class="atrium-page-title">Tools & Applications</h1>
    </div>
    <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :tools}) do %>
      <button
        onclick="document.getElementById('add-tool-form').style.display = document.getElementById('add-tool-form').style.display === 'none' ? 'block' : 'none'"
        class="atrium-btn atrium-btn-primary">
        + Add tool
      </button>
    <% end %>
  </div>

  <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :tools}) do %>
    <div id="add-tool-form" style="display:none;margin-bottom:24px">
      <div class="atrium-card">
        <div class="atrium-card-header"><div class="atrium-card-title">Add tool</div></div>
        <div class="atrium-card-body">
          <form method="post" action={~p"/tools"} style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <div>
              <label class="atrium-label">Name</label>
              <input type="text" name="tool[label]" class="atrium-input" style="width:160px" placeholder="Slack" required />
            </div>
            <div>
              <label class="atrium-label">URL</label>
              <input type="url" name="tool[url]" class="atrium-input" style="width:220px" placeholder="https://..." required />
            </div>
            <div>
              <label class="atrium-label">Description</label>
              <input type="text" name="tool[description]" class="atrium-input" style="width:200px" placeholder="Team messaging" />
            </div>
            <button type="submit" class="atrium-btn atrium-btn-primary" style="margin-bottom:1px">Add</button>
          </form>
        </div>
      </div>
    </div>
  <% end %>

  <%= if @tools == [] do %>
    <div style="border:2px dashed var(--border);border-radius:var(--radius);padding:48px;text-align:center;color:var(--text-tertiary)">
      <p style="font-size:.875rem">No tools added yet.</p>
    </div>
  <% end %>

  <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:12px">
    <%= for tool <- @tools do %>
      <div style="position:relative">
        <a href={tool.url} target="_blank" rel="noopener noreferrer"
           style="display:flex;flex-direction:column;align-items:center;gap:10px;padding:24px 16px;border:1px solid var(--border);border-radius:var(--radius);background:var(--surface);text-decoration:none;color:var(--text-primary);text-align:center;transition:border-color .15s,background .15s"
           onmouseover="this.style.borderColor='var(--blue-500)';this.style.background='var(--blue-50)'"
           onmouseout="this.style.borderColor='var(--border)';this.style.background='var(--surface)'">
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75" style="width:24px;height:24px;color:var(--blue-500)">
            <path d="M6.5 3.5H3a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h9a1 1 0 0 0 1-1v-3.5M9.5 2H14v4.5M14 2l-7 7" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
          <div>
            <div style="font-weight:600;font-size:.9375rem"><%= tool.label %></div>
            <%= if tool.description do %>
              <div style="font-size:.8125rem;color:var(--text-secondary);margin-top:2px"><%= tool.description %></div>
            <% end %>
          </div>
        </a>
        <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :tools}) do %>
          <form method="post" action={~p"/tools/#{tool.id}/delete"} style="position:absolute;top:6px;right:6px">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <button type="submit"
              style="border:none;background:none;cursor:pointer;padding:4px;color:var(--text-tertiary);border-radius:3px"
              onmouseover="this.style.color='var(--color-error,#ef4444)'"
              onmouseout="this.style.color='var(--text-tertiary)'"
              title="Remove">
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75" style="width:13px;height:13px">
                <path d="M2 2l12 12M14 2L2 14" stroke-linecap="round"/>
              </svg>
            </button>
          </form>
        <% end %>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 7: Add routes**

In `lib/atrium_web/router.ex`, authenticated scope:

```elixir
get  "/tools",            ToolsController, :index
post "/tools",            ToolsController, :create_tool
post "/tools/:id/delete", ToolsController, :delete_tool
```

- [ ] **Step 8: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add priv/repo/tenant_migrations/20260501000004_create_tool_links.exs \
        lib/atrium/tools.ex lib/atrium/tools/ \
        lib/atrium_web/controllers/tools_controller.ex \
        lib/atrium_web/controllers/tools_html.ex \
        lib/atrium_web/controllers/tools_html/ \
        lib/atrium_web/router.ex
git commit -m "feat: tools & applications launchpad"
```

---

## Task 8: Compliance Policies View

The compliance section uses the generic document flow. Build a dedicated compliance index that shows all approved policy documents as a clean list — read-only for all staff, editable for compliance officers. Reuses `Documents.list_documents/3`.

**Files:**
- Create: `lib/atrium_web/controllers/compliance_controller.ex`
- Create: `lib/atrium_web/controllers/compliance_html.ex`
- Create: `lib/atrium_web/controllers/compliance_html/index.html.heex`
- Modify: `lib/atrium_web/router.ex`

- [ ] **Step 1: Create ComplianceController**

```elixir
# lib/atrium_web/controllers/compliance_controller.ex
defmodule AtriumWeb.ComplianceController do
  use AtriumWeb, :controller
  alias Atrium.Documents

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "compliance"}]
       when action in [:index]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    policies = Documents.list_documents(prefix, "compliance", status: "approved")
    drafts =
      if Atrium.Authorization.Policy.can?(prefix, conn.assigns.current_user, :edit, {:section, :compliance}) do
        Documents.list_documents(prefix, "compliance")
        |> Enum.reject(&(&1.status == "approved"))
      else
        []
      end
    render(conn, :index, policies: policies, drafts: drafts)
  end
end
```

- [ ] **Step 2: Create ComplianceHTML module**

```elixir
# lib/atrium_web/controllers/compliance_html.ex
defmodule AtriumWeb.ComplianceHTML do
  use AtriumWeb, :html
  embed_templates "compliance_html/*"
end
```

- [ ] **Step 3: Create compliance index template**

```heex
<%# lib/atrium_web/controllers/compliance_html/index.html.heex %>
<div class="atrium-anim">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:28px">
    <div>
      <div class="atrium-page-eyebrow">Compliance</div>
      <h1 class="atrium-page-title">Compliance & Policies</h1>
    </div>
    <%= if Atrium.Authorization.Policy.can?(@conn.assigns.tenant_prefix, @conn.assigns.current_user, :edit, {:section, :compliance}) do %>
      <a href={~p"/sections/compliance/documents/new"} class="atrium-btn atrium-btn-primary">New policy</a>
    <% end %>
  </div>

  <div class="atrium-card" style="margin-bottom:16px">
    <div class="atrium-card-header"><div class="atrium-card-title">Active policies</div></div>
    <table class="atrium-table">
      <thead>
        <tr>
          <th>Policy</th>
          <th>Approved</th>
          <th>Version</th>
        </tr>
      </thead>
      <tbody>
        <%= for doc <- @policies do %>
          <tr onclick={"window.location='#{~p"/sections/compliance/documents/#{doc.id}"}';"} style="cursor:pointer">
            <td style="font-weight:500">
              <a href={~p"/sections/compliance/documents/#{doc.id}"} style="color:var(--text-primary);text-decoration:none"><%= doc.title %></a>
            </td>
            <td style="font-size:.8125rem;color:var(--text-secondary)">
              <%= if doc.approved_at, do: Calendar.strftime(doc.approved_at, "%d %b %Y"), else: "—" %>
            </td>
            <td style="font-family:'IBM Plex Mono',monospace;font-size:.8125rem">v<%= doc.current_version %></td>
          </tr>
        <% end %>
        <%= if @policies == [] do %>
          <tr><td colspan="3" style="padding:32px;text-align:center;color:var(--text-tertiary)">No approved policies yet.</td></tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <%= if @drafts != [] do %>
    <div class="atrium-card">
      <div class="atrium-card-header"><div class="atrium-card-title">In progress</div></div>
      <table class="atrium-table">
        <thead>
          <tr>
            <th>Policy</th>
            <th>Status</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <%= for doc <- @drafts do %>
            <tr>
              <td style="font-weight:500"><%= doc.title %></td>
              <td>
                <span class={"atrium-badge atrium-badge-#{doc.status}"}><%= doc.status %></span>
              </td>
              <td style="text-align:right">
                <a href={~p"/sections/compliance/documents/#{doc.id}"} class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.8125rem">View</a>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% end %>
</div>
```

- [ ] **Step 4: Add route**

```elixir
get "/compliance", ComplianceController, :index
```

- [ ] **Step 5: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add lib/atrium_web/controllers/compliance_controller.ex \
        lib/atrium_web/controllers/compliance_html.ex \
        lib/atrium_web/controllers/compliance_html/ \
        lib/atrium_web/router.ex
git commit -m "feat: compliance policies index with draft/approved split"
```

---

## Task 9: IT Helpdesk Ticket View

IT support uses forms. Build a dedicated helpdesk view that shows: a "Submit a ticket" button (links to the published helpdesk form), and an "My tickets" list (submissions the current user filed). IT staff (who have `edit` on helpdesk) also see all pending submissions. No new DB schema.

**Files:**
- Create: `lib/atrium_web/controllers/helpdesk_controller.ex`
- Create: `lib/atrium_web/controllers/helpdesk_html.ex`
- Create: `lib/atrium_web/controllers/helpdesk_html/index.html.heex`
- Modify: `lib/atrium_web/router.ex`

- [ ] **Step 1: Create HelpdeskController**

```elixir
# lib/atrium_web/controllers/helpdesk_controller.ex
defmodule AtriumWeb.HelpdeskController do
  use AtriumWeb, :controller
  alias Atrium.Forms

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "helpdesk"}]
       when action in [:index]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    # Find published forms for the helpdesk section
    ticket_forms = Forms.list_forms(prefix, "helpdesk") |> Enum.filter(&(&1.status == "published"))

    # All submissions by this user across helpdesk forms
    my_submissions = Forms.list_submissions_for_user(prefix, user.id, "helpdesk")

    # If user can edit (IT staff), also show all pending
    pending =
      if Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, :helpdesk}) do
        Forms.list_pending_submissions(prefix, "helpdesk")
      else
        []
      end

    render(conn, :index, ticket_forms: ticket_forms, my_submissions: my_submissions, pending: pending)
  end
end
```

- [ ] **Step 2: Add missing context functions to Atrium.Forms**

In `lib/atrium/forms.ex`, add:

```elixir
def list_submissions_for_user(prefix, user_id, section_key) do
  import Ecto.Query
  alias Atrium.Forms.{FormSubmission, Form}

  Repo.all(
    from s in FormSubmission,
      join: f in Form, on: f.id == s.form_id,
      where: f.section_key == ^section_key and s.submitted_by_id == ^user_id,
      order_by: [desc: s.inserted_at],
      preload: [form: f],
    prefix: prefix
  )
end

def list_pending_submissions(prefix, section_key) do
  import Ecto.Query
  alias Atrium.Forms.{FormSubmission, Form}

  Repo.all(
    from s in FormSubmission,
      join: f in Form, on: f.id == s.form_id,
      where: f.section_key == ^section_key and s.status == "pending",
      order_by: [desc: s.inserted_at],
      preload: [form: f],
    prefix: prefix
  )
end
```

- [ ] **Step 3: Create HelpdeskHTML module**

```elixir
# lib/atrium_web/controllers/helpdesk_html.ex
defmodule AtriumWeb.HelpdeskHTML do
  use AtriumWeb, :html
  embed_templates "helpdesk_html/*"
end
```

- [ ] **Step 4: Create helpdesk index template**

```heex
<%# lib/atrium_web/controllers/helpdesk_html/index.html.heex %>
<div class="atrium-anim">
  <div style="margin-bottom:28px">
    <div class="atrium-page-eyebrow">IT Support</div>
    <h1 class="atrium-page-title">Help Desk</h1>
  </div>

  <%# Ticket forms %>
  <%= if @ticket_forms != [] do %>
    <div class="atrium-card" style="margin-bottom:20px">
      <div class="atrium-card-header"><div class="atrium-card-title">Submit a request</div></div>
      <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:8px">
        <%= for form <- @ticket_forms do %>
          <a href={~p"/sections/helpdesk/forms/#{form.id}/submit"} class="atrium-sidebar-item" style="border:1px solid var(--border);border-radius:var(--radius);padding:12px 14px">
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75">
              <rect x="2" y="2" width="12" height="12" rx="1.5" stroke-linejoin="round"/>
              <path d="M5 5.5h6M5 8h6M5 10.5h3" stroke-linecap="round"/>
            </svg>
            <%= form.title %>
          </a>
        <% end %>
      </div>
    </div>
  <% end %>

  <%# Pending submissions — IT staff only %>
  <%= if @pending != [] do %>
    <div class="atrium-card" style="margin-bottom:20px">
      <div class="atrium-card-header">
        <div class="atrium-card-title">Pending requests</div>
        <span class="atrium-badge atrium-badge-in_review"><%= length(@pending) %> pending</span>
      </div>
      <table class="atrium-table">
        <thead>
          <tr><th>Form</th><th>Submitted</th><th>Status</th><th></th></tr>
        </thead>
        <tbody>
          <%= for sub <- @pending do %>
            <tr>
              <td style="font-weight:500"><%= sub.form.title %></td>
              <td style="font-size:.8125rem;color:var(--text-secondary)"><%= Calendar.strftime(sub.inserted_at, "%d %b %Y %H:%M") %></td>
              <td><span class="atrium-badge atrium-badge-in_review"><%= sub.status %></span></td>
              <td style="text-align:right">
                <a href={~p"/sections/helpdesk/forms/#{sub.form_id}/submissions/#{sub.id}"} class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.8125rem">Review</a>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% end %>

  <%# My submissions %>
  <div class="atrium-card">
    <div class="atrium-card-header"><div class="atrium-card-title">My requests</div></div>
    <table class="atrium-table">
      <thead>
        <tr><th>Form</th><th>Submitted</th><th>Status</th><th></th></tr>
      </thead>
      <tbody>
        <%= for sub <- @my_submissions do %>
          <tr>
            <td style="font-weight:500"><%= sub.form.title %></td>
            <td style="font-size:.8125rem;color:var(--text-secondary)"><%= Calendar.strftime(sub.inserted_at, "%d %b %Y %H:%M") %></td>
            <td>
              <span class={"atrium-badge #{if sub.status == "completed", do: "atrium-badge-approved", else: "atrium-badge-in_review"}"}>
                <%= sub.status %>
              </span>
            </td>
            <td style="text-align:right">
              <a href={~p"/sections/helpdesk/forms/#{sub.form_id}/submissions/#{sub.id}"} class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.8125rem">View</a>
            </td>
          </tr>
        <% end %>
        <%= if @my_submissions == [] do %>
          <tr><td colspan="4" style="padding:32px;text-align:center;color:var(--text-tertiary)">No requests yet.</td></tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

- [ ] **Step 5: Add route**

```elixir
get "/helpdesk", HelpdeskController, :index
```

- [ ] **Step 6: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add lib/atrium_web/controllers/helpdesk_controller.ex \
        lib/atrium_web/controllers/helpdesk_html.ex \
        lib/atrium_web/controllers/helpdesk_html/ \
        lib/atrium/forms.ex \
        lib/atrium_web/router.ex
git commit -m "feat: IT helpdesk index with ticket forms and submission tracker"
```

---

## Task 10: Polish & Launch Prep

Final wiring: update the sidebar nav to route to the new dedicated pages instead of fallback section routes, and provide a brand-instance setup checklist.

**Files:**
- Modify: `lib/atrium_web/components/layouts/app.html.heex` — update sidebar links for home, news, directory, tools, compliance, helpdesk
- Create: `docs/brand-instance-setup.md`

- [ ] **Step 1: Update sidebar links to use dedicated routes**

In `lib/atrium_web/components/layouts/app.html.heex`, the sidebar currently links to `/sections/:key/documents` for every section. For sections with dedicated routes, override the href:

The sections block currently iterates `@nav`. Add a helper map at the top of the nav block:

```heex
<% dedicated_routes = %{
  "home" => "/home",
  "news" => "/news",
  "directory" => "/directory",
  "tools" => "/tools",
  "compliance" => "/compliance",
  "helpdesk" => "/helpdesk"
} %>
```

Then change the section `<a href>` from:
```heex
<a href={"/sections/#{key}/documents"} ...>
```
to:
```heex
<a href={Map.get(dedicated_routes, key, "/sections/#{key}/documents")} ...>
```

- [ ] **Step 2: Update `section_active` detection for dedicated routes**

The current `section_active` check uses `String.contains?(path, "/sections/#{key}/"`. For dedicated routes it should also match the dedicated path prefix:

```heex
<% dedicated_prefix = Map.get(dedicated_routes, key)
   section_active = String.contains?(path, "/sections/#{key}/") or
                    (dedicated_prefix != nil and String.starts_with?(path, dedicated_prefix))
%>
```

- [ ] **Step 3: Create brand instance setup checklist**

Create `docs/brand-instance-setup.md` with:

```markdown
# Brand Instance Setup Checklist

Use this checklist to spin up a new branded instance (e.g. MCL, ALLDOQ).

## 1. Create the tenant (super admin)
1. Log in to the platform admin at `https://admin.<your-domain>/super`
2. Go to Tenants → New tenant
3. Set slug (e.g. `mcl` or `alldoq`), name, and allow_local_login
4. Save — provisioning runs automatically (creates schema + seeds default groups/ACLs)

## 2. Configure branding (super admin)
1. Go to Tenants → [tenant] → Edit
2. Set theme colours: primary, secondary, accent
3. Toggle enabled sections — select which of the 14 sections this brand will show

## 3. Create the first admin user (tenant admin)
1. Go to the tenant's login URL: `https://<slug>.<your-domain>/login`
2. Use the super admin console (or direct DB insert) to invite the first user and set `is_admin = true`
3. User accepts invitation, sets password

## 4. Configure groups & permissions (tenant admin)
1. Log in as the admin user
2. Go to Admin → Users → invite all staff
3. Assign users to groups: people_and_culture, it, finance, communications, compliance_officers
4. Section ACLs are pre-seeded from SectionRegistry defaults — adjust per brand requirements via Admin → Users → [user] → Permissions

## 5. Create subsections (tenant admin)
For sections that support subsections (HR, Departments, Docs, Projects):
1. Go to Admin → Sections → [section] → Subsections
2. Create subsections (e.g. HR → Payroll, Benefits, Onboarding)
3. Grant subsection-level ACLs to relevant groups

## 6. Enable SSO (optional, super admin)
1. Go to Tenants → [tenant] → IDPs
2. Add OIDC or SAML provider configuration
3. Test login flow

## 7. Seed content
1. Log in as a Communications team member
2. Post first announcement on the Home page
3. Draft and publish first News article
4. Add Tools & Applications links
5. Upload any existing policies to Compliance section
```

- [ ] **Step 4: Run full test suite**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 5: Final commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add lib/atrium_web/components/layouts/app.html.heex docs/brand-instance-setup.md
git commit -m "feat: wire sidebar dedicated routes + brand setup checklist"
```

---

## Progress tracker

| Task | Feature | Status |
|---|---|---|
| Task 1 | Home dashboard (announcements + quick links) | [ ] |
| Task 2 | News feed UI | [ ] |
| Task 3 | Employee directory + profile fields | [ ] |
| Task 4 | Subsection management UI | [ ] |
| Task 5 | Form notification email fanout | [ ] |
| Task 6 | Form version history view | [ ] |
| Task 7 | Tools launchpad | [ ] |
| Task 8 | Compliance policies view | [ ] |
| Task 9 | IT helpdesk ticket view | [ ] |
| Task 10 | Polish + brand instance setup | [ ] |
