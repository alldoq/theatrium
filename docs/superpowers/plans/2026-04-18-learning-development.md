# Learning & Development Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow staff to browse a course catalog, view materials (linked documents + external URLs), and self-report completion; People & Culture staff manage courses.

**Architecture:** Three new tenant-scoped tables (`courses`, `course_materials`, `course_completions`) managed by `Atrium.Learning` context. `LearningController` handles all UI at `/learning`. Completion is self-reported via upsert/delete on `course_completions`.

**Tech Stack:** Phoenix 1.8, Ecto, PostgreSQL (Triplex tenant prefix via `priv/repo/tenant_migrations/`), `atrium-*` CSS, no LiveView, no Tailwind, vanilla JS for materials form.

---

## File Structure

**New files:**
- `priv/repo/tenant_migrations/TIMESTAMP_create_learning_tables.exs` — courses + course_materials + course_completions
- `lib/atrium/learning/course.ex` — Ecto schema
- `lib/atrium/learning/course_material.ex` — Ecto schema
- `lib/atrium/learning/course_completion.ex` — Ecto schema
- `lib/atrium/learning.ex` — context: list, get, create, update, archive, publish, materials CRUD, complete/uncomplete
- `lib/atrium_web/controllers/learning_controller.ex` — index/show/new/create/edit/update/publish/archive/complete/uncomplete
- `lib/atrium_web/controllers/learning_html.ex` — HTML module
- `lib/atrium_web/controllers/learning_html/index.html.heex`
- `lib/atrium_web/controllers/learning_html/show.html.heex`
- `lib/atrium_web/controllers/learning_html/new.html.heex`
- `lib/atrium_web/controllers/learning_html/edit.html.heex`
- `test/atrium/learning_test.exs`
- `test/atrium_web/controllers/learning_controller_test.exs`

**Modified files:**
- `lib/atrium_web/router.ex` — add `/learning` routes
- `lib/atrium_web/components/layouts/app.html.heex` — add Learning to nav (already handled by AppShell via SectionRegistry; no change needed if nav is dynamic)

---

### Task 1: Migrations + Schemas

**Files:**
- Create: `priv/repo/tenant_migrations/20260418300001_create_learning_tables.exs`
- Create: `lib/atrium/learning/course.ex`
- Create: `lib/atrium/learning/course_material.ex`
- Create: `lib/atrium/learning/course_completion.ex`
- Create: `test/atrium/learning_test.exs` (failing tests first)

- [ ] **Step 1: Write failing tests**

Create `test/atrium/learning_test.exs`:

```elixir
defmodule Atrium.LearningTest do
  use Atrium.TenantCase, async: false

  alias Atrium.Learning
  alias Atrium.Learning.{Course, CourseMaterial, CourseCompletion}
  alias Atrium.Accounts

  defp build_user(prefix) do
    {:ok, %{user: user}} =
      Accounts.invite_user(prefix, %{
        email: "learning_actor_#{System.unique_integer([:positive])}@example.com",
        name: "Learning Actor"
      })
    user
  end

  defp build_course(prefix, user, attrs \\ %{}) do
    base = %{title: "Intro to Safety", description: "Safety course", category: "Compliance"}
    Learning.create_course(prefix, Map.merge(base, attrs), user)
  end

  describe "create_course/3" do
    test "creates a course with status draft", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:ok, %Course{status: "draft", title: "Intro to Safety"}} =
               build_course(prefix, user)
    end

    test "returns error for missing title", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:error, cs} = Learning.create_course(prefix, %{category: "HR"}, user)
      assert errors_on(cs)[:title]
    end
  end

  describe "publish_course/2" do
    test "sets status to published", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      assert {:ok, %Course{status: "published"}} = Learning.publish_course(prefix, course)
    end
  end

  describe "archive_course/2" do
    test "sets status to archived from published", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      {:ok, course} = Learning.publish_course(prefix, course)
      assert {:ok, %Course{status: "archived"}} = Learning.archive_course(prefix, course)
    end

    test "returns error when archiving a draft", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      assert {:error, _} = Learning.archive_course(prefix, course)
    end
  end

  describe "list_courses/2" do
    test "returns only published courses by default", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, draft} = build_course(prefix, user, %{title: "Draft Course"})
      {:ok, pub} = build_course(prefix, user, %{title: "Published Course"})
      {:ok, _} = Learning.publish_course(prefix, pub)

      results = Learning.list_courses(prefix)
      ids = Enum.map(results, & &1.id)
      assert pub.id in ids
      refute draft.id in ids
    end

    test "returns all courses when status: :all", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, draft} = build_course(prefix, user, %{title: "Draft"})
      {:ok, pub} = build_course(prefix, user, %{title: "Published"})
      {:ok, _} = Learning.publish_course(prefix, pub)

      results = Learning.list_courses(prefix, status: :all)
      ids = Enum.map(results, & &1.id)
      assert draft.id in ids
      assert pub.id in ids
    end
  end

  describe "add_material/3 and list_materials/2" do
    test "adds a URL material", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      assert {:ok, %CourseMaterial{type: "url", title: "OSHA Guide"}} =
               Learning.add_material(prefix, course.id, %{
                 type: "url",
                 title: "OSHA Guide",
                 url: "https://osha.gov/guide",
                 position: 0
               })
    end

    test "returns error for URL material without https", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      assert {:error, cs} =
               Learning.add_material(prefix, course.id, %{
                 type: "url",
                 title: "Bad URL",
                 url: "not-a-url",
                 position: 0
               })
      assert errors_on(cs)[:url]
    end

    test "lists materials ordered by position", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      Learning.add_material(prefix, course.id, %{type: "url", title: "Second", url: "https://b.com", position: 10})
      Learning.add_material(prefix, course.id, %{type: "url", title: "First", url: "https://a.com", position: 0})
      [first, second] = Learning.list_materials(prefix, course.id)
      assert first.title == "First"
      assert second.title == "Second"
    end
  end

  describe "complete_course/3 and uncomplete_course/3" do
    test "marks a course as complete", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      assert {:ok, %CourseCompletion{}} = Learning.complete_course(prefix, course.id, user.id)
      assert Learning.completed?(prefix, course.id, user.id)
    end

    test "complete is idempotent", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      {:ok, _} = Learning.complete_course(prefix, course.id, user.id)
      assert {:ok, _} = Learning.complete_course(prefix, course.id, user.id)
    end

    test "uncomplete removes completion", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, course} = build_course(prefix, user)
      {:ok, _} = Learning.complete_course(prefix, course.id, user.id)
      :ok = Learning.uncomplete_course(prefix, course.id, user.id)
      refute Learning.completed?(prefix, course.id, user.id)
    end

    test "completion_count returns number of completions", %{tenant_prefix: prefix} do
      user1 = build_user(prefix)
      user2 = build_user(prefix)
      {:ok, course} = build_course(prefix, user1)
      Learning.complete_course(prefix, course.id, user1.id)
      Learning.complete_course(prefix, course.id, user2.id)
      assert Learning.completion_count(prefix, course.id) == 2
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium/learning_test.exs 2>&1 | head -20
```

Expected: compile error — `Atrium.Learning` not defined.

- [ ] **Step 3: Create the migration**

```bash
mix ecto.gen.migration create_learning_tables --migrations-path priv/repo/tenant_migrations
```

Edit the generated file (it will be in `priv/repo/tenant_migrations/`). Replace the body with:

```elixir
defmodule Atrium.Repo.Migrations.CreateLearningTables do
  use Ecto.Migration

  def change do
    create table(:courses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :category, :string
      add :status, :string, null: false, default: "draft"
      add :created_by_id, :binary_id, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:courses, [:status])
    create index(:courses, [:category])

    create table(:course_materials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :position, :integer, null: false, default: 0
      add :title, :string, null: false
      add :document_id, :binary_id
      add :url, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:course_materials, [:course_id])
    create index(:course_materials, [:course_id, :position])

    create table(:course_completions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :binary_id, null: false
      add :completed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:course_completions, [:course_id, :user_id])
    create index(:course_completions, [:user_id])
  end
end
```

- [ ] **Step 4: Run tenant migrations**

```bash
mix triplex.migrate
```

Expected: migration runs with no errors.

- [ ] **Step 5: Create Course schema**

Create `lib/atrium/learning/course.ex`:

```elixir
defmodule Atrium.Learning.Course do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "courses" do
    field :title, :string
    field :description, :string
    field :category, :string
    field :status, :string, default: "draft"
    field :created_by_id, :binary_id

    has_many :materials, Atrium.Learning.CourseMaterial, foreign_key: :course_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(course, attrs) do
    course
    |> cast(attrs, [:title, :description, :category, :status, :created_by_id])
    |> validate_required([:title, :created_by_id])
    |> validate_inclusion(:status, ~w(draft published archived))
    |> validate_length(:title, max: 200)
  end
end
```

- [ ] **Step 6: Create CourseMaterial schema**

Create `lib/atrium/learning/course_material.ex`:

```elixir
defmodule Atrium.Learning.CourseMaterial do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "course_materials" do
    field :type, :string
    field :position, :integer, default: 0
    field :title, :string
    field :document_id, :binary_id
    field :url, :string
    field :course_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(material, attrs) do
    material
    |> cast(attrs, [:course_id, :type, :position, :title, :document_id, :url])
    |> validate_required([:course_id, :type, :title, :position])
    |> validate_inclusion(:type, ~w(document url))
    |> validate_url()
    |> validate_document()
  end

  defp validate_url(cs) do
    case get_field(cs, :type) do
      "url" ->
        cs
        |> validate_required([:url])
        |> validate_format(:url, ~r/\Ahttps?:\/\//,
             message: "must start with http:// or https://")
      _ -> cs
    end
  end

  defp validate_document(cs) do
    case get_field(cs, :type) do
      "document" -> validate_required(cs, [:document_id])
      _ -> cs
    end
  end
end
```

- [ ] **Step 7: Create CourseCompletion schema**

Create `lib/atrium/learning/course_completion.ex`:

```elixir
defmodule Atrium.Learning.CourseCompletion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "course_completions" do
    field :course_id, :binary_id
    field :user_id, :binary_id
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [:course_id, :user_id, :completed_at])
    |> validate_required([:course_id, :user_id, :completed_at])
    |> unique_constraint([:course_id, :user_id])
  end
end
```

- [ ] **Step 8: Create the Learning context**

Create `lib/atrium/learning.ex`:

```elixir
defmodule Atrium.Learning do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Learning.{Course, CourseMaterial, CourseCompletion}

  def list_courses(prefix, opts \\ []) do
    query =
      case Keyword.get(opts, :status) do
        :all -> from(c in Course, order_by: [asc: c.category, asc: c.title])
        _ -> from(c in Course, where: c.status == "published", order_by: [asc: c.category, asc: c.title])
      end

    Repo.all(query, prefix: prefix)
  end

  def get_course!(prefix, id), do: Repo.get!(Course, id, prefix: prefix)

  def create_course(prefix, attrs, actor_user) do
    attrs_with_creator = Map.put(stringify(attrs), "created_by_id", actor_user.id)

    %Course{}
    |> Course.changeset(attrs_with_creator)
    |> Repo.insert(prefix: prefix)
  end

  def update_course(prefix, %Course{} = course, attrs) do
    course
    |> Course.changeset(stringify(attrs))
    |> Repo.update(prefix: prefix)
  end

  def publish_course(prefix, %Course{status: "draft"} = course) do
    course
    |> Course.changeset(%{status: "published"})
    |> Repo.update(prefix: prefix)
  end

  def publish_course(_prefix, _course), do: {:error, :invalid_status}

  def archive_course(prefix, %Course{status: "published"} = course) do
    course
    |> Course.changeset(%{status: "archived"})
    |> Repo.update(prefix: prefix)
  end

  def archive_course(_prefix, _course), do: {:error, :invalid_status}

  def list_materials(prefix, course_id) do
    Repo.all(
      from(m in CourseMaterial,
        where: m.course_id == ^course_id,
        order_by: [asc: m.position]
      ),
      prefix: prefix
    )
  end

  def add_material(prefix, course_id, attrs) do
    attrs_with_course = Map.put(stringify(attrs), "course_id", course_id)

    %CourseMaterial{}
    |> CourseMaterial.changeset(attrs_with_course)
    |> Repo.insert(prefix: prefix)
  end

  def delete_material(prefix, material_id) do
    case Repo.get(CourseMaterial, material_id, prefix: prefix) do
      nil -> {:error, :not_found}
      material -> Repo.delete(material, prefix: prefix)
    end
  end

  def complete_course(prefix, course_id, user_id) do
    %CourseCompletion{}
    |> CourseCompletion.changeset(%{
      course_id: course_id,
      user_id: user_id,
      completed_at: DateTime.utc_now()
    })
    |> Repo.insert(
      prefix: prefix,
      on_conflict: :nothing,
      conflict_target: [:course_id, :user_id]
    )
  end

  def uncomplete_course(prefix, course_id, user_id) do
    case Repo.get_by(CourseCompletion, [course_id: course_id, user_id: user_id], prefix: prefix) do
      nil -> :ok
      completion ->
        Repo.delete(completion, prefix: prefix)
        :ok
    end
  end

  def completed?(prefix, course_id, user_id) do
    Repo.exists?(
      from(c in CourseCompletion,
        where: c.course_id == ^course_id and c.user_id == ^user_id
      ),
      prefix: prefix
    )
  end

  def completion_count(prefix, course_id) do
    Repo.aggregate(
      from(c in CourseCompletion, where: c.course_id == ^course_id),
      :count,
      prefix: prefix
    )
  end

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
```

- [ ] **Step 9: Run tests to verify they pass**

```bash
mix test test/atrium/learning_test.exs
```

Expected: `14 tests, 0 failures`

- [ ] **Step 10: Commit**

```bash
git add priv/repo/tenant_migrations/ lib/atrium/learning/ lib/atrium/learning.ex test/atrium/learning_test.exs
git commit -m "feat: add Learning context + schemas + migrations"
```

---

### Task 2: LearningController + Routes + HTML module

**Files:**
- Create: `lib/atrium_web/controllers/learning_controller.ex`
- Create: `lib/atrium_web/controllers/learning_html.ex`
- Modify: `lib/atrium_web/router.ex`
- Create: `test/atrium_web/controllers/learning_controller_test.exs` (failing tests first)

- [ ] **Step 1: Write failing controller tests**

Create `test/atrium_web/controllers/learning_controller_test.exs`:

```elixir
defmodule AtriumWeb.LearningControllerTest do
  use AtriumWeb.TenantConnCase, async: false

  alias Atrium.Learning
  alias Atrium.Accounts

  defp build_user(prefix) do
    {:ok, %{user: user}} =
      Accounts.invite_user(prefix, %{
        email: "lc_actor_#{System.unique_integer([:positive])}@example.com",
        name: "LC Actor"
      })
    user
  end

  defp build_published_course(prefix, user) do
    {:ok, course} = Learning.create_course(prefix, %{title: "Safety 101", category: "Compliance"}, user)
    {:ok, course} = Learning.publish_course(prefix, course)
    course
  end

  setup %{conn: conn, tenant_prefix: prefix} do
    user = build_user(prefix)
    conn = init_test_session(conn, %{user_id: user.id})
    {:ok, conn: conn, user: user, prefix: prefix}
  end

  describe "GET /learning" do
    test "renders published courses", %{conn: conn, user: user, prefix: prefix} do
      build_published_course(prefix, user)
      conn = get(conn, "/learning")
      assert html_response(conn, 200) =~ "Safety 101"
    end

    test "does not show draft courses to regular staff", %{conn: conn, user: user, prefix: prefix} do
      Learning.create_course(prefix, %{title: "Draft Course", category: "HR"}, user)
      conn = get(conn, "/learning")
      html = html_response(conn, 200)
      refute html =~ "Draft Course"
    end
  end

  describe "GET /learning/:id" do
    test "renders course show page", %{conn: conn, user: user, prefix: prefix} do
      course = build_published_course(prefix, user)
      conn = get(conn, "/learning/#{course.id}")
      assert html_response(conn, 200) =~ "Safety 101"
    end

    test "returns 404 for draft course accessed by non-editor", %{conn: conn, user: user, prefix: prefix} do
      {:ok, draft} = Learning.create_course(prefix, %{title: "Draft", category: "HR"}, user)
      conn = get(conn, "/learning/#{draft.id}")
      assert html_response(conn, 404)
    end
  end

  describe "POST /learning/:id/complete" do
    test "marks course as complete and redirects", %{conn: conn, user: user, prefix: prefix} do
      course = build_published_course(prefix, user)
      conn = post(conn, "/learning/#{course.id}/complete")
      assert redirected_to(conn) == "/learning/#{course.id}"
      assert Learning.completed?(prefix, course.id, user.id)
    end
  end

  describe "DELETE /learning/:id/complete" do
    test "removes completion and redirects", %{conn: conn, user: user, prefix: prefix} do
      course = build_published_course(prefix, user)
      Learning.complete_course(prefix, course.id, user.id)
      conn = delete(conn, "/learning/#{course.id}/complete")
      assert redirected_to(conn) == "/learning/#{course.id}"
      refute Learning.completed?(prefix, course.id, user.id)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/atrium_web/controllers/learning_controller_test.exs 2>&1 | head -20
```

Expected: compile error — `LearningController` not defined.

- [ ] **Step 3: Add routes to router.ex**

Edit `lib/atrium_web/router.ex`. Inside the `pipe_through [:authenticated]` scope (after the `/helpdesk` line), add:

```elixir
      get    "/learning",                  LearningController, :index
      get    "/learning/new",              LearningController, :new
      post   "/learning",                  LearningController, :create
      get    "/learning/:id",              LearningController, :show
      get    "/learning/:id/edit",         LearningController, :edit
      put    "/learning/:id",              LearningController, :update
      post   "/learning/:id/publish",      LearningController, :publish
      post   "/learning/:id/archive",      LearningController, :archive
      post   "/learning/:id/complete",     LearningController, :complete
      delete "/learning/:id/complete",     LearningController, :uncomplete
```

- [ ] **Step 4: Create the HTML module**

Create `lib/atrium_web/controllers/learning_html.ex`:

```elixir
defmodule AtriumWeb.LearningHTML do
  use AtriumWeb, :html

  embed_templates "learning_html/*"
end
```

- [ ] **Step 5: Create the controller**

Create `lib/atrium_web/controllers/learning_controller.ex`:

```elixir
defmodule AtriumWeb.LearningController do
  use AtriumWeb, :controller

  alias Atrium.Learning
  alias Atrium.Learning.Course

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "learning"}]
       when action in [:index, :show, :complete, :uncomplete]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "learning"}]
       when action in [:new, :create, :edit, :update, :publish, :archive]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "learning"})

    published = Learning.list_courses(prefix)
    all_courses = if can_edit, do: Learning.list_courses(prefix, status: :all), else: []
    drafts_and_archived = Enum.reject(all_courses, &(&1.status == "published"))

    completion_ids =
      published
      |> Enum.filter(&Learning.completed?(prefix, &1.id, user.id))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    render(conn, :index,
      courses: published,
      drafts_and_archived: drafts_and_archived,
      completion_ids: completion_ids,
      can_edit: can_edit
    )
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    course = Learning.get_course!(prefix, id)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "learning"})

    if course.status != "published" && !can_edit do
      conn |> put_status(:not_found) |> put_view(AtriumWeb.ErrorHTML) |> render(:"404") |> halt()
    else
      materials = Learning.list_materials(prefix, id)
      completed = Learning.completed?(prefix, id, user.id)
      count = if can_edit, do: Learning.completion_count(prefix, id), else: nil

      render(conn, :show,
        course: course,
        materials: materials,
        completed: completed,
        completion_count: count,
        can_edit: can_edit
      )
    end
  end

  def new(conn, _params) do
    render(conn, :new, changeset: Course.changeset(%Course{}, %{}))
  end

  def create(conn, %{"course" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Learning.create_course(prefix, params, user) do
      {:ok, course} ->
        conn
        |> put_flash(:info, "Course created.")
        |> redirect(to: ~p"/learning/#{course.id}/edit")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Could not create course.")
        |> render(:new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, id)
    materials = Learning.list_materials(prefix, id)
    render(conn, :edit,
      course: course,
      materials: materials,
      changeset: Course.changeset(course, %{})
    )
  end

  def update(conn, %{"id" => id, "course" => params}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, id)

    case Learning.update_course(prefix, course, params) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, "Course updated.")
        |> redirect(to: ~p"/learning/#{updated.id}")

      {:error, changeset} ->
        materials = Learning.list_materials(prefix, id)
        conn
        |> put_flash(:error, "Could not update course.")
        |> render(:edit, course: course, materials: materials, changeset: changeset)
    end
  end

  def publish(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, id)

    case Learning.publish_course(prefix, course) do
      {:ok, _} ->
        conn |> put_flash(:info, "Course published.") |> redirect(to: ~p"/learning/#{id}")
      {:error, _} ->
        conn |> put_flash(:error, "Cannot publish this course.") |> redirect(to: ~p"/learning/#{id}/edit")
    end
  end

  def archive(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, id)

    case Learning.archive_course(prefix, course) do
      {:ok, _} ->
        conn |> put_flash(:info, "Course archived.") |> redirect(to: ~p"/learning")
      {:error, _} ->
        conn |> put_flash(:error, "Cannot archive this course.") |> redirect(to: ~p"/learning/#{id}")
    end
  end

  def complete(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    Learning.complete_course(prefix, id, user.id)
    conn |> redirect(to: ~p"/learning/#{id}")
  end

  def uncomplete(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    Learning.uncomplete_course(prefix, id, user.id)
    conn |> redirect(to: ~p"/learning/#{id}")
  end
end
```

- [ ] **Step 6: Create stub templates so the controller compiles**

Create `lib/atrium_web/controllers/learning_html/index.html.heex`:

```heex
<div>Learning index stub</div>
```

Create `lib/atrium_web/controllers/learning_html/show.html.heex`:

```heex
<div>Learning show stub</div>
```

Create `lib/atrium_web/controllers/learning_html/new.html.heex`:

```heex
<div>Learning new stub</div>
```

Create `lib/atrium_web/controllers/learning_html/edit.html.heex`:

```heex
<div>Learning edit stub</div>
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
mix test test/atrium_web/controllers/learning_controller_test.exs
```

Expected: `6 tests, 0 failures`

- [ ] **Step 8: Commit**

```bash
git add lib/atrium_web/controllers/learning_controller.ex \
        lib/atrium_web/controllers/learning_html.ex \
        lib/atrium_web/controllers/learning_html/ \
        lib/atrium_web/router.ex \
        test/atrium_web/controllers/learning_controller_test.exs
git commit -m "feat: add LearningController + routes + stub templates"
```

---

### Task 3: Templates

**Files:**
- Replace: `lib/atrium_web/controllers/learning_html/index.html.heex`
- Replace: `lib/atrium_web/controllers/learning_html/show.html.heex`
- Replace: `lib/atrium_web/controllers/learning_html/new.html.heex`
- Replace: `lib/atrium_web/controllers/learning_html/edit.html.heex`

- [ ] **Step 1: Replace index template**

Replace `lib/atrium_web/controllers/learning_html/index.html.heex` with:

```heex
<div class="atrium-anim" style="max-width:800px">
  <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:24px">
    <div>
      <div class="atrium-page-eyebrow">Platform</div>
      <h1 class="atrium-page-title">Learning &amp; Development</h1>
    </div>
    <%= if @can_edit do %>
      <a href={~p"/learning/new"} class="atrium-btn atrium-btn-primary">New course</a>
    <% end %>
  </div>

  <%= if Enum.empty?(@courses) do %>
    <div class="atrium-card">
      <div class="atrium-card-body" style="text-align:center;padding:40px;color:var(--text-tertiary)">
        No published courses yet.
      </div>
    </div>
  <% else %>
    <%= for {category, courses} <- Enum.group_by(@courses, & &1.category) do %>
      <div style="margin-bottom:32px">
        <div style="font-size:.75rem;font-weight:600;color:var(--text-tertiary);text-transform:uppercase;letter-spacing:.05em;margin-bottom:10px">
          <%= category || "General" %>
        </div>
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:12px">
          <%= for course <- courses do %>
            <a href={~p"/learning/#{course.id}"} style="text-decoration:none">
              <div class="atrium-card" style="height:100%;transition:box-shadow .15s">
                <div class="atrium-card-body">
                  <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:8px">
                    <div style="font-size:.9375rem;font-weight:600;color:var(--text-primary);line-height:1.35">
                      <%= course.title %>
                    </div>
                    <%= if MapSet.member?(@completion_ids, course.id) do %>
                      <svg viewBox="0 0 16 16" width="18" height="18" fill="none" stroke="var(--green-600,#16a34a)" stroke-width="2" style="flex-shrink:0;margin-top:2px">
                        <circle cx="8" cy="8" r="6"/>
                        <path d="M5 8l2.5 2.5L11 5" stroke-linecap="round" stroke-linejoin="round"/>
                      </svg>
                    <% end %>
                  </div>
                  <%= if course.description do %>
                    <p style="font-size:.8125rem;color:var(--text-secondary);margin-top:6px;line-height:1.5">
                      <%= String.slice(course.description, 0, 120) %><%= if String.length(course.description || "") > 120, do: "…" %>
                    </p>
                  <% end %>
                </div>
              </div>
            </a>
          <% end %>
        </div>
      </div>
    <% end %>
  <% end %>

  <%= if @can_edit && !Enum.empty?(@drafts_and_archived) do %>
    <div style="margin-top:40px">
      <div style="font-size:.75rem;font-weight:600;color:var(--text-tertiary);text-transform:uppercase;letter-spacing:.05em;margin-bottom:10px">
        Drafts &amp; Archived
      </div>
      <div class="atrium-card">
        <table style="width:100%;border-collapse:collapse">
          <tbody>
            <%= for course <- @drafts_and_archived do %>
              <tr style="border-bottom:1px solid var(--border)">
                <td style="padding:10px 16px;font-size:.875rem;color:var(--text-primary)">
                  <a href={~p"/learning/#{course.id}"} style="color:inherit;text-decoration:none"><%= course.title %></a>
                </td>
                <td style="padding:10px 16px">
                  <span style={"font-size:.75rem;font-weight:500;padding:2px 8px;border-radius:999px;#{if course.status == "draft", do: "background:var(--yellow-100,#fef9c3);color:var(--yellow-700,#a16207)", else: "background:var(--surface-raised);color:var(--text-tertiary)"}"}>
                    <%= course.status %>
                  </span>
                </td>
                <td style="padding:10px 16px;text-align:right">
                  <a href={~p"/learning/#{course.id}/edit"} class="atrium-btn atrium-btn-ghost" style="font-size:.8125rem;padding:4px 10px">Edit</a>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Replace show template**

Replace `lib/atrium_web/controllers/learning_html/show.html.heex` with:

```heex
<div class="atrium-anim" style="max-width:680px">
  <div style="margin-bottom:20px">
    <a href={~p"/learning"} style="font-size:.8125rem;color:var(--text-tertiary);text-decoration:none">
      ← Learning &amp; Development
    </a>
  </div>

  <div style="margin-bottom:8px">
    <%= if @course.category do %>
      <span style="font-size:.75rem;font-weight:600;color:var(--text-tertiary);text-transform:uppercase;letter-spacing:.05em"><%= @course.category %></span>
    <% end %>
  </div>

  <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-bottom:24px">
    <h1 class="atrium-page-title" style="margin:0"><%= @course.title %></h1>
    <%= if @can_edit do %>
      <div style="display:flex;gap:8px;flex-shrink:0">
        <a href={~p"/learning/#{@course.id}/edit"} class="atrium-btn atrium-btn-ghost">Edit</a>
        <%= if @course.status == "published" do %>
          <form method="post" action={~p"/learning/#{@course.id}/archive"} style="display:inline">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <button type="submit" class="atrium-btn atrium-btn-ghost" style="color:var(--color-error,#ef4444)">Archive</button>
          </form>
        <% end %>
      </div>
    <% end %>
  </div>

  <%= if @course.status != "published" do %>
    <div style="background:var(--yellow-50,#fefce8);border:1px solid var(--yellow-200,#fef08a);border-radius:var(--radius);padding:10px 14px;margin-bottom:20px;font-size:.875rem;color:var(--yellow-800,#854d0e)">
      This course is <strong><%= @course.status %></strong> and not visible to staff.
    </div>
  <% end %>

  <%= if @course.description do %>
    <p style="font-size:.9375rem;color:var(--text-secondary);line-height:1.6;margin-bottom:24px"><%= @course.description %></p>
  <% end %>

  <%= if !Enum.empty?(@materials) do %>
    <div class="atrium-card" style="margin-bottom:24px">
      <div style="padding:14px 16px;border-bottom:1px solid var(--border);font-size:.8125rem;font-weight:600;color:var(--text-tertiary);text-transform:uppercase;letter-spacing:.04em">
        Materials
      </div>
      <ul style="list-style:none;margin:0;padding:0">
        <%= for material <- @materials do %>
          <li style="border-bottom:1px solid var(--border);padding:12px 16px;display:flex;align-items:center;gap:10px">
            <%= if material.type == "url" do %>
              <svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.75" style="color:var(--text-tertiary);flex-shrink:0">
                <path d="M6.5 9.5A3.5 3.5 0 0 0 11.5 9l1.5-1.5a3.5 3.5 0 0 0-5-5L6.5 4M9.5 6.5A3.5 3.5 0 0 0 4.5 7L3 8.5a3.5 3.5 0 0 0 5 5l1.5-1.5" stroke-linecap="round"/>
              </svg>
              <a href={material.url} target="_blank" rel="noopener noreferrer" style="font-size:.875rem;color:var(--blue-600,#2563eb)">
                <%= material.title %>
                <svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.75" style="display:inline;margin-left:3px;vertical-align:middle">
                  <path d="M4 12L12 4M6 4h6v6" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
              </a>
            <% else %>
              <svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.75" style="color:var(--text-tertiary);flex-shrink:0">
                <path d="M10 2H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1V5l-2-3z" stroke-linejoin="round"/>
                <path d="M10 2v3h2M6 8h4M6 11h3" stroke-linecap="round"/>
              </svg>
              <a href={~p"/sections/learning/documents/#{material.document_id}"} style="font-size:.875rem;color:var(--blue-600,#2563eb)">
                <%= material.title %>
              </a>
            <% end %>
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div style="display:flex;align-items:center;gap:16px">
    <%= if @completed do %>
      <div style="display:flex;align-items:center;gap:8px;color:var(--green-700,#15803d);font-size:.875rem;font-weight:500">
        <svg viewBox="0 0 16 16" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2">
          <circle cx="8" cy="8" r="6"/>
          <path d="M5 8l2.5 2.5L11 5" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        Completed
      </div>
      <form method="post" action={~p"/learning/#{@course.id}/complete"} style="display:inline">
        <input type="hidden" name="_method" value="delete" />
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <button type="submit" class="atrium-btn atrium-btn-ghost" style="font-size:.8125rem">Mark as incomplete</button>
      </form>
    <% else %>
      <form method="post" action={~p"/learning/#{@course.id}/complete"}>
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <button type="submit" class="atrium-btn atrium-btn-primary">Mark as complete</button>
      </form>
    <% end %>

    <%= if @can_edit && @completion_count != nil do %>
      <span style="font-size:.8125rem;color:var(--text-tertiary)"><%= @completion_count %> staff completed</span>
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: Replace new template**

Replace `lib/atrium_web/controllers/learning_html/new.html.heex` with:

```heex
<div class="atrium-anim" style="max-width:560px">
  <div style="margin-bottom:20px">
    <a href={~p"/learning"} style="font-size:.8125rem;color:var(--text-tertiary);text-decoration:none">
      ← Learning &amp; Development
    </a>
  </div>

  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Learning &amp; Development</div>
    <h1 class="atrium-page-title">New Course</h1>
  </div>

  <form method="post" action={~p"/learning"}>
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

    <div class="atrium-card" style="margin-bottom:20px">
      <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:16px">

        <div>
          <label class="atrium-label" for="course_title">Title <span style="color:var(--color-error,#ef4444)">*</span></label>
          <input id="course_title" type="text" name="course[title]" class="atrium-input"
            value={Ecto.Changeset.get_field(@changeset, :title) || ""}
            required placeholder="e.g. Workplace Safety Essentials" />
          <% title_err = @changeset.action && List.first(Keyword.get_values(@changeset.errors, :title)) %>
          <%= if title_err do %><p style="font-size:.8125rem;color:var(--color-error,#ef4444);margin-top:4px"><%= elem(title_err, 0) %></p><% end %>
        </div>

        <div>
          <label class="atrium-label" for="course_category">Category</label>
          <input id="course_category" type="text" name="course[category]" class="atrium-input"
            value={Ecto.Changeset.get_field(@changeset, :category) || ""}
            placeholder="e.g. Compliance, HR, IT" />
        </div>

        <div>
          <label class="atrium-label" for="course_description">Description</label>
          <textarea id="course_description" name="course[description]" class="atrium-input" rows="4"
            style="resize:vertical" placeholder="Brief overview of what this course covers…"
          ><%= Ecto.Changeset.get_field(@changeset, :description) || "" %></textarea>
        </div>

      </div>
    </div>

    <div style="display:flex;gap:8px">
      <button type="submit" class="atrium-btn atrium-btn-primary">Create course</button>
      <a href={~p"/learning"} class="atrium-btn atrium-btn-ghost">Cancel</a>
    </div>
  </form>
</div>
```

- [ ] **Step 4: Replace edit template**

Replace `lib/atrium_web/controllers/learning_html/edit.html.heex` with:

```heex
<div class="atrium-anim" style="max-width:640px">
  <div style="margin-bottom:20px">
    <a href={~p"/learning/#{@course.id}"} style="font-size:.8125rem;color:var(--text-tertiary);text-decoration:none">
      ← Back to course
    </a>
  </div>

  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Learning &amp; Development</div>
    <h1 class="atrium-page-title">Edit Course</h1>
  </div>

  <form method="post" action={~p"/learning/#{@course.id}"}>
    <input type="hidden" name="_method" value="put" />
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

    <div class="atrium-card" style="margin-bottom:20px">
      <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:16px">

        <div>
          <label class="atrium-label" for="course_title">Title <span style="color:var(--color-error,#ef4444)">*</span></label>
          <input id="course_title" type="text" name="course[title]" class="atrium-input"
            value={Ecto.Changeset.get_field(@changeset, :title) || ""}
            required />
          <% title_err = @changeset.action && List.first(Keyword.get_values(@changeset.errors, :title)) %>
          <%= if title_err do %><p style="font-size:.8125rem;color:var(--color-error,#ef4444);margin-top:4px"><%= elem(title_err, 0) %></p><% end %>
        </div>

        <div>
          <label class="atrium-label" for="course_category">Category</label>
          <input id="course_category" type="text" name="course[category]" class="atrium-input"
            value={Ecto.Changeset.get_field(@changeset, :category) || ""}
            placeholder="e.g. Compliance, HR, IT" />
        </div>

        <div>
          <label class="atrium-label" for="course_description">Description</label>
          <textarea id="course_description" name="course[description]" class="atrium-input" rows="4"
            style="resize:vertical"
          ><%= Ecto.Changeset.get_field(@changeset, :description) || "" %></textarea>
        </div>

      </div>
    </div>

    <div class="atrium-card" style="margin-bottom:20px">
      <div style="padding:14px 16px;border-bottom:1px solid var(--border);font-size:.875rem;font-weight:600;color:var(--text-primary)">
        Materials
      </div>
      <div class="atrium-card-body">

        <%= if !Enum.empty?(@materials) do %>
          <ul style="list-style:none;margin:0 0 16px;padding:0">
            <%= for material <- @materials do %>
              <li style="display:flex;align-items:center;justify-content:space-between;gap:12px;padding:8px 0;border-bottom:1px solid var(--border)">
                <span style="font-size:.875rem;color:var(--text-primary)">
                  <%= material.title %>
                  <span style="font-size:.75rem;color:var(--text-tertiary);margin-left:6px"><%= material.type %></span>
                </span>
                <form method="post" action={~p"/learning/#{@course.id}/materials/#{material.id}/delete"} style="display:inline">
                  <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                  <button type="submit" class="atrium-btn atrium-btn-ghost" style="font-size:.75rem;padding:2px 8px;color:var(--color-error,#ef4444)">Remove</button>
                </form>
              </li>
            <% end %>
          </ul>
        <% end %>

        <div style="border:1px solid var(--border);border-radius:var(--radius);padding:14px;background:var(--surface-raised)">
          <div style="font-size:.8125rem;font-weight:600;color:var(--text-secondary);margin-bottom:10px">Add material</div>
          <div id="add-material-form">
            <div style="display:flex;gap:8px;margin-bottom:8px">
              <button type="button" onclick="setMaterialType('url')" id="btn-url"
                class="atrium-btn atrium-btn-ghost"
                style="font-size:.8125rem;padding:4px 10px">Link (URL)</button>
              <button type="button" onclick="setMaterialType('document')" id="btn-document"
                class="atrium-btn atrium-btn-ghost"
                style="font-size:.8125rem;padding:4px 10px">Document</button>
            </div>

            <div id="material-url-fields" style="display:none;flex-direction:column;gap:8px">
              <input type="text" id="mat-title" placeholder="Material title" class="atrium-input" style="font-size:.875rem" />
              <input type="url" id="mat-url" placeholder="https://..." class="atrium-input" style="font-size:.875rem" />
              <button type="button" onclick="addMaterial('url')" class="atrium-btn atrium-btn-primary" style="font-size:.8125rem;align-self:flex-start">Add</button>
            </div>

            <div id="material-document-fields" style="display:none;flex-direction:column;gap:8px">
              <input type="text" id="mat-doc-title" placeholder="Material title" class="atrium-input" style="font-size:.875rem" />
              <input type="text" id="mat-doc-id" placeholder="Document ID" class="atrium-input" style="font-size:.875rem" />
              <button type="button" onclick="addMaterial('document')" class="atrium-btn atrium-btn-primary" style="font-size:.8125rem;align-self:flex-start">Add</button>
            </div>
          </div>

          <form id="material-submit-form" method="post" action={~p"/learning/#{@course.id}/materials"} style="display:none">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <input type="hidden" id="mat-form-type" name="material[type]" />
            <input type="hidden" id="mat-form-title" name="material[title]" />
            <input type="hidden" id="mat-form-url" name="material[url]" />
            <input type="hidden" id="mat-form-document-id" name="material[document_id]" />
            <input type="hidden" name="material[position]" value="<%= length(@materials) %>" />
          </form>
        </div>

      </div>
    </div>

    <div style="display:flex;gap:8px">
      <button type="submit" class="atrium-btn atrium-btn-primary">Save changes</button>
      <%= if @course.status == "draft" do %>
        <form method="post" action={~p"/learning/#{@course.id}/publish"} style="display:inline">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button type="submit" class="atrium-btn atrium-btn-primary">Publish</button>
        </form>
      <% end %>
      <a href={~p"/learning/#{@course.id}"} class="atrium-btn atrium-btn-ghost">Cancel</a>
    </div>
  </form>
</div>

<script>
  function setMaterialType(type) {
    document.getElementById('material-url-fields').style.display = type === 'url' ? 'flex' : 'none';
    document.getElementById('material-document-fields').style.display = type === 'document' ? 'flex' : 'none';
  }

  function addMaterial(type) {
    var title = type === 'url'
      ? document.getElementById('mat-title').value
      : document.getElementById('mat-doc-title').value;
    if (!title.trim()) { alert('Please enter a title.'); return; }
    document.getElementById('mat-form-type').value = type;
    document.getElementById('mat-form-title').value = title;
    if (type === 'url') {
      var url = document.getElementById('mat-url').value;
      if (!url.match(/^https?:\/\//)) { alert('URL must start with http:// or https://'); return; }
      document.getElementById('mat-form-url').value = url;
    } else {
      document.getElementById('mat-form-document-id').value = document.getElementById('mat-doc-id').value;
    }
    document.getElementById('material-submit-form').submit();
  }
</script>
```

- [ ] **Step 5: Add material add/delete routes to router.ex**

Edit `lib/atrium_web/router.ex`. After the `delete "/learning/:id/complete"` line, add:

```elixir
      post "/learning/:id/materials",               LearningController, :add_material
      post "/learning/:id/materials/:mid/delete",   LearningController, :delete_material
```

- [ ] **Step 6: Add add_material/delete_material actions to the controller**

Edit `lib/atrium_web/controllers/learning_controller.ex`. Add these two actions after `uncomplete/2`:

```elixir
  def add_material(conn, %{"id" => id, "material" => params}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, id)

    case Learning.add_material(prefix, course.id, params) do
      {:ok, _} ->
        conn |> put_flash(:info, "Material added.") |> redirect(to: ~p"/learning/#{id}/edit")
      {:error, _changeset} ->
        conn |> put_flash(:error, "Invalid material.") |> redirect(to: ~p"/learning/#{id}/edit")
    end
  end

  def delete_material(conn, %{"id" => id, "mid" => mid}) do
    prefix = conn.assigns.tenant_prefix
    Learning.delete_material(prefix, mid)
    conn |> put_flash(:info, "Material removed.") |> redirect(to: ~p"/learning/#{id}/edit")
  end
```

Also update the `plug AtriumWeb.Plugs.Authorize` for `:edit` actions to include the new actions:

```elixir
  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "learning"}]
       when action in [:new, :create, :edit, :update, :publish, :archive, :add_material, :delete_material]
```

- [ ] **Step 7: Run full test suite**

```bash
mix test
```

Expected: all tests pass (1 pre-existing failure in ShellTest is OK).

- [ ] **Step 8: Commit**

```bash
git add lib/atrium_web/controllers/learning_html/ \
        lib/atrium_web/controllers/learning_controller.ex \
        lib/atrium_web/router.ex
git commit -m "feat: add Learning & Development templates and material management"
```

---

## Self-Review

**Spec coverage:**
- ✅ `courses` table with title/description/category/status — Task 1
- ✅ `course_materials` with type/position/title/document_id/url — Task 1
- ✅ `course_completions` with unique (course_id, user_id) — Task 1
- ✅ `Atrium.Learning` context: list, get, create, update, archive, publish, materials CRUD, complete/uncomplete, completed?, completion_count — Task 1
- ✅ `/learning` index: published courses grouped by category, completion checkmarks, P&C sees drafts/archived — Task 3
- ✅ `/learning/:id` show: materials list, complete/uncomplete button, completion count for editors — Task 3
- ✅ `/learning/new` + `/learning/:id/edit`: create/edit form with materials management — Task 3
- ✅ Draft/archived courses → 404 for non-editors — Task 2 (controller)
- ✅ URL validation (http/https) — Task 1 (changeset)
- ✅ Completion is idempotent upsert — Task 1 (context)
- ✅ Archive only from published — Task 1 (context)
- ✅ Unit tests for context — Task 1
- ✅ Controller tests — Task 2

**Placeholder scan:** None.

**Type consistency:**
- `Learning.create_course(prefix, attrs, user)` — consistent Tasks 1 and 2
- `Learning.add_material(prefix, course_id, attrs)` — consistent Tasks 1 and 3
- `Learning.complete_course(prefix, course_id, user_id)` — consistent Tasks 1 and 2
- `Learning.uncomplete_course/3` returns `:ok` — controller in Task 2 ignores return value correctly
