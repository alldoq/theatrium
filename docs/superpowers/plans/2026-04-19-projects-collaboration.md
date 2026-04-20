# Projects & Collaboration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Projects section where staff can see and join projects, and editors can create/manage projects with members, status tracking, and update threads.

**Architecture:** New `Atrium.Projects` context with `projects` and `project_members` tables. `ProjectsController` at `/projects` (dedicated, like `FeedbackController`). Update threads are lightweight post records on a project (one table, analogous to document comments). Members are linked via `project_members` join table. Add "projects" to the dedicated nav list.

**Tech Stack:** Phoenix 1.8, Ecto, Triplex schema-per-tenant, `atrium-*` CSS, no LiveView, no Tailwind.

---

## File Structure

**New files:**
- `priv/repo/tenant_migrations/20260502000004_create_projects.exs`
- `lib/atrium/projects/project.ex`
- `lib/atrium/projects/project_member.ex`
- `lib/atrium/projects/project_update.ex`
- `lib/atrium/projects.ex`
- `lib/atrium_web/controllers/projects_controller.ex`
- `lib/atrium_web/controllers/projects_html.ex`
- `lib/atrium_web/controllers/projects_html/index.html.heex`
- `lib/atrium_web/controllers/projects_html/show.html.heex`
- `lib/atrium_web/controllers/projects_html/new.html.heex`
- `lib/atrium_web/controllers/projects_html/edit.html.heex`
- `test/atrium/projects_test.exs`
- `test/atrium_web/controllers/projects_controller_test.exs`

**Modified files:**
- `lib/atrium_web/router.ex` — add projects routes
- `lib/atrium_web/components/layouts/app.html.heex` — add "projects" to dedicated list

---

## Task 1: Migration + schemas + context

**Files:**
- Create: `priv/repo/tenant_migrations/20260502000004_create_projects.exs`
- Create: `lib/atrium/projects/project.ex`
- Create: `lib/atrium/projects/project_member.ex`
- Create: `lib/atrium/projects/project_update.ex`
- Create: `lib/atrium/projects.ex`
- Create: `test/atrium/projects_test.exs`

### Migration

```elixir
# priv/repo/tenant_migrations/20260502000004_create_projects.exs
defmodule Atrium.Repo.TenantMigrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "active"
      add :owner_id, :binary_id, null: false
      timestamps(type: :timestamptz)
    end

    create table(:project_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :binary_id, null: false
      add :role, :string, null: false, default: "member"
      timestamps(type: :timestamptz)
    end

    create unique_index(:project_members, [:project_id, :user_id])
    create index(:project_members, [:project_id])

    create table(:project_updates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, :binary_id, null: false
      add :body, :text, null: false
      timestamps(type: :timestamptz)
    end

    create index(:project_updates, [:project_id])
  end
end
```

### Schemas

```elixir
# lib/atrium/projects/project.ex
defmodule Atrium.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "projects" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "active"
    field :owner_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:title, :description, :status, :owner_id])
    |> validate_required([:title, :owner_id])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_inclusion(:status, ~w(active on_hold completed archived))
  end
end
```

```elixir
# lib/atrium/projects/project_member.ex
defmodule Atrium.Projects.ProjectMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_members" do
    field :project_id, :binary_id
    field :user_id, :binary_id
    field :role, :string, default: "member"
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:project_id, :user_id, :role])
    |> validate_required([:project_id, :user_id])
    |> validate_inclusion(:role, ~w(lead member))
    |> unique_constraint([:project_id, :user_id])
  end
end
```

```elixir
# lib/atrium/projects/project_update.ex
defmodule Atrium.Projects.ProjectUpdate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_updates" do
    field :project_id, :binary_id
    field :author_id, :binary_id
    field :body, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(update, attrs) do
    update
    |> cast(attrs, [:project_id, :author_id, :body])
    |> validate_required([:project_id, :author_id, :body])
    |> validate_length(:body, min: 1, max: 4000)
  end
end
```

### Context

```elixir
# lib/atrium/projects.ex
defmodule Atrium.Projects do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Projects.{Project, ProjectMember, ProjectUpdate}

  def list_projects(prefix) do
    Repo.all(from(p in Project, order_by: [desc: p.inserted_at]), prefix: prefix)
  end

  def get_project!(prefix, id) do
    Repo.get!(Project, id, prefix: prefix)
  end

  def create_project(prefix, attrs, user) do
    attrs = Map.put(stringify(attrs), "owner_id", user.id)
    changeset = Project.changeset(%Project{}, attrs)

    Repo.transaction(fn ->
      with {:ok, project} <- Repo.insert(changeset, prefix: prefix),
           :ok <- audit_project(prefix, "project.created", project, {:user, user.id}) do
        project
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_project(prefix, project, attrs, user) do
    changeset = Project.changeset(project, stringify(attrs))

    Repo.transaction(fn ->
      with {:ok, updated} <- Repo.update(changeset, prefix: prefix),
           :ok <- audit_project(prefix, "project.updated", updated, {:user, user.id}) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def archive_project(prefix, project, user) do
    update_project(prefix, project, %{"status" => "archived"}, user)
  end

  def list_members(prefix, project_id) do
    Repo.all(
      from(m in ProjectMember, where: m.project_id == ^project_id, order_by: m.inserted_at),
      prefix: prefix
    )
  end

  def add_member(prefix, project_id, user_id, role \\ "member") do
    changeset = ProjectMember.changeset(%ProjectMember{}, %{
      project_id: project_id,
      user_id: user_id,
      role: role
    })
    case Repo.insert(changeset, prefix: prefix) do
      {:ok, member} -> {:ok, member}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def remove_member(prefix, project_id, user_id) do
    case Repo.get_by(ProjectMember, [project_id: project_id, user_id: user_id], prefix: prefix) do
      nil -> {:error, :not_found}
      member ->
        Repo.delete(member, prefix: prefix)
        :ok
    end
  end

  def member?(prefix, project_id, user_id) do
    Repo.exists?(
      from(m in ProjectMember, where: m.project_id == ^project_id and m.user_id == ^user_id),
      prefix: prefix
    )
  end

  def list_updates(prefix, project_id) do
    Repo.all(
      from(u in ProjectUpdate, where: u.project_id == ^project_id, order_by: [asc: u.inserted_at]),
      prefix: prefix
    )
  end

  def add_update(prefix, project_id, attrs) do
    changeset = ProjectUpdate.changeset(%ProjectUpdate{}, Map.put(stringify(attrs), "project_id", project_id))
    Repo.insert(changeset, prefix: prefix)
  end

  def get_update(prefix, update_id) do
    Repo.get(ProjectUpdate, update_id, prefix: prefix)
  end

  def delete_update(prefix, update_id) do
    case Repo.get(ProjectUpdate, update_id, prefix: prefix) do
      nil -> {:error, :not_found}
      update ->
        Repo.delete(update, prefix: prefix)
        :ok
    end
  end

  def count_members(prefix, project_id) do
    Repo.aggregate(
      from(m in ProjectMember, where: m.project_id == ^project_id),
      :count,
      :id,
      prefix: prefix
    )
  end

  defp audit_project(prefix, action, project, actor) do
    case Atrium.Audit.log(prefix, action, %{
      actor: actor,
      resource: {"Project", project.id}
    }) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
```

### Tests

```elixir
# test/atrium/projects_test.exs
defmodule Atrium.ProjectsTest do
  use Atrium.DataCase, async: false

  alias Atrium.{Projects, Tenants, Accounts}
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "proj_#{:erlang.unique_integer([:positive])}"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Projects Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "proj_#{System.unique_integer([:positive])}@example.com",
      name: "Owner"
    })
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })

    {:ok, prefix: prefix, user: user}
  end

  test "create_project/3 creates a project", %{prefix: prefix, user: user} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Alpha"}, user)
    assert project.title == "Alpha"
    assert project.owner_id == user.id
    assert project.status == "active"
  end

  test "list_projects/1 returns all projects", %{prefix: prefix, user: user} do
    {:ok, _} = Projects.create_project(prefix, %{"title" => "P1"}, user)
    {:ok, _} = Projects.create_project(prefix, %{"title" => "P2"}, user)
    assert length(Projects.list_projects(prefix)) == 2
  end

  test "update_project/4 updates fields", %{prefix: prefix, user: user} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Old"}, user)
    {:ok, updated} = Projects.update_project(prefix, project, %{"title" => "New", "status" => "on_hold"}, user)
    assert updated.title == "New"
    assert updated.status == "on_hold"
  end

  test "add_member/4 and member?/3", %{prefix: prefix, user: user} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Team"}, user)
    {:ok, %{user: other}} = Accounts.invite_user(prefix, %{
      email: "other_#{System.unique_integer([:positive])}@example.com",
      name: "Other"
    })
    {:ok, other} = Accounts.activate_user_with_password(prefix, other, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    {:ok, _} = Projects.add_member(prefix, project.id, other.id)
    assert Projects.member?(prefix, project.id, other.id)
  end

  test "remove_member/3 removes membership", %{prefix: prefix, user: user} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Team"}, user)
    {:ok, _} = Projects.add_member(prefix, project.id, user.id)
    assert :ok = Projects.remove_member(prefix, project.id, user.id)
    refute Projects.member?(prefix, project.id, user.id)
  end

  test "add_update/3 and list_updates/2", %{prefix: prefix, user: user} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Updates"}, user)
    {:ok, _} = Projects.add_update(prefix, project.id, %{"author_id" => user.id, "body" => "First update"})
    {:ok, _} = Projects.add_update(prefix, project.id, %{"author_id" => user.id, "body" => "Second update"})
    updates = Projects.list_updates(prefix, project.id)
    assert length(updates) == 2
    assert hd(updates).body == "First update"
  end

  test "delete_update/2 removes update", %{prefix: prefix, user: user} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Del"}, user)
    {:ok, update} = Projects.add_update(prefix, project.id, %{"author_id" => user.id, "body" => "Bye"})
    assert :ok = Projects.delete_update(prefix, update.id)
    assert Projects.list_updates(prefix, project.id) == []
  end

  test "delete_update/2 returns error for missing update", %{prefix: prefix} do
    assert {:error, :not_found} = Projects.delete_update(prefix, Ecto.UUID.generate())
  end

  test "count_members/2 counts correctly", %{prefix: prefix, user: user} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Count"}, user)
    {:ok, _} = Projects.add_member(prefix, project.id, user.id)
    assert Projects.count_members(prefix, project.id) == 1
  end
end
```

### Steps

- [ ] **Step 1: Write failing tests**

```bash
mix test test/atrium/projects_test.exs
```

Expected: compile error (module not found).

- [ ] **Step 2: Create migration file**

Create `priv/repo/tenant_migrations/20260502000004_create_projects.exs` as above.

- [ ] **Step 3: Create schema files**

Create `lib/atrium/projects/project.ex`, `lib/atrium/projects/project_member.ex`, `lib/atrium/projects/project_update.ex` as above.

- [ ] **Step 4: Create context `lib/atrium/projects.ex`** as above.

- [ ] **Step 5: Create test file**

Create `test/atrium/projects_test.exs` as above.

- [ ] **Step 6: Run migration and tests**

```bash
mix triplex.migrate
mix test test/atrium/projects_test.exs
```

Expected: 8 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add priv/repo/tenant_migrations/20260502000004_create_projects.exs \
        lib/atrium/projects/project.ex \
        lib/atrium/projects/project_member.ex \
        lib/atrium/projects/project_update.ex \
        lib/atrium/projects.ex \
        test/atrium/projects_test.exs
git commit -m "feat: add Projects context with members and update threads"
```

---

## Task 2: ProjectsController + templates + routes + nav

**Files:**
- Create: `lib/atrium_web/controllers/projects_controller.ex`
- Create: `lib/atrium_web/controllers/projects_html.ex`
- Create: `lib/atrium_web/controllers/projects_html/index.html.heex`
- Create: `lib/atrium_web/controllers/projects_html/show.html.heex`
- Create: `lib/atrium_web/controllers/projects_html/new.html.heex`
- Create: `lib/atrium_web/controllers/projects_html/edit.html.heex`
- Modify: `lib/atrium_web/router.ex`
- Modify: `lib/atrium_web/components/layouts/app.html.heex`
- Create: `test/atrium_web/controllers/projects_controller_test.exs`

### Controller

```elixir
# lib/atrium_web/controllers/projects_controller.ex
defmodule AtriumWeb.ProjectsController do
  use AtriumWeb, :controller
  alias Atrium.Projects
  alias Atrium.Projects.Project

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "projects"}]
       when action in [:index, :show]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "projects"}]
       when action in [:new, :create, :edit, :update, :archive, :add_member, :remove_member]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "projects"})
    projects = Projects.list_projects(prefix)
    member_counts = Map.new(projects, fn p -> {p.id, Projects.count_members(prefix, p.id)} end)
    render(conn, :index, projects: projects, member_counts: member_counts, can_edit: can_edit)
  end

  def new(conn, _params) do
    render(conn, :new, changeset: Project.changeset(%Project{}, %{}))
  end

  def create(conn, %{"project" => attrs}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Projects.create_project(prefix, attrs, user) do
      {:ok, project} ->
        conn
        |> put_flash(:info, "Project created.")
        |> redirect(to: ~p"/projects/#{project.id}")
      {:error, changeset} ->
        conn
        |> put_status(422)
        |> render(:new, changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    project = Projects.get_project!(prefix, id)
    members = Projects.list_members(prefix, id)
    updates = Projects.list_updates(prefix, id)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "projects"})
    is_member = Projects.member?(prefix, id, user.id)

    all_users =
      if can_edit do
        Atrium.Accounts.list_users(prefix)
      else
        []
      end

    render(conn, :show,
      project: project,
      members: members,
      updates: updates,
      can_edit: can_edit,
      is_member: is_member,
      all_users: all_users,
      current_user: user
    )
  end

  def edit(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    project = Projects.get_project!(prefix, id)
    render(conn, :edit, project: project, changeset: Project.changeset(project, %{}))
  end

  def update(conn, %{"id" => id, "project" => attrs}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    project = Projects.get_project!(prefix, id)

    case Projects.update_project(prefix, project, attrs, user) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, "Project updated.")
        |> redirect(to: ~p"/projects/#{updated.id}")
      {:error, changeset} ->
        conn
        |> put_status(422)
        |> render(:edit, project: project, changeset: changeset)
    end
  end

  def archive(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    project = Projects.get_project!(prefix, id)

    case Projects.archive_project(prefix, project, user) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Project archived.")
        |> redirect(to: ~p"/projects")
      {:error, _} ->
        conn
        |> put_flash(:error, "Could not archive project.")
        |> redirect(to: ~p"/projects/#{id}")
    end
  end

  def add_member(conn, %{"id" => id, "user_id" => user_id}) do
    prefix = conn.assigns.tenant_prefix
    Projects.add_member(prefix, id, user_id)
    redirect(conn, to: ~p"/projects/#{id}")
  end

  def add_member(conn, %{"id" => id}) do
    redirect(conn, to: ~p"/projects/#{id}")
  end

  def remove_member(conn, %{"id" => id, "user_id" => user_id}) do
    prefix = conn.assigns.tenant_prefix
    Projects.remove_member(prefix, id, user_id)
    redirect(conn, to: ~p"/projects/#{id}")
  end

  def add_update(conn, %{"id" => id, "update" => %{"body" => body}}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Projects.add_update(prefix, id, %{"author_id" => user.id, "body" => body}) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Update posted.")
        |> redirect(to: ~p"/projects/#{id}" <> "#updates")
      {:error, _} ->
        conn
        |> put_flash(:error, "Update cannot be blank.")
        |> redirect(to: ~p"/projects/#{id}" <> "#updates")
    end
  end

  def add_update(conn, %{"id" => id}) do
    conn
    |> put_flash(:error, "Update cannot be blank.")
    |> redirect(to: ~p"/projects/#{id}" <> "#updates")
  end

  def delete_update(conn, %{"id" => id, "uid" => uid}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "projects"})
    project_update = Projects.get_update(prefix, uid)

    cond do
      is_nil(project_update) ->
        redirect(conn, to: ~p"/projects/#{id}" <> "#updates")
      can_edit || project_update.author_id == user.id ->
        Projects.delete_update(prefix, uid)
        conn
        |> put_flash(:info, "Update deleted.")
        |> redirect(to: ~p"/projects/#{id}" <> "#updates")
      true ->
        conn
        |> put_flash(:error, "Not authorised.")
        |> redirect(to: ~p"/projects/#{id}" <> "#updates")
    end
  end
end
```

### HTML module

```elixir
# lib/atrium_web/controllers/projects_html.ex
defmodule AtriumWeb.ProjectsHTML do
  use AtriumWeb, :html
  embed_templates "projects_html/*"
end
```

### Template: index

```heex
<%# lib/atrium_web/controllers/projects_html/index.html.heex %>
<div class="atrium-anim">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:28px">
    <div>
      <div class="atrium-page-eyebrow">Projects</div>
      <h1 class="atrium-page-title">Projects &amp; Collaboration</h1>
    </div>
    <%= if @can_edit do %>
      <a href={~p"/projects/new"} class="atrium-btn atrium-btn-primary">New project</a>
    <% end %>
  </div>

  <div class="atrium-card">
    <table class="atrium-table">
      <thead>
        <tr>
          <th>Project</th>
          <th>Status</th>
          <th>Members</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <%= for project <- @projects do %>
          <tr>
            <td style="font-weight:500">
              <a href={~p"/projects/#{project.id}"} style="color:var(--text-primary);text-decoration:none"><%= project.title %></a>
            </td>
            <td>
              <span class={"atrium-badge atrium-badge-#{project.status}"}><%= project.status %></span>
            </td>
            <td style="font-size:.875rem;color:var(--text-secondary)">
              <%= Map.get(@member_counts, project.id, 0) %>
            </td>
            <td style="text-align:right">
              <a href={~p"/projects/#{project.id}"} class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.8125rem">View</a>
            </td>
          </tr>
        <% end %>
        <%= if @projects == [] do %>
          <tr>
            <td colspan="4" style="padding:32px;text-align:center;color:var(--text-tertiary)">
              No projects yet.<%= if @can_edit do %> <a href={~p"/projects/new"} style="color:var(--blue-600)">Create one</a>.<% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

### Template: show

```heex
<%# lib/atrium_web/controllers/projects_html/show.html.heex %>
<div class="atrium-anim">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:28px">
    <div>
      <div class="atrium-page-eyebrow">Projects</div>
      <h1 class="atrium-page-title"><%= @project.title %></h1>
      <span class={"atrium-badge atrium-badge-#{@project.status}"}><%= @project.status %></span>
    </div>
    <%= if @can_edit do %>
      <div style="display:flex;gap:8px">
        <a href={~p"/projects/#{@project.id}/edit"} class="atrium-btn atrium-btn-ghost">Edit</a>
        <form action={~p"/projects/#{@project.id}/archive"} method="post" style="display:inline">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button type="submit" class="atrium-btn atrium-btn-ghost" onclick="return confirm('Archive this project?')">Archive</button>
        </form>
      </div>
    <% end %>
  </div>

  <div style="display:grid;grid-template-columns:1fr 320px;gap:24px;align-items:start">
    <div>
      <%= if @project.description do %>
        <div class="atrium-card" style="margin-bottom:24px">
          <div class="atrium-card-header"><div class="atrium-card-title">About</div></div>
          <div style="padding:16px 20px;color:var(--text-secondary);white-space:pre-wrap"><%= @project.description %></div>
        </div>
      <% end %>

      <div class="atrium-card" id="updates">
        <div class="atrium-card-header">
          <div class="atrium-card-title">Updates</div>
        </div>
        <div style="padding:0 20px">
          <%= for update <- @updates do %>
            <div style="border-bottom:1px solid var(--border);padding:12px 0;display:flex;gap:12px;align-items:flex-start">
              <div style="flex:1">
                <div style="font-size:.8125rem;color:var(--text-tertiary);margin-bottom:4px">
                  <%= Calendar.strftime(update.inserted_at, "%b %-d, %Y") %>
                </div>
                <div style="white-space:pre-wrap"><%= update.body %></div>
              </div>
              <%= if @can_edit || update.author_id == @current_user.id do %>
                <form action={~p"/projects/#{@project.id}/updates/#{update.id}/delete"} method="post" style="display:inline">
                  <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                  <button type="submit" class="atrium-btn atrium-btn-ghost" style="height:24px;font-size:.75rem;padding:0 8px">Delete</button>
                </form>
              <% end %>
            </div>
          <% end %>
          <%= if @updates == [] do %>
            <div style="padding:32px 0;text-align:center;color:var(--text-tertiary)">No updates yet.</div>
          <% end %>
        </div>
        <div style="padding:16px 20px;border-top:1px solid var(--border)">
          <form action={~p"/projects/#{@project.id}/updates"} method="post">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <textarea name="update[body]" placeholder="Post an update…" rows="3" style="width:100%;padding:8px 10px;border:1px solid var(--border);border-radius:6px;font-size:.875rem;resize:vertical;background:var(--surface);color:var(--text-primary)"></textarea>
            <div style="margin-top:8px;text-align:right">
              <button type="submit" class="atrium-btn atrium-btn-primary" style="height:28px;font-size:.8125rem">Post update</button>
            </div>
          </form>
        </div>
      </div>
    </div>

    <div>
      <div class="atrium-card">
        <div class="atrium-card-header"><div class="atrium-card-title">Members</div></div>
        <div style="padding:0 20px">
          <%= for member <- @members do %>
            <div style="display:flex;align-items:center;justify-content:space-between;padding:8px 0;border-bottom:1px solid var(--border)">
              <div style="font-size:.875rem"><%= member.user_id %></div>
              <div style="display:flex;align-items:center;gap:8px">
                <span style="font-size:.75rem;color:var(--text-tertiary)"><%= member.role %></span>
                <%= if @can_edit do %>
                  <form action={~p"/projects/#{@project.id}/members/#{member.user_id}/delete"} method="post" style="display:inline">
                    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                    <button type="submit" class="atrium-btn atrium-btn-ghost" style="height:22px;font-size:.75rem;padding:0 6px">×</button>
                  </form>
                <% end %>
              </div>
            </div>
          <% end %>
          <%= if @members == [] do %>
            <div style="padding:16px 0;text-align:center;color:var(--text-tertiary);font-size:.875rem">No members yet.</div>
          <% end %>
        </div>
        <%= if @can_edit do %>
          <div style="padding:12px 20px;border-top:1px solid var(--border)">
            <form action={~p"/projects/#{@project.id}/members"} method="post">
              <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
              <select name="user_id" style="width:100%;padding:6px 8px;border:1px solid var(--border);border-radius:6px;font-size:.875rem;background:var(--surface);color:var(--text-primary);margin-bottom:8px">
                <option value="">Add member…</option>
                <%= for user <- @all_users do %>
                  <option value={user.id}><%= user.name %> (<%= user.email %>)</option>
                <% end %>
              </select>
              <button type="submit" class="atrium-btn atrium-btn-ghost" style="width:100%;height:28px;font-size:.8125rem">Add</button>
            </form>
          </div>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

### Template: new

```heex
<%# lib/atrium_web/controllers/projects_html/new.html.heex %>
<div class="atrium-anim">
  <div style="margin-bottom:28px">
    <div class="atrium-page-eyebrow">Projects</div>
    <h1 class="atrium-page-title">New Project</h1>
  </div>

  <div class="atrium-card" style="max-width:600px">
    <div style="padding:24px">
      <.form for={@changeset} action={~p"/projects"} method="post">
        <div style="margin-bottom:16px">
          <label style="display:block;font-size:.875rem;font-weight:500;margin-bottom:4px">Title</label>
          <.input field={@changeset[:title]} type="text" style="width:100%" />
        </div>
        <div style="margin-bottom:16px">
          <label style="display:block;font-size:.875rem;font-weight:500;margin-bottom:4px">Description</label>
          <.input field={@changeset[:description]} type="textarea" rows="4" style="width:100%" />
        </div>
        <div style="display:flex;gap:8px;justify-content:flex-end">
          <a href={~p"/projects"} class="atrium-btn atrium-btn-ghost">Cancel</a>
          <button type="submit" class="atrium-btn atrium-btn-primary">Create project</button>
        </div>
      </.form>
    </div>
  </div>
</div>
```

### Template: edit

```heex
<%# lib/atrium_web/controllers/projects_html/edit.html.heex %>
<div class="atrium-anim">
  <div style="margin-bottom:28px">
    <div class="atrium-page-eyebrow">Projects</div>
    <h1 class="atrium-page-title">Edit Project</h1>
  </div>

  <div class="atrium-card" style="max-width:600px">
    <div style="padding:24px">
      <.form for={@changeset} action={~p"/projects/#{@project.id}"} method="post">
        <input type="hidden" name="_method" value="put" />
        <div style="margin-bottom:16px">
          <label style="display:block;font-size:.875rem;font-weight:500;margin-bottom:4px">Title</label>
          <.input field={@changeset[:title]} type="text" style="width:100%" />
        </div>
        <div style="margin-bottom:16px">
          <label style="display:block;font-size:.875rem;font-weight:500;margin-bottom:4px">Description</label>
          <.input field={@changeset[:description]} type="textarea" rows="4" style="width:100%" />
        </div>
        <div style="margin-bottom:16px">
          <label style="display:block;font-size:.875rem;font-weight:500;margin-bottom:4px">Status</label>
          <select name="project[status]" style="padding:6px 10px;border:1px solid var(--border);border-radius:6px;font-size:.875rem;background:var(--surface);color:var(--text-primary)">
            <%= for status <- ~w(active on_hold completed archived) do %>
              <option value={status} selected={@project.status == status}><%= status %></option>
            <% end %>
          </select>
        </div>
        <div style="display:flex;gap:8px;justify-content:flex-end">
          <a href={~p"/projects/#{@project.id}"} class="atrium-btn atrium-btn-ghost">Cancel</a>
          <button type="submit" class="atrium-btn atrium-btn-primary">Save changes</button>
        </div>
      </.form>
    </div>
  </div>
</div>
```

### Router change

In `lib/atrium_web/router.ex`, add after `get "/feedback", FeedbackController, :index`:

```elixir
get    "/projects",                                     ProjectsController, :index
get    "/projects/new",                                 ProjectsController, :new
post   "/projects",                                     ProjectsController, :create
get    "/projects/:id",                                 ProjectsController, :show
get    "/projects/:id/edit",                            ProjectsController, :edit
put    "/projects/:id",                                 ProjectsController, :update
post   "/projects/:id/archive",                         ProjectsController, :archive
post   "/projects/:id/members",                         ProjectsController, :add_member
post   "/projects/:id/members/:user_id/delete",         ProjectsController, :remove_member
post   "/projects/:id/updates",                         ProjectsController, :add_update
post   "/projects/:id/updates/:uid/delete",             ProjectsController, :delete_update
```

### Nav change

In `lib/atrium_web/components/layouts/app.html.heex`, change:

```elixir
<% dedicated = ~w(home news directory tools compliance helpdesk events learning feedback) %>
```

to:

```elixir
<% dedicated = ~w(home news directory tools compliance helpdesk events learning feedback projects) %>
```

### Tests

```elixir
# test/atrium_web/controllers/projects_controller_test.exs
defmodule AtriumWeb.ProjectsControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Accounts, Authorization, Tenants, Projects}
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "pr_#{:erlang.unique_integer([:positive])}"
    host = "#{slug}.atrium.example"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Projects Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: viewer}} = Accounts.invite_user(prefix, %{
      email: "viewer_#{System.unique_integer([:positive])}@example.com",
      name: "Viewer"
    })
    {:ok, viewer} = Accounts.activate_user_with_password(prefix, viewer, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "projects", {:user, viewer.id}, :view)

    {:ok, %{user: editor}} = Accounts.invite_user(prefix, %{
      email: "editor_#{System.unique_integer([:positive])}@example.com",
      name: "Editor"
    })
    {:ok, editor} = Accounts.activate_user_with_password(prefix, editor, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "projects", {:user, editor.id}, :view)
    Authorization.grant_section(prefix, "projects", {:user, editor.id}, :edit)

    viewer_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: viewer.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    editor_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: editor.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    {:ok, viewer_conn: viewer_conn, editor_conn: editor_conn, prefix: prefix, viewer: viewer, editor: editor}
  end

  test "GET /projects shows index to viewer", %{viewer_conn: viewer_conn} do
    conn = get(viewer_conn, "/projects")
    assert html_response(conn, 200) =~ "Projects"
  end

  test "GET /projects shows New project button to editor only", %{viewer_conn: viewer_conn, editor_conn: editor_conn} do
    assert get(editor_conn, "/projects") |> html_response(200) =~ "New project"
    refute get(viewer_conn, "/projects") |> html_response(200) =~ "New project"
  end

  test "POST /projects creates project and redirects", %{editor_conn: editor_conn} do
    conn = post(editor_conn, "/projects", %{"project" => %{"title" => "Alpha Project", "description" => "Test"}})
    assert redirected_to(conn) =~ "/projects/"
  end

  test "GET /projects/:id shows project to viewer", %{viewer_conn: viewer_conn, prefix: prefix, editor: editor} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Visible"}, editor)
    conn = get(viewer_conn, "/projects/#{project.id}")
    assert html_response(conn, 200) =~ "Visible"
  end

  test "GET /projects/:id shows edit controls to editor only", %{viewer_conn: viewer_conn, editor_conn: editor_conn, prefix: prefix, editor: editor} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Controls"}, editor)
    assert get(editor_conn, "/projects/#{project.id}") |> html_response(200) =~ "Edit"
    refute get(viewer_conn, "/projects/#{project.id}") |> html_response(200) =~ ~s(href="/projects/#{project.id}/edit")
  end

  test "POST /projects/:id/updates adds an update", %{viewer_conn: viewer_conn, prefix: prefix, editor: editor} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Updates"}, editor)
    conn = post(viewer_conn, "/projects/#{project.id}/updates", %{"update" => %{"body" => "Hello world"}})
    assert redirected_to(conn) =~ "/projects/#{project.id}"
    assert length(Projects.list_updates(prefix, project.id)) == 1
  end

  test "POST /projects/:id/archive archives project", %{editor_conn: editor_conn, prefix: prefix, editor: editor} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "To archive"}, editor)
    conn = post(editor_conn, "/projects/#{project.id}/archive")
    assert redirected_to(conn) == "/projects"
    assert Projects.get_project!(prefix, project.id).status == "archived"
  end
end
```

### Steps

- [ ] **Step 1: Write failing tests**

```bash
mix test test/atrium_web/controllers/projects_controller_test.exs
```

Expected: compile error or route not found.

- [ ] **Step 2: Create HTML module `lib/atrium_web/controllers/projects_html.ex`** as above.

- [ ] **Step 3: Create controller `lib/atrium_web/controllers/projects_controller.ex`** as above.

- [ ] **Step 4: Create templates**

Create `lib/atrium_web/controllers/projects_html/` directory and all four templates as above.

- [ ] **Step 5: Add routes to `lib/atrium_web/router.ex`** as specified above, after the feedback route.

- [ ] **Step 6: Add "projects" to dedicated nav list in `lib/atrium_web/components/layouts/app.html.heex`** as specified above.

- [ ] **Step 7: Run tests**

```bash
mix test test/atrium_web/controllers/projects_controller_test.exs
```

Expected: 7 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add lib/atrium_web/controllers/projects_controller.ex \
        lib/atrium_web/controllers/projects_html.ex \
        lib/atrium_web/controllers/projects_html/index.html.heex \
        lib/atrium_web/controllers/projects_html/show.html.heex \
        lib/atrium_web/controllers/projects_html/new.html.heex \
        lib/atrium_web/controllers/projects_html/edit.html.heex \
        lib/atrium_web/router.ex \
        lib/atrium_web/components/layouts/app.html.heex \
        test/atrium_web/controllers/projects_controller_test.exs
git commit -m "feat: add Projects dedicated section with CRUD, members, and update threads"
```
