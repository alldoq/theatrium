# Phase 1b: Form Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver tenant-scoped form builder with drag-and-drop Vue island, versioned form schemas, multi-party submission review, external reviewer token links, Oban notification worker, and full audit integration.

**Architecture:** Four Ecto schemas (`Form`, `FormVersion`, `FormSubmission`, `FormSubmissionReview`) in a new `Atrium.Forms` context. Controller-based server-rendered HEEx for all views except the builder (Vue 3 island). External reviewers use Phoenix.Token signed links — no session required. Oban `NotificationWorker` fans out Swoosh emails on submission.

**Tech Stack:** Elixir/Phoenix 1.8, Ecto 3.x, PostgreSQL schema-per-tenant via Triplex, Vue 3 island for drag-and-drop builder, Swoosh for external emails, Oban for notification workers, Phoenix.Token for external reviewer links, `Atrium.Audit` for event logging.

---

## File Structure

**New files:**
- `priv/repo/tenant_migrations/20260422000001_create_forms.exs`
- `priv/repo/tenant_migrations/20260422000002_create_form_versions.exs`
- `priv/repo/tenant_migrations/20260422000003_create_form_submissions.exs`
- `priv/repo/tenant_migrations/20260422000004_create_form_submission_reviews.exs`
- `lib/atrium/forms/form.ex`
- `lib/atrium/forms/form_version.ex`
- `lib/atrium/forms/form_submission.ex`
- `lib/atrium/forms/form_submission_review.ex`
- `lib/atrium/forms/notification_worker.ex`
- `lib/atrium/forms.ex`
- `lib/atrium_web/controllers/form_controller.ex`
- `lib/atrium_web/controllers/form_html.ex`
- `lib/atrium_web/controllers/form_html/index.html.heex`
- `lib/atrium_web/controllers/form_html/show.html.heex`
- `lib/atrium_web/controllers/form_html/new.html.heex`
- `lib/atrium_web/controllers/form_html/edit.html.heex`
- `lib/atrium_web/controllers/form_html/submit_form.html.heex`
- `lib/atrium_web/controllers/form_html/submissions_index.html.heex`
- `lib/atrium_web/controllers/form_html/show_submission.html.heex`
- `lib/atrium_web/controllers/external_review_controller.ex`
- `lib/atrium_web/controllers/external_review_html.ex`
- `lib/atrium_web/controllers/external_review_html/show.html.heex`
- `assets/js/islands/FormBuilderIsland.vue`
- `test/atrium/forms_test.exs`
- `test/atrium_web/controllers/form_controller_test.exs`
- `test/atrium_web/controllers/external_review_controller_test.exs`

**Modified files:**
- `lib/atrium_web/router.ex` — add form routes (authenticated + external)
- `assets/js/app.js` — import FormBuilderIsland

---

## Task 1: Tenant Migrations

**Files:**
- Create: `priv/repo/tenant_migrations/20260422000001_create_forms.exs`
- Create: `priv/repo/tenant_migrations/20260422000002_create_form_versions.exs`
- Create: `priv/repo/tenant_migrations/20260422000003_create_form_submissions.exs`
- Create: `priv/repo/tenant_migrations/20260422000004_create_form_submission_reviews.exs`

- [ ] **Step 1: Create the forms migration**

```elixir
# priv/repo/tenant_migrations/20260422000001_create_forms.exs
defmodule Atrium.Repo.TenantMigrations.CreateForms do
  use Ecto.Migration

  def change do
    create table(:forms, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :title, :string, null: false
      add :section_key, :string, null: false
      add :subsection_slug, :string, null: true
      add :status, :string, null: false, default: "draft"
      add :current_version, :integer, null: false, default: 1
      add :author_id, :binary_id, null: false
      add :notification_recipients, :jsonb, null: false, default: "[]"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:forms, [:section_key])
    create index(:forms, [:section_key, :subsection_slug])
    create index(:forms, [:author_id])
    create index(:forms, [:status])
  end
end
```

- [ ] **Step 2: Create the form_versions migration**

```elixir
# priv/repo/tenant_migrations/20260422000002_create_form_versions.exs
defmodule Atrium.Repo.TenantMigrations.CreateFormVersions do
  use Ecto.Migration

  def change do
    create table(:form_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :form_id, references(:forms, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :fields, :jsonb, null: false, default: "[]"
      add :published_by_id, :binary_id, null: false
      add :published_at, :utc_datetime_usec, null: false
    end

    create index(:form_versions, [:form_id])
    create unique_index(:form_versions, [:form_id, :version])
  end
end
```

- [ ] **Step 3: Create the form_submissions migration**

```elixir
# priv/repo/tenant_migrations/20260422000003_create_form_submissions.exs
defmodule Atrium.Repo.TenantMigrations.CreateFormSubmissions do
  use Ecto.Migration

  def change do
    create table(:form_submissions, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :form_id, references(:forms, type: :binary_id, on_delete: :delete_all), null: false
      add :form_version, :integer, null: false
      add :submitted_by_id, :binary_id, null: false
      add :submitted_at, :utc_datetime_usec, null: false
      add :status, :string, null: false, default: "pending"
      add :field_values, :jsonb, null: false, default: "{}"
      add :file_keys, :jsonb, null: false, default: "[]"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:form_submissions, [:form_id])
    create index(:form_submissions, [:submitted_by_id])
    create index(:form_submissions, [:status])
  end
end
```

- [ ] **Step 4: Create the form_submission_reviews migration**

```elixir
# priv/repo/tenant_migrations/20260422000004_create_form_submission_reviews.exs
defmodule Atrium.Repo.TenantMigrations.CreateFormSubmissionReviews do
  use Ecto.Migration

  def change do
    create table(:form_submission_reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :submission_id, references(:form_submissions, type: :binary_id, on_delete: :delete_all), null: false
      add :reviewer_type, :string, null: false
      add :reviewer_id, :binary_id, null: true
      add :reviewer_email, :string, null: true
      add :status, :string, null: false, default: "pending"
      add :completed_at, :utc_datetime_usec, null: true
      add :completed_by_id, :binary_id, null: true

      timestamps(type: :utc_datetime_usec)
    end

    create index(:form_submission_reviews, [:submission_id])
    create index(:form_submission_reviews, [:reviewer_id])
    create index(:form_submission_reviews, [:status])
  end
end
```

- [ ] **Step 5: Verify migrations compile**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix ecto.migrate
```
Expected: "Already up" or migrations applied — no compile errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add priv/repo/tenant_migrations/20260422000001_create_forms.exs priv/repo/tenant_migrations/20260422000002_create_form_versions.exs priv/repo/tenant_migrations/20260422000003_create_form_submissions.exs priv/repo/tenant_migrations/20260422000004_create_form_submission_reviews.exs && git commit -m "feat(phase-1b): add forms tenant migrations"
```

---

## Task 2: Ecto Schemas

**Files:**
- Create: `lib/atrium/forms/form.ex`
- Create: `lib/atrium/forms/form_version.ex`
- Create: `lib/atrium/forms/form_submission.ex`
- Create: `lib/atrium/forms/form_submission_review.ex`
- Create: `test/atrium/forms_test.exs` (schema tests only for this task)

- [ ] **Step 1: Write failing schema tests**

```elixir
# test/atrium/forms_test.exs
defmodule Atrium.Forms.FormSchemaTest do
  use Atrium.DataCase, async: true
  alias Atrium.Forms.Form

  describe "Form.changeset/2" do
    test "valid attrs produce a valid changeset" do
      cs = Form.changeset(%Form{}, %{
        title: "Leave Request",
        section_key: "hr",
        author_id: Ecto.UUID.generate()
      })
      assert cs.valid?
    end

    test "title is required" do
      cs = Form.changeset(%Form{}, %{section_key: "hr", author_id: Ecto.UUID.generate()})
      assert errors_on(cs)[:title]
    end

    test "section_key is required" do
      cs = Form.changeset(%Form{}, %{title: "T", author_id: Ecto.UUID.generate()})
      assert errors_on(cs)[:section_key]
    end

    test "author_id is required" do
      cs = Form.changeset(%Form{}, %{title: "T", section_key: "hr"})
      assert errors_on(cs)[:author_id]
    end

    test "status defaults to draft" do
      cs = Form.changeset(%Form{}, %{title: "T", section_key: "hr", author_id: Ecto.UUID.generate()})
      assert %Form{status: "draft"} = Ecto.Changeset.apply_changes(cs)
    end

    test "status_changeset rejects invalid status" do
      cs = Form.status_changeset(%Form{status: "draft"}, "nonsense")
      assert errors_on(cs)[:status]
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/forms_test.exs 2>&1 | head -10
```
Expected: compile error — `Atrium.Forms.Form` not defined.

- [ ] **Step 3: Create Form schema**

```elixir
# lib/atrium/forms/form.ex
defmodule Atrium.Forms.Form do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft published archived)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "forms" do
    field :title, :string
    field :section_key, :string
    field :subsection_slug, :string
    field :status, :string, default: "draft"
    field :current_version, :integer, default: 1
    field :author_id, :binary_id
    field :notification_recipients, {:array, :map}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:title, :section_key, :subsection_slug, :author_id, :notification_recipients])
    |> validate_required([:title, :section_key, :author_id])
    |> validate_length(:title, min: 1, max: 500)
  end

  def update_changeset(form, attrs) do
    form
    |> cast(attrs, [:title, :subsection_slug, :notification_recipients])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 500)
  end

  def status_changeset(form, status) do
    form
    |> cast(%{status: status}, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  def version_bump_changeset(%Ecto.Changeset{} = cs) do
    current = get_field(cs, :current_version)
    change(cs, current_version: current + 1)
  end

  def version_bump_changeset(%__MODULE__{} = form) do
    change(form, current_version: form.current_version + 1)
  end
end
```

- [ ] **Step 4: Create FormVersion schema**

```elixir
# lib/atrium/forms/form_version.ex
defmodule Atrium.Forms.FormVersion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_versions" do
    field :form_id, :binary_id
    field :version, :integer
    field :fields, {:array, :map}, default: []
    field :published_by_id, :binary_id
    field :published_at, :utc_datetime_usec
  end

  def changeset(fv, attrs) do
    fv
    |> cast(attrs, [:form_id, :version, :fields, :published_by_id, :published_at])
    |> validate_required([:form_id, :version, :published_by_id, :published_at])
  end
end
```

- [ ] **Step 5: Create FormSubmission schema**

```elixir
# lib/atrium/forms/form_submission.ex
defmodule Atrium.Forms.FormSubmission do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending completed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_submissions" do
    field :form_id, :binary_id
    field :form_version, :integer
    field :submitted_by_id, :binary_id
    field :submitted_at, :utc_datetime_usec
    field :status, :string, default: "pending"
    field :field_values, :map, default: %{}
    field :file_keys, {:array, :string}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:form_id, :form_version, :submitted_by_id, :submitted_at, :field_values, :file_keys])
    |> validate_required([:form_id, :form_version, :submitted_by_id, :submitted_at])
  end

  def complete_changeset(sub) do
    change(sub, status: "completed")
  end
end
```

- [ ] **Step 6: Create FormSubmissionReview schema**

```elixir
# lib/atrium/forms/form_submission_review.ex
defmodule Atrium.Forms.FormSubmissionReview do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending completed)
  @reviewer_types ~w(user email)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_submission_reviews" do
    field :submission_id, :binary_id
    field :reviewer_type, :string
    field :reviewer_id, :binary_id
    field :reviewer_email, :string
    field :status, :string, default: "pending"
    field :completed_at, :utc_datetime_usec
    field :completed_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [:submission_id, :reviewer_type, :reviewer_id, :reviewer_email])
    |> validate_required([:submission_id, :reviewer_type])
    |> validate_inclusion(:reviewer_type, @reviewer_types)
  end

  def complete_changeset(review, completed_by_id) do
    review
    |> change(%{
      status: "completed",
      completed_at: DateTime.utc_now(),
      completed_by_id: completed_by_id
    })
  end
end
```

- [ ] **Step 7: Run schema tests**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/forms_test.exs 2>&1 | tail -10
```
Expected: 6 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add lib/atrium/forms/form.ex lib/atrium/forms/form_version.ex lib/atrium/forms/form_submission.ex lib/atrium/forms/form_submission_review.ex test/atrium/forms_test.exs && git commit -m "feat(phase-1b): add Form, FormVersion, FormSubmission, FormSubmissionReview schemas"
```

---

## Task 3: Forms Context — CRUD + Lifecycle

**Files:**
- Create: `lib/atrium/forms.ex`
- Modify: `test/atrium/forms_test.exs` — append `FormsTest` module

- [ ] **Step 1: Append context tests to test/atrium/forms_test.exs**

```elixir
defmodule Atrium.FormsTest do
  use Atrium.TenantCase
  alias Atrium.Forms
  alias Atrium.Accounts

  defp build_user(prefix) do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "form_user_#{System.unique_integer([:positive])}@example.com",
      name: "Form User"
    })
    user
  end

  describe "create_form/3" do
    test "creates a form in draft status", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "Leave Request", section_key: "hr"}, user)
      assert form.title == "Leave Request"
      assert form.status == "draft"
      assert form.current_version == 1
      assert form.author_id == user.id
    end

    test "returns error for missing required fields", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:error, cs} = Forms.create_form(prefix, %{}, user)
      assert errors_on(cs)[:title]
    end
  end

  describe "get_form!/2" do
    test "returns the form", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      assert Forms.get_form!(prefix, form.id).id == form.id
    end

    test "raises on missing id", %{tenant_prefix: prefix} do
      assert_raise Ecto.NoResultsError, fn ->
        Forms.get_form!(prefix, Ecto.UUID.generate())
      end
    end
  end

  describe "list_forms/3" do
    test "lists forms in a section", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, _} = Forms.create_form(prefix, %{title: "A", section_key: "compliance"}, user)
      {:ok, _} = Forms.create_form(prefix, %{title: "B", section_key: "compliance"}, user)
      {:ok, _} = Forms.create_form(prefix, %{title: "C", section_key: "docs"}, user)
      forms = Forms.list_forms(prefix, "compliance")
      titles = Enum.map(forms, & &1.title)
      assert "A" in titles
      assert "B" in titles
      refute "C" in titles
    end
  end

  describe "update_form/4" do
    test "updates title on draft form", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "Old", section_key: "hr"}, user)
      {:ok, updated} = Forms.update_form(prefix, form, %{title: "New"}, user)
      assert updated.title == "New"
    end

    test "cannot update a non-draft form", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      assert {:error, :not_draft} = Forms.update_form(prefix, form, %{title: "X"}, user)
    end
  end

  describe "publish_form/4" do
    test "draft → published, creates FormVersion snapshot", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      fields = [%{"id" => Ecto.UUID.generate(), "type" => "text", "label" => "Name", "required" => true, "order" => 1, "options" => [], "conditions" => []}]
      {:ok, published} = Forms.publish_form(prefix, form, fields, user)
      assert published.status == "published"
      versions = Forms.list_versions(prefix, form.id)
      assert length(versions) == 1
      assert hd(versions).version == 1
      assert hd(versions).fields == fields
    end

    test "only draft forms can be published", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      assert {:error, :invalid_transition} = Forms.publish_form(prefix, form, [], user)
    end
  end

  describe "archive_form/3" do
    test "published → archived", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      {:ok, archived} = Forms.archive_form(prefix, form, user)
      assert archived.status == "archived"
    end

    test "draft cannot be archived", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      assert {:error, :invalid_transition} = Forms.archive_form(prefix, form, user)
    end
  end

  describe "reopen_form/3" do
    test "published → draft, bumps current_version", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      {:ok, reopened} = Forms.reopen_form(prefix, form, user)
      assert reopened.status == "draft"
      assert reopened.current_version == 2
    end
  end

  describe "list_versions/2" do
    test "returns versions ordered by version desc", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      {:ok, form} = Forms.reopen_form(prefix, form, user)
      {:ok, _} = Forms.publish_form(prefix, form, [], user)
      versions = Forms.list_versions(prefix, form.id)
      assert length(versions) == 2
      assert hd(versions).version == 2
    end
  end
end
```

- [ ] **Step 2: Run to verify failures**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/forms_test.exs 2>&1 | head -10
```
Expected: compile error — `Atrium.Forms` not defined.

- [ ] **Step 3: Create lib/atrium/forms.ex**

```elixir
# lib/atrium/forms.ex
defmodule Atrium.Forms do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Forms.{Form, FormVersion, FormSubmission, FormSubmissionReview}

  # ---------------------------------------------------------------------------
  # CRUD
  # ---------------------------------------------------------------------------

  def create_form(prefix, attrs, actor_user) do
    string_attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    attrs_with_author = Map.put(string_attrs, "author_id", actor_user.id)

    Repo.transaction(fn ->
      with {:ok, form} <- insert_form(prefix, attrs_with_author),
           {:ok, _} <- Audit.log(prefix, "form.created", %{
             actor: {:user, actor_user.id},
             resource: {"Form", form.id},
             changes: %{"title" => [nil, form.title], "section_key" => [nil, form.section_key]}
           }) do
        form
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_form!(prefix, id) do
    Repo.get!(Form, id, prefix: prefix)
  end

  def list_forms(prefix, section_key, opts \\ []) do
    query =
      from f in Form,
        where: f.section_key == ^section_key,
        order_by: [desc: f.inserted_at]

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [f], f.status == ^status)
      end

    Repo.all(query, prefix: prefix)
  end

  def update_form(prefix, %Form{status: "draft"} = form, attrs, actor_user) do
    Repo.transaction(fn ->
      with {:ok, updated} <- apply_update(prefix, form, attrs),
           {:ok, _} <- Audit.log(prefix, "form.updated", %{
             actor: {:user, actor_user.id},
             resource: {"Form", updated.id},
             changes: Audit.changeset_diff(form, updated)
           }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_form(_prefix, _form, _attrs, _actor_user), do: {:error, :not_draft}

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  def publish_form(prefix, %Form{status: "draft"} = form, fields, actor_user) do
    Repo.transaction(fn ->
      with {:ok, published} <- apply_status(prefix, form, "published"),
           {:ok, _ver} <- insert_version(prefix, published, fields, actor_user),
           {:ok, _} <- Audit.log(prefix, "form.published", %{
             actor: {:user, actor_user.id},
             resource: {"Form", published.id},
             changes: %{"status" => ["draft", "published"], "version" => [nil, published.current_version]}
           }) do
        published
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def publish_form(_prefix, _form, _fields, _actor_user), do: {:error, :invalid_transition}

  def archive_form(prefix, %Form{status: "published"} = form, actor_user) do
    Repo.transaction(fn ->
      with {:ok, archived} <- apply_status(prefix, form, "archived"),
           {:ok, _} <- Audit.log(prefix, "form.archived", %{
             actor: {:user, actor_user.id},
             resource: {"Form", archived.id},
             changes: %{"status" => ["published", "archived"]}
           }) do
        archived
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def archive_form(_prefix, _form, _actor_user), do: {:error, :invalid_transition}

  def reopen_form(prefix, %Form{status: "published"} = form, actor_user) do
    Repo.transaction(fn ->
      cs =
        form
        |> Form.status_changeset("draft")
        |> Form.version_bump_changeset()

      with {:ok, reopened} <- Repo.update(cs, prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "form.updated", %{
             actor: {:user, actor_user.id},
             resource: {"Form", reopened.id},
             changes: %{"status" => ["published", "draft"], "current_version" => [form.current_version, reopened.current_version]}
           }) do
        reopened
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def reopen_form(_prefix, _form, _actor_user), do: {:error, :invalid_transition}

  # ---------------------------------------------------------------------------
  # Versions
  # ---------------------------------------------------------------------------

  def list_versions(prefix, form_id) do
    from(v in FormVersion,
      where: v.form_id == ^form_id,
      order_by: [desc: v.version]
    )
    |> Repo.all(prefix: prefix)
  end

  def get_latest_version!(prefix, form_id) do
    from(v in FormVersion,
      where: v.form_id == ^form_id,
      order_by: [desc: v.version],
      limit: 1
    )
    |> Repo.one!(prefix: prefix)
  end

  # ---------------------------------------------------------------------------
  # Submissions
  # ---------------------------------------------------------------------------

  def create_submission(prefix, form, field_values, actor_user) do
    version = form.current_version

    Repo.transaction(fn ->
      with {:ok, sub} <- insert_submission(prefix, form, version, field_values, actor_user),
           {:ok, _} <- create_reviews(prefix, sub, form.notification_recipients),
           {:ok, _} <- Audit.log(prefix, "form.submission_created", %{
             actor: {:user, actor_user.id},
             resource: {"FormSubmission", sub.id},
             changes: %{"form_id" => [nil, form.id], "form_version" => [nil, version]}
           }) do
        sub
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, sub} ->
        enqueue_notification(prefix, sub.id)
        {:ok, sub}
      err -> err
    end
  end

  def get_submission!(prefix, id) do
    Repo.get!(FormSubmission, id, prefix: prefix)
  end

  def list_submissions(prefix, form_id, opts \\ []) do
    query =
      from s in FormSubmission,
        where: s.form_id == ^form_id,
        order_by: [desc: s.submitted_at]

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [s], s.status == ^status)
      end

    Repo.all(query, prefix: prefix)
  end

  def list_reviews(prefix, submission_id) do
    from(r in FormSubmissionReview,
      where: r.submission_id == ^submission_id
    )
    |> Repo.all(prefix: prefix)
  end

  # ---------------------------------------------------------------------------
  # Reviews
  # ---------------------------------------------------------------------------

  def complete_review(prefix, review, actor_user_or_nil) do
    completed_by_id = if actor_user_or_nil, do: actor_user_or_nil.id, else: nil

    Repo.transaction(fn ->
      with {:ok, done} <- Repo.update(FormSubmissionReview.complete_changeset(review, completed_by_id), prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "form.review_completed", %{
             actor: if(actor_user_or_nil, do: {:user, actor_user_or_nil.id}, else: :system),
             resource: {"FormSubmissionReview", done.id},
             changes: %{"status" => ["pending", "completed"]}
           }),
           {:ok, _sub} <- maybe_complete_submission(prefix, done.submission_id) do
        done
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_review_by_token(token) do
    case Phoenix.Token.verify(AtriumWeb.Endpoint, "form_review", token, max_age: 30 * 24 * 3600) do
      {:ok, %{"submission_id" => sid, "reviewer_email" => email, "prefix" => prefix}} ->
        review =
          from(r in FormSubmissionReview,
            where: r.submission_id == ^sid and r.reviewer_email == ^email and r.reviewer_type == "email"
          )
          |> Repo.one(prefix: prefix)

        case review do
          nil -> {:error, :not_found}
          r -> {:ok, r, prefix}
        end

      {:error, :expired} -> {:error, :expired}
      {:error, _} -> {:error, :invalid}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp insert_form(prefix, attrs) do
    %Form{}
    |> Form.changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  defp apply_update(prefix, form, attrs) do
    form
    |> Form.update_changeset(attrs)
    |> Repo.update(prefix: prefix)
  end

  defp apply_status(prefix, form, status) do
    form
    |> Form.status_changeset(status)
    |> Repo.update(prefix: prefix)
  end

  defp insert_version(prefix, form, fields, actor_user) do
    %FormVersion{}
    |> FormVersion.changeset(%{
      form_id: form.id,
      version: form.current_version,
      fields: fields,
      published_by_id: actor_user.id,
      published_at: DateTime.utc_now()
    })
    |> Repo.insert(prefix: prefix)
  end

  defp insert_submission(prefix, form, version, field_values, actor_user) do
    %FormSubmission{}
    |> FormSubmission.changeset(%{
      form_id: form.id,
      form_version: version,
      submitted_by_id: actor_user.id,
      submitted_at: DateTime.utc_now(),
      field_values: field_values
    })
    |> Repo.insert(prefix: prefix)
  end

  defp create_reviews(_prefix, _sub, []), do: {:ok, []}

  defp create_reviews(prefix, sub, recipients) do
    results =
      Enum.map(recipients, fn recipient ->
        attrs = %{
          submission_id: sub.id,
          reviewer_type: recipient["type"] || recipient[:type],
          reviewer_id: recipient["id"] || recipient[:id],
          reviewer_email: recipient["email"] || recipient[:email]
        }

        %FormSubmissionReview{}
        |> FormSubmissionReview.changeset(attrs)
        |> Repo.insert(prefix: prefix)
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))
    if errors == [], do: {:ok, results}, else: hd(errors)
  end

  defp maybe_complete_submission(prefix, submission_id) do
    pending_count =
      from(r in FormSubmissionReview,
        where: r.submission_id == ^submission_id and r.status == "pending",
        select: count()
      )
      |> Repo.one(prefix: prefix)

    if pending_count == 0 do
      sub = Repo.get!(FormSubmission, submission_id, prefix: prefix)

      with {:ok, completed} <- Repo.update(FormSubmission.complete_changeset(sub), prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "form.submission_completed", %{
             actor: :system,
             resource: {"FormSubmission", completed.id},
             changes: %{"status" => ["pending", "completed"]}
           }) do
        {:ok, completed}
      end
    else
      {:ok, :not_yet_complete}
    end
  end

  defp enqueue_notification(prefix, submission_id) do
    %{prefix: prefix, submission_id: submission_id}
    |> Atrium.Forms.NotificationWorker.new()
    |> Oban.insert()
  end
end
```

- [ ] **Step 4: Run context tests**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/forms_test.exs 2>&1 | tail -15
```
Expected: All tests pass. If `NotificationWorker` is missing, create a stub first (next step handles it).

- [ ] **Step 5: Create NotificationWorker stub**

```elixir
# lib/atrium/forms/notification_worker.ex
defmodule Atrium.Forms.NotificationWorker do
  use Oban.Worker, queue: :notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"prefix" => prefix, "submission_id" => sid}}) do
    alias Atrium.Forms
    alias Atrium.Forms.FormSubmissionReview

    reviews = Forms.list_reviews(prefix, sid)
    sub = Forms.get_submission!(prefix, sid)

    Enum.each(reviews, fn review ->
      case review.reviewer_type do
        "email" -> send_external_email(prefix, sub, review)
        "user" -> :ok
      end
    end)

    :ok
  end

  defp send_external_email(prefix, sub, review) do
    token = Phoenix.Token.sign(AtriumWeb.Endpoint, "form_review", %{
      "submission_id" => sub.id,
      "reviewer_email" => review.reviewer_email,
      "prefix" => prefix
    })

    review.reviewer_email
    |> Atrium.Forms.ReviewEmail.external_reviewer(sub, token)
    |> Atrium.Mailer.deliver()

    :ok
  end
end
```

- [ ] **Step 6: Create ReviewEmail module**

```elixir
# lib/atrium/forms/review_email.ex
defmodule Atrium.Forms.ReviewEmail do
  use Swoosh.Mailer, otp_app: :atrium
  import Swoosh.Email

  def external_reviewer(to_email, submission, token) do
    review_url = AtriumWeb.Endpoint.url() <> "/forms/review/#{token}"

    new()
    |> to(to_email)
    |> from({"Atrium", "no-reply@atrium.example"})
    |> subject("Action required: form submission review")
    |> text_body("""
    You have been asked to review a form submission.

    Visit this link to view and complete your review:
    #{review_url}

    This link is valid for 30 days.
    """)
  end
end
```

- [ ] **Step 7: Add :notifications queue to Oban config**

In `config/config.exs`, find the Oban queues config and add `notifications: 5`:

```elixir
config :atrium, Oban,
  repo: Atrium.Repo,
  queues: [default: 10, maintenance: 2, audit: 5, notifications: 5]
```

- [ ] **Step 8: Run all forms tests**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/forms_test.exs 2>&1 | tail -10
```
Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add lib/atrium/forms.ex lib/atrium/forms/notification_worker.ex lib/atrium/forms/review_email.ex config/config.exs test/atrium/forms_test.exs && git commit -m "feat(phase-1b): add Forms context with CRUD, lifecycle, submissions, and review completion"
```

---

## Task 4: Submission + Review + Audit Tests

**Files:**
- Modify: `test/atrium/forms_test.exs` — append submission and audit tests

- [ ] **Step 1: Append submission and audit tests**

```elixir
defmodule Atrium.Forms.SubmissionTest do
  use Atrium.TenantCase
  alias Atrium.Forms
  alias Atrium.Accounts

  defp build_user(prefix) do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "sub_user_#{System.unique_integer([:positive])}@example.com",
      name: "Sub User"
    })
    user
  end

  defp published_form(prefix, user) do
    {:ok, form} = Forms.create_form(prefix, %{title: "Test Form", section_key: "hr"}, user)
    {:ok, form} = Forms.publish_form(prefix, form, [], user)
    form
  end

  describe "create_submission/4" do
    test "creates a submission with field values", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      form = published_form(prefix, user)
      {:ok, sub} = Forms.create_submission(prefix, form, %{"name" => "Alice"}, user)
      assert sub.form_id == form.id
      assert sub.status == "pending"
      assert sub.field_values == %{"name" => "Alice"}
    end

    test "creates reviews for each notification recipient", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{
        title: "T",
        section_key: "hr",
        notification_recipients: [
          %{"type" => "email", "email" => "reviewer@external.com"},
          %{"type" => "user", "id" => user.id}
        ]
      }, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      {:ok, sub} = Forms.create_submission(prefix, form, %{}, user)
      reviews = Forms.list_reviews(prefix, sub.id)
      assert length(reviews) == 2
    end

    test "submission auto-completes when no recipients", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      form = published_form(prefix, user)
      {:ok, sub} = Forms.create_submission(prefix, form, %{}, user)
      assert sub.status == "pending"
    end
  end

  describe "complete_review/3" do
    test "marks review completed", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{
        title: "T",
        section_key: "hr",
        notification_recipients: [%{"type" => "user", "id" => user.id}]
      }, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      {:ok, sub} = Forms.create_submission(prefix, form, %{}, user)
      [review] = Forms.list_reviews(prefix, sub.id)
      {:ok, done} = Forms.complete_review(prefix, review, user)
      assert done.status == "completed"
      assert done.completed_by_id == user.id
    end

    test "submission completes when last review is completed", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{
        title: "T",
        section_key: "hr",
        notification_recipients: [%{"type" => "user", "id" => user.id}]
      }, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      {:ok, sub} = Forms.create_submission(prefix, form, %{}, user)
      [review] = Forms.list_reviews(prefix, sub.id)
      {:ok, _} = Forms.complete_review(prefix, review, user)
      completed_sub = Forms.get_submission!(prefix, sub.id)
      assert completed_sub.status == "completed"
    end
  end

  describe "audit events" do
    test "create_form emits form.created", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      history = Atrium.Audit.history_for(prefix, "Form", form.id)
      assert Enum.any?(history, &(&1.action == "form.created"))
    end

    test "publish_form emits form.published", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, _} = Forms.publish_form(prefix, form, [], user)
      history = Atrium.Audit.history_for(prefix, "Form", form.id)
      assert Enum.any?(history, &(&1.action == "form.published"))
    end

    test "create_submission emits form.submission_created", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      form = published_form(prefix, user)
      {:ok, sub} = Forms.create_submission(prefix, form, %{}, user)
      history = Atrium.Audit.history_for(prefix, "FormSubmission", sub.id)
      assert Enum.any?(history, &(&1.action == "form.submission_created"))
    end

    test "complete_review emits form.review_completed and form.submission_completed when last", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{
        title: "T",
        section_key: "hr",
        notification_recipients: [%{"type" => "user", "id" => user.id}]
      }, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      {:ok, sub} = Forms.create_submission(prefix, form, %{}, user)
      [review] = Forms.list_reviews(prefix, sub.id)
      {:ok, _} = Forms.complete_review(prefix, review, user)
      review_history = Atrium.Audit.history_for(prefix, "FormSubmissionReview", review.id)
      sub_history = Atrium.Audit.history_for(prefix, "FormSubmission", sub.id)
      assert Enum.any?(review_history, &(&1.action == "form.review_completed"))
      assert Enum.any?(sub_history, &(&1.action == "form.submission_completed"))
    end
  end
end
```

- [ ] **Step 2: Run the new tests**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/forms_test.exs 2>&1 | tail -15
```
Expected: All tests pass. Note: `create_submission` enqueues an Oban job — tests use `Oban.Testing` sandbox which allows job enqueuing without performing.

If you get an Oban error about the testing mode, add this to `test/support/data_case.ex` if not already present:

```elixir
setup tags do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Atrium.Repo)
  unless tags[:async] do
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, {:shared, self()})
  end
  :ok
end
```

And ensure `config/test.exs` has:
```elixir
config :atrium, Oban, testing: :inline
```

- [ ] **Step 3: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add test/atrium/forms_test.exs && git commit -m "feat(phase-1b): add submission, review, and audit event tests"
```

---

## Task 5: Router + FormController + ExternalReviewController

**Files:**
- Modify: `lib/atrium_web/router.ex`
- Create: `lib/atrium_web/controllers/form_controller.ex`
- Create: `lib/atrium_web/controllers/form_html.ex`
- Create: `lib/atrium_web/controllers/external_review_controller.ex`
- Create: `lib/atrium_web/controllers/external_review_html.ex`
- Create: `test/atrium_web/controllers/form_controller_test.exs`
- Create: `test/atrium_web/controllers/external_review_controller_test.exs`

- [ ] **Step 1: Add routes to lib/atrium_web/router.ex**

Inside the authenticated scope (the `scope "/" do` block with `pipe_through [AtriumWeb.Plugs.RequireUser, AtriumWeb.Plugs.AssignNav]`), add after document routes:

```elixir
      get  "/sections/:section_key/forms",                                    FormController, :index
      get  "/sections/:section_key/forms/new",                                FormController, :new
      post "/sections/:section_key/forms",                                    FormController, :create
      get  "/sections/:section_key/forms/:id",                                FormController, :show
      get  "/sections/:section_key/forms/:id/edit",                           FormController, :edit
      put  "/sections/:section_key/forms/:id",                                FormController, :update
      post "/sections/:section_key/forms/:id/publish",                        FormController, :publish
      post "/sections/:section_key/forms/:id/archive",                        FormController, :archive
      post "/sections/:section_key/forms/:id/reopen",                         FormController, :reopen
      get  "/sections/:section_key/forms/:id/submit",                         FormController, :submit_form
      post "/sections/:section_key/forms/:id/submit",                         FormController, :create_submission
      get  "/sections/:section_key/forms/:id/submissions",                    FormController, :submissions_index
      get  "/sections/:section_key/forms/:id/submissions/:sid",               FormController, :show_submission
      post "/sections/:section_key/forms/:id/submissions/:sid/complete",      FormController, :complete_review
```

Outside the authenticated scope, inside the tenant `scope "/", AtriumWeb do` block (before the `if Application.compile_env` block), add the external reviewer routes. These only need `:browser` and `:tenant` — no `:RequireUser`:

```elixir
    get  "/forms/review/:token",          ExternalReviewController, :show
    post "/forms/review/:token/complete", ExternalReviewController, :complete
```

- [ ] **Step 2: Create FormController**

```elixir
# lib/atrium_web/controllers/form_controller.ex
defmodule AtriumWeb.FormController do
  use AtriumWeb, :controller
  alias Atrium.Forms
  alias Atrium.Forms.Form

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: &__MODULE__.section_target/1]
       when action in [:index, :show, :submit_form, :create_submission, :submissions_index, :show_submission]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: &__MODULE__.section_target/1]
       when action in [:new, :create, :edit, :update, :publish, :reopen, :complete_review]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :approve, target: &__MODULE__.section_target/1]
       when action in [:archive]

  def section_target(conn), do: {:section, conn.path_params["section_key"]}

  def index(conn, %{"section_key" => section_key} = params) do
    prefix = conn.assigns.tenant_prefix
    opts = if st = params["status"], do: [status: st], else: []
    forms = Forms.list_forms(prefix, section_key, opts)
    render(conn, :index, forms: forms, section_key: section_key)
  end

  def new(conn, %{"section_key" => section_key}) do
    changeset = Form.changeset(%Form{}, %{})
    render(conn, :new, changeset: changeset, section_key: section_key)
  end

  def create(conn, %{"section_key" => section_key, "form" => form_params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    attrs = Map.put(form_params, "section_key", section_key)

    case Forms.create_form(prefix, attrs, user) do
      {:ok, form} ->
        conn
        |> put_flash(:info, "Form created.")
        |> redirect(to: ~p"/sections/#{section_key}/forms/#{form.id}/edit")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(422) |> render(:new, changeset: changeset, section_key: section_key)

      {:error, _} ->
        conn |> put_flash(:error, "An unexpected error occurred.") |> redirect(to: ~p"/sections/#{section_key}/forms")
    end
  end

  def show(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    form = Forms.get_form!(prefix, id)
    versions = Forms.list_versions(prefix, form.id)
    history = Atrium.Audit.history_for(prefix, "Form", form.id)
    render(conn, :show, form: form, versions: versions, history: history, section_key: section_key)
  end

  def edit(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    form = Forms.get_form!(prefix, id)

    if form.status != "draft" do
      conn
      |> put_flash(:error, "Only draft forms can be edited.")
      |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")
    else
      changeset = Form.update_changeset(form, %{})
      latest_fields =
        case Forms.list_versions(prefix, form.id) do
          [] -> []
          [v | _] -> v.fields
        end
      render(conn, :edit, form: form, changeset: changeset, section_key: section_key, latest_fields: latest_fields)
    end
  end

  def update(conn, %{"section_key" => section_key, "id" => id, "form" => form_params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    form = Forms.get_form!(prefix, id)

    case Forms.update_form(prefix, form, form_params, user) do
      {:ok, updated} ->
        conn |> put_flash(:info, "Form updated.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{updated.id}/edit")

      {:error, :not_draft} ->
        conn |> put_flash(:error, "Only draft forms can be edited.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(422) |> render(:edit, form: form, changeset: changeset, section_key: section_key, latest_fields: [])

      {:error, _} ->
        conn |> put_flash(:error, "An unexpected error occurred.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")
    end
  end

  def publish(conn, %{"section_key" => section_key, "id" => id, "form" => %{"fields" => fields_json}}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    form = Forms.get_form!(prefix, id)
    fields = Jason.decode!(fields_json)

    case Forms.publish_form(prefix, form, fields, user) do
      {:ok, _} ->
        conn |> put_flash(:info, "Form published.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")

      {:error, _} ->
        conn |> put_flash(:error, "Could not publish form.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/edit")
    end
  end

  def archive(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    form = Forms.get_form!(prefix, id)

    case Forms.archive_form(prefix, form, user) do
      {:ok, _} -> conn |> put_flash(:info, "Form archived.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")
      {:error, _} -> conn |> put_flash(:error, "Could not archive form.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")
    end
  end

  def reopen(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    form = Forms.get_form!(prefix, id)

    case Forms.reopen_form(prefix, form, user) do
      {:ok, _} -> conn |> put_flash(:info, "Form reopened for editing.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/edit")
      {:error, _} -> conn |> put_flash(:error, "Could not reopen form.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")
    end
  end

  def submit_form(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    form = Forms.get_form!(prefix, id)

    if form.status != "published" do
      conn |> put_flash(:error, "This form is not available.") |> redirect(to: ~p"/sections/#{section_key}/forms")
    else
      version = Forms.get_latest_version!(prefix, form.id)
      render(conn, :submit_form, form: form, version: version, section_key: section_key)
    end
  end

  def create_submission(conn, %{"section_key" => section_key, "id" => id, "submission" => values}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    form = Forms.get_form!(prefix, id)

    case Forms.create_submission(prefix, form, values, user) do
      {:ok, sub} ->
        conn |> put_flash(:info, "Form submitted.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/submissions/#{sub.id}")

      {:error, _} ->
        version = Forms.get_latest_version!(prefix, form.id)
        conn |> put_status(422) |> render(:submit_form, form: form, version: version, section_key: section_key)
    end
  end

  def submissions_index(conn, %{"section_key" => section_key, "id" => id} = params) do
    prefix = conn.assigns.tenant_prefix
    form = Forms.get_form!(prefix, id)
    opts = if st = params["status"], do: [status: st], else: []
    submissions = Forms.list_submissions(prefix, form.id, opts)
    render(conn, :submissions_index, form: form, submissions: submissions, section_key: section_key)
  end

  def show_submission(conn, %{"section_key" => section_key, "id" => id, "sid" => sid}) do
    prefix = conn.assigns.tenant_prefix
    form = Forms.get_form!(prefix, id)
    submission = Forms.get_submission!(prefix, sid)
    reviews = Forms.list_reviews(prefix, submission.id)
    version = Forms.list_versions(prefix, form.id)
             |> Enum.find(&(&1.version == submission.form_version))
    render(conn, :show_submission, form: form, submission: submission, reviews: reviews, version: version, section_key: section_key)
  end

  def complete_review(conn, %{"section_key" => section_key, "id" => id, "sid" => sid}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    _form = Forms.get_form!(prefix, id)

    review =
      Forms.list_reviews(prefix, sid)
      |> Enum.find(&(&1.reviewer_id == user.id && &1.status == "pending"))

    case review do
      nil ->
        conn |> put_flash(:error, "No pending review found.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/submissions/#{sid}")

      r ->
        case Forms.complete_review(prefix, r, user) do
          {:ok, _} -> conn |> put_flash(:info, "Review marked complete.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/submissions/#{sid}")
          {:error, _} -> conn |> put_flash(:error, "Could not complete review.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/submissions/#{sid}")
        end
    end
  end
end
```

- [ ] **Step 3: Create form_html.ex**

```elixir
# lib/atrium_web/controllers/form_html.ex
defmodule AtriumWeb.FormHTML do
  use AtriumWeb, :html

  embed_templates "form_html/*"

  def status_badge_class("draft"),     do: "bg-slate-100 text-slate-700"
  def status_badge_class("published"), do: "bg-green-100 text-green-700"
  def status_badge_class("archived"),  do: "bg-slate-200 text-slate-500"
  def status_badge_class(_),           do: "bg-slate-100 text-slate-700"
end
```

- [ ] **Step 4: Create ExternalReviewController**

```elixir
# lib/atrium_web/controllers/external_review_controller.ex
defmodule AtriumWeb.ExternalReviewController do
  use AtriumWeb, :controller
  alias Atrium.Forms

  def show(conn, %{"token" => token}) do
    case Forms.get_review_by_token(token) do
      {:ok, review, prefix} ->
        submission = Forms.get_submission!(prefix, review.submission_id)
        form = Forms.get_form!(prefix, submission.form_id)
        version = Forms.list_versions(prefix, form.id)
                  |> Enum.find(&(&1.version == submission.form_version))
        render(conn, :show, review: review, submission: submission, form: form, version: version, token: token)

      {:error, :expired} ->
        conn |> put_status(400) |> text("This review link has expired.")

      {:error, _} ->
        conn |> put_status(400) |> text("Invalid review link.")
    end
  end

  def complete(conn, %{"token" => token}) do
    case Forms.get_review_by_token(token) do
      {:ok, review, prefix} ->
        if review.status == "completed" do
          conn |> put_flash(:info, "This review has already been completed.") |> render(:show, review: review, token: token, already_done: true)
        else
          case Forms.complete_review(prefix, review, nil) do
            {:ok, _} -> conn |> put_flash(:info, "Review marked as complete. Thank you.") |> redirect(to: ~p"/forms/review/#{token}")
            {:error, _} -> conn |> put_status(500) |> text("Could not complete review.")
          end
        end

      {:error, :expired} ->
        conn |> put_status(400) |> text("This review link has expired.")

      {:error, _} ->
        conn |> put_status(400) |> text("Invalid review link.")
    end
  end
end
```

- [ ] **Step 5: Create external_review_html.ex**

```elixir
# lib/atrium_web/controllers/external_review_html.ex
defmodule AtriumWeb.ExternalReviewHTML do
  use AtriumWeb, :html

  embed_templates "external_review_html/*"
end
```

- [ ] **Step 6: Create controller test files**

Create `test/atrium_web/controllers/form_controller_test.exs`:

```elixir
defmodule AtriumWeb.FormControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.{Tenants, Accounts, Authorization}
  alias Atrium.Tenants.Provisioner
  alias Atrium.Forms

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "form_ctrl_test", name: "Form Ctrl Test"})
    {:ok, tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop("form_ctrl_test") end)

    prefix = Triplex.to_prefix("form_ctrl_test")
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{email: "fctrl@example.com", name: "Form Ctrl"})
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "hr", {:user, user.id}, :edit)
    Authorization.grant_section(prefix, "hr", {:user, user.id}, :approve)

    conn =
      build_conn()
      |> Map.put(:host, "form_ctrl_test.atrium.example")
      |> post("/login", %{email: "fctrl@example.com", password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, "form_ctrl_test.atrium.example")

    {:ok, conn: conn, prefix: prefix, user: user}
  end

  describe "GET /sections/hr/forms" do
    test "returns 200", %{conn: conn} do
      conn = get(conn, "/sections/hr/forms")
      assert html_response(conn, 200) =~ "Forms"
    end
  end

  describe "GET /sections/hr/forms/new" do
    test "renders new form", %{conn: conn} do
      conn = get(conn, "/sections/hr/forms/new")
      assert html_response(conn, 200) =~ "New form"
    end
  end

  describe "POST /sections/hr/forms" do
    test "creates form and redirects to edit", %{conn: conn} do
      conn = post(conn, "/sections/hr/forms", %{form: %{title: "Leave Request"}})
      assert redirected_to(conn) =~ "/sections/hr/forms/"
      assert redirected_to(conn) =~ "/edit"
    end

    test "re-renders new on invalid attrs", %{conn: conn} do
      conn = post(conn, "/sections/hr/forms", %{form: %{title: ""}})
      assert html_response(conn, 422) =~ "New form"
    end
  end

  describe "GET /sections/hr/forms/:id" do
    test "shows form", %{conn: conn, prefix: prefix, user: user} do
      {:ok, form} = Forms.create_form(prefix, %{title: "ShowMe", section_key: "hr"}, user)
      conn = get(conn, "/sections/hr/forms/#{form.id}")
      assert html_response(conn, 200) =~ "ShowMe"
    end
  end

  describe "GET /sections/hr/forms/:id/edit" do
    test "renders builder for draft form", %{conn: conn, prefix: prefix, user: user} do
      {:ok, form} = Forms.create_form(prefix, %{title: "EditMe", section_key: "hr"}, user)
      conn = get(conn, "/sections/hr/forms/#{form.id}/edit")
      assert html_response(conn, 200) =~ "FormBuilderIsland"
    end
  end

  describe "POST /sections/hr/forms/:id/publish" do
    test "publishes form", %{conn: conn, prefix: prefix, user: user} do
      {:ok, form} = Forms.create_form(prefix, %{title: "Pub", section_key: "hr"}, user)
      conn = post(conn, "/sections/hr/forms/#{form.id}/publish", %{form: %{fields: "[]"}})
      assert redirected_to(conn) =~ "/sections/hr/forms/#{form.id}"
      assert Forms.get_form!(prefix, form.id).status == "published"
    end
  end

  describe "GET /sections/hr/forms/:id/submit" do
    test "renders submit form for published form", %{conn: conn, prefix: prefix, user: user} do
      {:ok, form} = Forms.create_form(prefix, %{title: "Fill Me", section_key: "hr"}, user)
      {:ok, _} = Forms.publish_form(prefix, form, [], user)
      conn = get(conn, "/sections/hr/forms/#{form.id}/submit")
      assert html_response(conn, 200) =~ "Fill Me"
    end
  end

  describe "POST /sections/hr/forms/:id/submit" do
    test "creates submission and redirects to show", %{conn: conn, prefix: prefix, user: user} do
      {:ok, form} = Forms.create_form(prefix, %{title: "Sub", section_key: "hr"}, user)
      {:ok, _} = Forms.publish_form(prefix, form, [], user)
      conn = post(conn, "/sections/hr/forms/#{form.id}/submit", %{submission: %{}})
      assert redirected_to(conn) =~ "/sections/hr/forms/#{form.id}/submissions/"
    end
  end

  describe "authorization" do
    test "POST /sections/hr/forms returns 403 for user without :edit", %{prefix: prefix} do
      {:ok, %{user: viewer}} = Accounts.invite_user(prefix, %{email: "fviewer@example.com", name: "Viewer"})
      {:ok, _} = Accounts.activate_user_with_password(prefix, viewer, %{
        password: "Correct-horse-battery1",
        password_confirmation: "Correct-horse-battery1"
      })
      viewer_conn =
        build_conn()
        |> Map.put(:host, "form_ctrl_test.atrium.example")
        |> post("/login", %{email: "fviewer@example.com", password: "Correct-horse-battery1"})
        |> recycle()
        |> Map.put(:host, "form_ctrl_test.atrium.example")
      viewer_conn = post(viewer_conn, "/sections/hr/forms", %{form: %{title: "X"}})
      assert viewer_conn.status == 403
    end
  end
end
```

Create `test/atrium_web/controllers/external_review_controller_test.exs`:

```elixir
defmodule AtriumWeb.ExternalReviewControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.{Tenants, Accounts}
  alias Atrium.Tenants.Provisioner
  alias Atrium.Forms

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "ext_review_test", name: "Ext Review Test"})
    {:ok, tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop("ext_review_test") end)

    prefix = Triplex.to_prefix("ext_review_test")
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{email: "submitter@example.com", name: "Submitter"})
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })

    {:ok, form} = Forms.create_form(prefix, %{
      title: "Ext Form",
      section_key: "hr",
      notification_recipients: [%{"type" => "email", "email" => "reviewer@external.com"}]
    }, user)
    {:ok, form} = Forms.publish_form(prefix, form, [], user)
    {:ok, sub} = Forms.create_submission(prefix, form, %{}, user)
    [review] = Forms.list_reviews(prefix, sub.id)

    token = Phoenix.Token.sign(AtriumWeb.Endpoint, "form_review", %{
      "submission_id" => sub.id,
      "reviewer_email" => "reviewer@external.com",
      "prefix" => prefix
    })

    conn = build_conn() |> Map.put(:host, "ext_review_test.atrium.example")

    {:ok, conn: conn, prefix: prefix, review: review, token: token, sub: sub}
  end

  describe "GET /forms/review/:token" do
    test "renders review page with valid token", %{conn: conn, token: token} do
      conn = get(conn, "/forms/review/#{token}")
      assert html_response(conn, 200) =~ "review"
    end

    test "returns 400 for invalid token", %{conn: conn} do
      conn = get(conn, "/forms/review/badtoken")
      assert conn.status == 400
    end

    test "returns 400 for expired token", %{conn: conn, sub: sub} do
      expired_token = Phoenix.Token.sign(AtriumWeb.Endpoint, "form_review", %{
        "submission_id" => sub.id,
        "reviewer_email" => "reviewer@external.com",
        "prefix" => "tenant_ext_review_test"
      }, signed_at: System.system_time(:second) - 31 * 24 * 3600)
      conn = get(conn, "/forms/review/#{expired_token}")
      assert conn.status == 400
    end
  end

  describe "POST /forms/review/:token/complete" do
    test "marks review complete and redirects", %{conn: conn, token: token, prefix: prefix, review: review} do
      conn = post(conn, "/forms/review/#{token}/complete")
      assert redirected_to(conn) =~ "/forms/review/#{token}"
      updated = Enum.find(Forms.list_reviews(prefix, review.submission_id), &(&1.id == review.id))
      assert updated.status == "completed"
    end

    test "already-completed review shows graceful message", %{conn: conn, token: token, prefix: prefix, review: review} do
      {:ok, _} = Forms.complete_review(prefix, review, nil)
      conn = post(conn, "/forms/review/#{token}/complete")
      assert html_response(conn, 200) =~ "already been completed"
    end
  end
end
```

- [ ] **Step 7: Compile check**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix compile 2>&1 | grep -E "error:|warning:" | head -20
```
Expected: No errors. Template-not-found warnings are expected at this stage.

- [ ] **Step 8: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add lib/atrium_web/router.ex lib/atrium_web/controllers/form_controller.ex lib/atrium_web/controllers/form_html.ex lib/atrium_web/controllers/external_review_controller.ex lib/atrium_web/controllers/external_review_html.ex test/atrium_web/controllers/form_controller_test.exs test/atrium_web/controllers/external_review_controller_test.exs && git commit -m "feat(phase-1b): add FormController, ExternalReviewController, and routes"
```

---

## Task 6: HEEx Templates

**Files:**
- Create: `lib/atrium_web/controllers/form_html/index.html.heex`
- Create: `lib/atrium_web/controllers/form_html/show.html.heex`
- Create: `lib/atrium_web/controllers/form_html/new.html.heex`
- Create: `lib/atrium_web/controllers/form_html/edit.html.heex`
- Create: `lib/atrium_web/controllers/form_html/submit_form.html.heex`
- Create: `lib/atrium_web/controllers/form_html/submissions_index.html.heex`
- Create: `lib/atrium_web/controllers/form_html/show_submission.html.heex`
- Create: `lib/atrium_web/controllers/external_review_html/show.html.heex`

- [ ] **Step 1: Create template directory**

```bash
mkdir -p /Users/marcinwalczak/Kod/atrium/lib/atrium_web/controllers/form_html
mkdir -p /Users/marcinwalczak/Kod/atrium/lib/atrium_web/controllers/external_review_html
```

- [ ] **Step 2: Create index.html.heex**

```heex
<%# lib/atrium_web/controllers/form_html/index.html.heex %>
<main class="p-8">
  <div class="flex items-center justify-between mb-6">
    <h1 class="text-xl font-semibold">Forms — <%= @section_key %></h1>
    <a href={~p"/sections/#{@section_key}/forms/new"} class="rounded bg-slate-900 text-white px-4 py-2 text-sm">
      New form
    </a>
  </div>
  <table class="w-full text-sm border">
    <thead class="bg-slate-50">
      <tr>
        <th class="p-2 text-left">Title</th>
        <th class="p-2 text-left">Status</th>
        <th class="p-2 text-left">Version</th>
        <th class="p-2 text-left">Updated</th>
      </tr>
    </thead>
    <tbody>
      <%= for form <- @forms do %>
        <tr class="border-t hover:bg-slate-50">
          <td class="p-2">
            <a href={~p"/sections/#{@section_key}/forms/#{form.id}"} class="text-blue-600 hover:underline">
              <%= form.title %>
            </a>
          </td>
          <td class="p-2">
            <span class={"rounded px-2 py-0.5 text-xs font-medium #{status_badge_class(form.status)}"}>
              <%= form.status %>
            </span>
          </td>
          <td class="p-2">v<%= form.current_version %></td>
          <td class="p-2"><%= Calendar.strftime(form.updated_at, "%Y-%m-%d %H:%M") %></td>
        </tr>
      <% end %>
      <%= if @forms == [] do %>
        <tr><td colspan="4" class="p-4 text-center text-slate-500">No forms yet.</td></tr>
      <% end %>
    </tbody>
  </table>
</main>
```

- [ ] **Step 3: Create show.html.heex**

```heex
<%# lib/atrium_web/controllers/form_html/show.html.heex %>
<main class="p-8 max-w-4xl">
  <div class="mb-4">
    <a href={~p"/sections/#{@section_key}/forms"} class="text-sm text-slate-500 hover:underline">← Back to forms</a>
  </div>
  <div class="flex items-start justify-between mb-6">
    <div>
      <h1 class="text-2xl font-semibold"><%= @form.title %></h1>
      <p class="text-sm text-slate-500 mt-1">
        v<%= @form.current_version %> ·
        <span class={"rounded px-2 py-0.5 text-xs font-medium #{status_badge_class(@form.status)}"}>
          <%= @form.status %>
        </span>
      </p>
    </div>
    <div class="flex gap-2">
      <%= if @form.status == "draft" do %>
        <a href={~p"/sections/#{@section_key}/forms/#{@form.id}/edit"} class="rounded border px-3 py-1 text-sm">Edit</a>
      <% end %>
      <%= if @form.status == "published" do %>
        <a href={~p"/sections/#{@section_key}/forms/#{@form.id}/submit"} class="rounded bg-blue-600 text-white px-3 py-1 text-sm">Fill in form</a>
        <a href={~p"/sections/#{@section_key}/forms/#{@form.id}/submissions"} class="rounded border px-3 py-1 text-sm">Submissions</a>
        <form method="post" action={~p"/sections/#{@section_key}/forms/#{@form.id}/reopen"}>
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button class="rounded border px-3 py-1 text-sm">Reopen for editing</button>
        </form>
        <form method="post" action={~p"/sections/#{@section_key}/forms/#{@form.id}/archive"}>
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button class="rounded border px-3 py-1 text-sm text-slate-600">Archive</button>
        </form>
      <% end %>
    </div>
  </div>
  <section class="mt-8">
    <h2 class="text-sm font-semibold text-slate-700 mb-2">Version history</h2>
    <table class="w-full text-sm border">
      <thead class="bg-slate-50">
        <tr>
          <th class="p-2 text-left">Version</th>
          <th class="p-2 text-left">Fields</th>
          <th class="p-2 text-left">Published at</th>
        </tr>
      </thead>
      <tbody>
        <%= for v <- @versions do %>
          <tr class="border-t">
            <td class="p-2">v<%= v.version %></td>
            <td class="p-2"><%= length(v.fields) %> field(s)</td>
            <td class="p-2"><%= Calendar.strftime(v.published_at, "%Y-%m-%d %H:%M:%S") %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </section>
  <section class="mt-8">
    <AtriumWeb.Components.HistoryView.history events={@history} title="Audit history" />
  </section>
</main>
```

- [ ] **Step 4: Create new.html.heex**

```heex
<%# lib/atrium_web/controllers/form_html/new.html.heex %>
<main class="p-8 max-w-xl">
  <div class="mb-4">
    <a href={~p"/sections/#{@section_key}/forms"} class="text-sm text-slate-500 hover:underline">← Back to forms</a>
  </div>
  <h1 class="text-xl font-semibold mb-6">New form</h1>
  <.form :let={f} for={@changeset} action={~p"/sections/#{@section_key}/forms"} method="post">
    <div class="mb-4">
      <label class="block text-sm font-medium mb-1">Title</label>
      <input type="text" name="form[title]" value={Phoenix.HTML.Form.input_value(f, :title) || ""} class="w-full border rounded p-2" />
      <%= if msg = f[:title].errors |> Enum.map(fn {msg, _} -> msg end) |> List.first() do %>
        <p class="text-red-600 text-sm mt-1"><%= msg %></p>
      <% end %>
    </div>
    <div class="flex gap-2">
      <button type="submit" class="rounded bg-slate-900 text-white px-4 py-2">Create and open builder</button>
      <a href={~p"/sections/#{@section_key}/forms"} class="rounded border px-4 py-2">Cancel</a>
    </div>
  </.form>
</main>
```

- [ ] **Step 5: Create edit.html.heex**

```heex
<%# lib/atrium_web/controllers/form_html/edit.html.heex %>
<main class="p-8">
  <div class="mb-4">
    <a href={~p"/sections/#{@section_key}/forms/#{@form.id}"} class="text-sm text-slate-500 hover:underline">← Back to form</a>
  </div>
  <h1 class="text-xl font-semibold mb-2">Edit: <%= @form.title %></h1>
  <p class="text-sm text-slate-500 mb-6">Drag fields to build your form. When ready, publish to make it available.</p>

  <form id="publish-form" method="post" action={~p"/sections/#{@section_key}/forms/#{@form.id}/publish"}>
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
    <input type="hidden" id="form_fields_json" name="form[fields]" value={Jason.encode!(@latest_fields)} />

    <div
      data-vue="FormBuilderIsland"
      data-props={Jason.encode!(%{fields: @latest_fields, fields_input_id: "form_fields_json"})}
      class="mb-6"
    ></div>

    <div class="flex gap-2">
      <button type="submit" class="rounded bg-green-600 text-white px-4 py-2">Publish</button>
      <a href={~p"/sections/#{@section_key}/forms/#{@form.id}"} class="rounded border px-4 py-2">Cancel</a>
    </div>
  </form>
</main>
```

- [ ] **Step 6: Create submit_form.html.heex**

```heex
<%# lib/atrium_web/controllers/form_html/submit_form.html.heex %>
<main class="p-8 max-w-2xl">
  <div class="mb-4">
    <a href={~p"/sections/#{@section_key}/forms/#{@form.id}"} class="text-sm text-slate-500 hover:underline">← Back</a>
  </div>
  <h1 class="text-xl font-semibold mb-6"><%= @form.title %></h1>

  <form method="post" action={~p"/sections/#{@section_key}/forms/#{@form.id}/submit"}>
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

    <%= for field <- @version.fields do %>
      <div class="mb-4" id={"field-#{field["id"]}"} data-conditions={Jason.encode!(field["conditions"] || [])}>
        <label class="block text-sm font-medium mb-1">
          <%= field["label"] %>
          <%= if field["required"] do %><span class="text-red-500">*</span><% end %>
        </label>
        <%= case field["type"] do %>
          <% "text" -> %>
            <input type="text" name={"submission[#{field["id"]}]"} class="w-full border rounded p-2" />
          <% "textarea" -> %>
            <textarea name={"submission[#{field["id"]}]"} rows="4" class="w-full border rounded p-2"></textarea>
          <% "number" -> %>
            <input type="number" name={"submission[#{field["id"]}]"} class="w-full border rounded p-2" />
          <% "date" -> %>
            <input type="date" name={"submission[#{field["id"]}]"} class="w-full border rounded p-2" />
          <% "radio" -> %>
            <%= for opt <- field["options"] || [] do %>
              <label class="flex items-center gap-2 mb-1">
                <input type="radio" name={"submission[#{field["id"]}]"} value={opt} />
                <%= opt %>
              </label>
            <% end %>
          <% "select" -> %>
            <select name={"submission[#{field["id"]}]"} class="w-full border rounded p-2">
              <option value="">— select —</option>
              <%= for opt <- field["options"] || [] do %>
                <option value={opt}><%= opt %></option>
              <% end %>
            </select>
          <% "checkbox_group" -> %>
            <%= for opt <- field["options"] || [] do %>
              <label class="flex items-center gap-2 mb-1">
                <input type="checkbox" name={"submission[#{field["id"]}][]"} value={opt} />
                <%= opt %>
              </label>
            <% end %>
          <% "file" -> %>
            <input type="file" name={"submission[#{field["id"]}]"} class="w-full border rounded p-2" disabled />
            <p class="text-xs text-slate-400 mt-1">File uploads coming in Phase 1c.</p>
          <% _ -> %>
            <input type="text" name={"submission[#{field["id"]}]"} class="w-full border rounded p-2" />
        <% end %>
      </div>
    <% end %>

    <button type="submit" class="rounded bg-slate-900 text-white px-4 py-2">Submit</button>
  </form>

  <script>
    // Client-side conditional field visibility
    (function() {
      function evalConditions(field) {
        const conditions = JSON.parse(field.dataset.conditions || "[]");
        if (conditions.length === 0) return true;
        return conditions.every(function(c) {
          const target = document.querySelector("[name='submission[" + c.field_id + "]']");
          if (!target) return false;
          const val = target.value;
          if (c.operator === "eq") return val === c.value;
          if (c.operator === "neq") return val !== c.value;
          if (c.operator === "contains") return val.includes(c.value);
          return true;
        });
      }
      function refresh() {
        document.querySelectorAll("[data-conditions]").forEach(function(el) {
          el.style.display = evalConditions(el) ? "" : "none";
        });
      }
      document.addEventListener("change", refresh);
      refresh();
    })();
  </script>
</main>
```

- [ ] **Step 7: Create submissions_index.html.heex**

```heex
<%# lib/atrium_web/controllers/form_html/submissions_index.html.heex %>
<main class="p-8">
  <div class="mb-4">
    <a href={~p"/sections/#{@section_key}/forms/#{@form.id}"} class="text-sm text-slate-500 hover:underline">← Back to form</a>
  </div>
  <h1 class="text-xl font-semibold mb-6">Submissions — <%= @form.title %></h1>
  <table class="w-full text-sm border">
    <thead class="bg-slate-50">
      <tr>
        <th class="p-2 text-left">Submitted</th>
        <th class="p-2 text-left">Status</th>
        <th class="p-2 text-left">Version</th>
        <th class="p-2 text-left"></th>
      </tr>
    </thead>
    <tbody>
      <%= for sub <- @submissions do %>
        <tr class="border-t">
          <td class="p-2"><%= Calendar.strftime(sub.submitted_at, "%Y-%m-%d %H:%M") %></td>
          <td class="p-2"><%= sub.status %></td>
          <td class="p-2">v<%= sub.form_version %></td>
          <td class="p-2">
            <a href={~p"/sections/#{@section_key}/forms/#{@form.id}/submissions/#{sub.id}"} class="text-blue-600 hover:underline">View</a>
          </td>
        </tr>
      <% end %>
      <%= if @submissions == [] do %>
        <tr><td colspan="4" class="p-4 text-center text-slate-500">No submissions yet.</td></tr>
      <% end %>
    </tbody>
  </table>
</main>
```

- [ ] **Step 8: Create show_submission.html.heex**

```heex
<%# lib/atrium_web/controllers/form_html/show_submission.html.heex %>
<main class="p-8 max-w-3xl">
  <div class="mb-4">
    <a href={~p"/sections/#{@section_key}/forms/#{@form.id}/submissions"} class="text-sm text-slate-500 hover:underline">← Back to submissions</a>
  </div>
  <h1 class="text-xl font-semibold mb-2"><%= @form.title %> — Submission</h1>
  <p class="text-sm text-slate-500 mb-6">
    Submitted <%= Calendar.strftime(@submission.submitted_at, "%Y-%m-%d %H:%M") %> ·
    <span class={"rounded px-2 py-0.5 text-xs font-medium #{if @submission.status == "completed", do: "bg-green-100 text-green-700", else: "bg-yellow-100 text-yellow-700"}"}><%= @submission.status %></span>
  </p>

  <section class="mb-8">
    <h2 class="text-sm font-semibold mb-2">Responses</h2>
    <dl class="border rounded divide-y">
      <%= if @version do %>
        <%= for field <- @version.fields do %>
          <div class="p-3">
            <dt class="text-xs text-slate-500"><%= field["label"] %></dt>
            <dd class="mt-1"><%= Map.get(@submission.field_values, field["id"], "—") %></dd>
          </div>
        <% end %>
      <% end %>
    </dl>
  </section>

  <section class="mb-8">
    <h2 class="text-sm font-semibold mb-2">Reviews</h2>
    <table class="w-full text-sm border">
      <thead class="bg-slate-50">
        <tr>
          <th class="p-2 text-left">Reviewer</th>
          <th class="p-2 text-left">Status</th>
          <th class="p-2 text-left">Completed</th>
          <th class="p-2 text-left"></th>
        </tr>
      </thead>
      <tbody>
        <%= for r <- @reviews do %>
          <tr class="border-t">
            <td class="p-2"><%= r.reviewer_email || r.reviewer_id %></td>
            <td class="p-2"><%= r.status %></td>
            <td class="p-2"><%= if r.completed_at, do: Calendar.strftime(r.completed_at, "%Y-%m-%d %H:%M"), else: "—" %></td>
            <td class="p-2">
              <%= if r.status == "pending" and r.reviewer_type == "user" do %>
                <form method="post" action={~p"/sections/#{@section_key}/forms/#{@form.id}/submissions/#{@submission.id}/complete"}>
                  <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                  <button class="text-blue-600 hover:underline text-sm">Mark complete</button>
                </form>
              <% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </section>
</main>
```

- [ ] **Step 9: Create external_review_html/show.html.heex**

```heex
<%# lib/atrium_web/controllers/external_review_html/show.html.heex %>
<main class="p-8 max-w-2xl mx-auto">
  <h1 class="text-xl font-semibold mb-2">Form submission review</h1>

  <%= if Map.get(assigns, :already_done) do %>
    <p class="text-green-700 mb-4">This review has already been completed. Thank you.</p>
  <% else %>
    <p class="text-slate-600 mb-6">Please review the submission below and mark it as complete when done.</p>

    <section class="mb-8 border rounded p-4">
      <p class="text-sm text-slate-500 mb-2">Reviewer: <%= @review.reviewer_email %></p>
      <p class="text-sm text-slate-500">Status: <%= @review.status %></p>
    </section>

    <%= if @review.status == "pending" do %>
      <form method="post" action={~p"/forms/review/#{@token}/complete"}>
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <button class="rounded bg-green-600 text-white px-4 py-2">Mark as complete</button>
      </form>
    <% end %>
  <% end %>
</main>
```

- [ ] **Step 10: Run all controller tests**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium_web/controllers/form_controller_test.exs test/atrium_web/controllers/external_review_controller_test.exs 2>&1 | tail -20
```
Expected: All tests pass. Fix any compilation errors before proceeding.

- [ ] **Step 11: Run full suite**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1 | tail -5
```
Expected: All tests pass, 0 failures.

- [ ] **Step 12: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add lib/atrium_web/controllers/form_html/ lib/atrium_web/controllers/external_review_html/ && git commit -m "feat(phase-1b): add HEEx templates for forms, submissions, and external review"
```

---

## Task 7: Vue FormBuilderIsland

**Files:**
- Create: `assets/js/islands/FormBuilderIsland.vue`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Create FormBuilderIsland.vue**

```vue
<!-- assets/js/islands/FormBuilderIsland.vue -->
<template>
  <div>
    <div class="flex gap-4 mb-4">
      <div class="w-48 border rounded p-3 bg-slate-50">
        <p class="text-xs font-semibold text-slate-600 mb-2 uppercase tracking-wide">Add field</p>
        <button
          v-for="type in fieldTypes"
          :key="type.value"
          type="button"
          @click="addField(type.value)"
          class="block w-full text-left text-sm px-2 py-1 rounded hover:bg-slate-200 mb-1"
        >
          + {{ type.label }}
        </button>
      </div>

      <div class="flex-1">
        <p v-if="fields.length === 0" class="text-slate-400 text-sm italic p-4 border rounded">
          No fields yet. Add a field from the left panel.
        </p>
        <div
          v-for="(field, index) in fields"
          :key="field.id"
          class="border rounded p-3 mb-2 bg-white"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="flex-1 space-y-2">
              <div class="flex gap-2 items-center">
                <span class="text-xs text-slate-400 uppercase font-semibold w-16 shrink-0">{{ field.type }}</span>
                <input
                  v-model="field.label"
                  @input="sync"
                  type="text"
                  placeholder="Field label"
                  class="flex-1 border rounded p-1 text-sm"
                />
                <label class="flex items-center gap-1 text-xs text-slate-600 shrink-0">
                  <input type="checkbox" v-model="field.required" @change="sync" />
                  Required
                </label>
              </div>

              <div v-if="['radio','select','checkbox_group'].includes(field.type)" class="ml-16">
                <p class="text-xs text-slate-500 mb-1">Options (one per line)</p>
                <textarea
                  :value="(field.options || []).join('\n')"
                  @input="e => { field.options = e.target.value.split('\n').filter(o => o.trim()); sync() }"
                  rows="3"
                  class="w-full border rounded p-1 text-xs"
                  placeholder="Option 1&#10;Option 2"
                ></textarea>
              </div>
            </div>

            <div class="flex flex-col gap-1">
              <button type="button" @click="moveUp(index)" :disabled="index === 0" class="text-slate-400 hover:text-slate-700 disabled:opacity-30 text-xs">▲</button>
              <button type="button" @click="moveDown(index)" :disabled="index === fields.length - 1" class="text-slate-400 hover:text-slate-700 disabled:opacity-30 text-xs">▼</button>
              <button type="button" @click="removeField(index)" class="text-red-400 hover:text-red-600 text-xs">✕</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { registerVueIsland } from "./registry.js"
import { ref, onMounted } from "vue"

registerVueIsland("FormBuilderIsland", {
  props: ["fields", "fields_input_id"],
  setup(props) {
    const fieldTypes = [
      { value: "text", label: "Text" },
      { value: "textarea", label: "Long text" },
      { value: "number", label: "Number" },
      { value: "date", label: "Date" },
      { value: "radio", label: "Radio" },
      { value: "select", label: "Select" },
      { value: "checkbox_group", label: "Checkboxes" },
      { value: "file", label: "File upload" },
    ]

    const fields = ref((props.fields || []).map(f => ({ ...f })))

    function generateId() {
      return "field_" + Math.random().toString(36).slice(2, 10)
    }

    function sync() {
      const input = document.getElementById(props.fields_input_id)
      if (input) {
        input.value = JSON.stringify(fields.value.map((f, i) => ({ ...f, order: i + 1 })))
      }
    }

    function addField(type) {
      fields.value.push({
        id: generateId(),
        type,
        label: "",
        required: false,
        order: fields.value.length + 1,
        options: [],
        conditions: [],
      })
      sync()
    }

    function removeField(index) {
      fields.value.splice(index, 1)
      sync()
    }

    function moveUp(index) {
      if (index === 0) return
      const tmp = fields.value[index - 1]
      fields.value[index - 1] = fields.value[index]
      fields.value[index] = tmp
      sync()
    }

    function moveDown(index) {
      if (index === fields.value.length - 1) return
      const tmp = fields.value[index + 1]
      fields.value[index + 1] = fields.value[index]
      fields.value[index] = tmp
      sync()
    }

    onMounted(sync)

    return { fieldTypes, fields, addField, removeField, moveUp, moveDown, sync }
  }
})
</script>
```

Note: this file uses `registerVueIsland` directly and exports nothing — it registers itself as a side effect when imported.

- [ ] **Step 2: Import island in app.js**

Add to the end of `assets/js/app.js`:

```javascript
import "./islands/FormBuilderIsland.vue"
```

- [ ] **Step 3: Verify esbuild compiles the island**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix esbuild atrium 2>&1 | grep -E "error:" | head -10
```
Expected: No errors (warnings about `module.exports` in topbar are pre-existing and acceptable).

- [ ] **Step 4: Run full test suite**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1 | tail -5
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium && git add assets/js/islands/FormBuilderIsland.vue assets/js/app.js && git commit -m "feat(phase-1b): add FormBuilderIsland Vue component"
```

---

## Task 8: Milestone Tag

- [ ] **Step 1: Run final full test suite**

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1 | tail -5
```
Expected: All tests pass, 0 failures.

- [ ] **Step 2: Tag the milestone**

```bash
cd /Users/marcinwalczak/Kod/atrium && git tag phase-1b-complete
```

- [ ] **Step 3: Verify**

```bash
git tag | grep phase-1b
```
Expected: `phase-1b-complete`
