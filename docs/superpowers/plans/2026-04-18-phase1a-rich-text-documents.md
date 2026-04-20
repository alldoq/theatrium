# Phase 1a: Rich-Text Documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver tenant-scoped rich-text documents with ISO lifecycle (draft→in_review→approved→archived), full version history, audit integration, and server-rendered CRUD UI with a Trix editor island.

**Architecture:** Two schemas (`Document` + `DocumentVersion`) in a new `Atrium.Documents` context. Controller-based (no LiveView) with 10 routes under `/sections/:section_key/documents`. Authorization reuses `Policy.can?/4` with `:edit`/`:approve` capabilities on section targets.

**Tech Stack:** Elixir/Phoenix 1.8, Ecto 3.x, PostgreSQL (schema-per-tenant via Triplex), Trix editor (bundled with Phoenix via esbuild), HEEx templates, `Atrium.Audit` for event logging.

---

## File Structure

**New files:**
- `priv/repo/tenant_migrations/20260421000001_create_documents.exs`
- `priv/repo/tenant_migrations/20260421000002_create_document_versions.exs`
- `lib/atrium/documents/document.ex`
- `lib/atrium/documents/document_version.ex`
- `lib/atrium/documents.ex`
- `lib/atrium_web/controllers/document_controller.ex`
- `lib/atrium_web/controllers/document_html.ex`
- `lib/atrium_web/controllers/document_html/index.html.heex`
- `lib/atrium_web/controllers/document_html/show.html.heex`
- `lib/atrium_web/controllers/document_html/new.html.heex`
- `lib/atrium_web/controllers/document_html/edit.html.heex`
- `test/atrium/documents_test.exs`
- `test/atrium_web/controllers/document_controller_test.exs`

**Modified files:**
- `lib/atrium_web/router.ex` — add 10 document routes inside authenticated scope

---

## Task 1: Tenant Migrations

**Files:**
- Create: `priv/repo/tenant_migrations/20260421000001_create_documents.exs`
- Create: `priv/repo/tenant_migrations/20260421000002_create_document_versions.exs`

- [ ] **Step 1: Write the documents migration**

```elixir
# priv/repo/tenant_migrations/20260421000001_create_documents.exs
defmodule Atrium.Repo.TenantMigrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :title, :string, null: false
      add :section_key, :string, null: false
      add :subsection_slug, :string, null: true
      add :status, :string, null: false, default: "draft"
      add :body_html, :text
      add :current_version, :integer, null: false, default: 1
      add :author_id, :binary_id, null: false
      add :approved_by_id, :binary_id, null: true
      add :approved_at, :utc_datetime_usec, null: true

      timestamps(type: :utc_datetime_usec)
    end

    create index(:documents, [:section_key])
    create index(:documents, [:section_key, :subsection_slug])
    create index(:documents, [:author_id])
    create index(:documents, [:status])
  end
end
```

- [ ] **Step 2: Write the document_versions migration**

```elixir
# priv/repo/tenant_migrations/20260421000002_create_document_versions.exs
defmodule Atrium.Repo.TenantMigrations.CreateDocumentVersions do
  use Ecto.Migration

  def change do
    create table(:document_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :title, :string, null: false
      add :body_html, :text
      add :saved_by_id, :binary_id, null: false
      add :saved_at, :utc_datetime_usec, null: false
    end

    create index(:document_versions, [:document_id])
    create unique_index(:document_versions, [:document_id, :version])
  end
end
```

- [ ] **Step 3: Run migrations to verify they execute cleanly**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix ecto.migrate
```
Expected: migrations applied with no errors.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/tenant_migrations/20260421000001_create_documents.exs \
        priv/repo/tenant_migrations/20260421000002_create_document_versions.exs
git commit -m "feat(phase-1a): add documents and document_versions tenant migrations"
```

---

## Task 2: Ecto Schemas

**Files:**
- Create: `lib/atrium/documents/document.ex`
- Create: `lib/atrium/documents/document_version.ex`

- [ ] **Step 1: Write failing tests for Document changeset**

```elixir
# test/atrium/documents_test.exs  (partial — schemas section)
defmodule Atrium.Documents.DocumentSchemaTest do
  use Atrium.DataCase, async: true
  alias Atrium.Documents.Document

  describe "Document.changeset/2" do
    test "valid attrs produce a valid changeset" do
      attrs = %{
        title: "My Policy",
        section_key: "hr",
        body_html: "<p>content</p>",
        author_id: Ecto.UUID.generate()
      }
      cs = Document.changeset(%Document{}, attrs)
      assert cs.valid?
    end

    test "title is required" do
      cs = Document.changeset(%Document{}, %{section_key: "hr", author_id: Ecto.UUID.generate()})
      assert {:title, _} = List.first(cs.errors)
    end

    test "section_key is required" do
      cs = Document.changeset(%Document{}, %{title: "T", author_id: Ecto.UUID.generate()})
      assert errors_on(cs)[:section_key]
    end

    test "author_id is required" do
      cs = Document.changeset(%Document{}, %{title: "T", section_key: "hr"})
      assert errors_on(cs)[:author_id]
    end

    test "status defaults to draft" do
      cs = Document.changeset(%Document{}, %{title: "T", section_key: "hr", author_id: Ecto.UUID.generate()})
      assert cs.changes[:status] == nil
      assert %Document{status: "draft"} = Ecto.Changeset.apply_changes(cs)
    end

    test "status must be a valid value" do
      cs = Document.changeset(%Document{}, %{title: "T", section_key: "hr", author_id: Ecto.UUID.generate(), status: "nonsense"})
      assert errors_on(cs)[:status]
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium/documents_test.exs 2>&1 | head -30
```
Expected: compile error or test failures (Document module does not exist yet).

- [ ] **Step 3: Write the Document schema**

```elixir
# lib/atrium/documents/document.ex
defmodule Atrium.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft in_review approved archived)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "documents" do
    field :title, :string
    field :section_key, :string
    field :subsection_slug, :string
    field :status, :string, default: "draft"
    field :body_html, :string
    field :current_version, :integer, default: 1
    field :author_id, :binary_id
    field :approved_by_id, :binary_id
    field :approved_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [:title, :section_key, :subsection_slug, :body_html, :author_id])
    |> validate_required([:title, :section_key, :author_id])
    |> validate_length(:title, min: 1, max: 500)
  end

  def update_changeset(doc, attrs) do
    doc
    |> cast(attrs, [:title, :body_html])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 500)
  end

  def status_changeset(doc, status, extra_attrs \\ %{}) do
    doc
    |> cast(Map.merge(%{status: status}, extra_attrs), [:status, :approved_by_id, :approved_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  def version_bump_changeset(doc) do
    change(doc, current_version: doc.current_version + 1)
  end
end
```

- [ ] **Step 4: Write the DocumentVersion schema**

```elixir
# lib/atrium/documents/document_version.ex
defmodule Atrium.Documents.DocumentVersion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "document_versions" do
    field :document_id, :binary_id
    field :version, :integer
    field :title, :string
    field :body_html, :string
    field :saved_by_id, :binary_id
    field :saved_at, :utc_datetime_usec
  end

  def changeset(dv, attrs) do
    dv
    |> cast(attrs, [:document_id, :version, :title, :body_html, :saved_by_id, :saved_at])
    |> validate_required([:document_id, :version, :title, :saved_by_id, :saved_at])
  end
end
```

- [ ] **Step 5: Run schema tests to verify they pass**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium/documents_test.exs 2>&1 | head -40
```
Expected: 5 tests pass (DocumentSchemaTest only — Documents context module not yet written).

- [ ] **Step 6: Commit**

```bash
git add lib/atrium/documents/document.ex \
        lib/atrium/documents/document_version.ex \
        test/atrium/documents_test.exs
git commit -m "feat(phase-1a): add Document and DocumentVersion schemas"
```

---

## Task 3: Documents Context — CRUD + Versions

**Files:**
- Create: `lib/atrium/documents.ex`
- Modify: `test/atrium/documents_test.exs` (add context tests)

- [ ] **Step 1: Write failing tests for CRUD**

Append to `test/atrium/documents_test.exs`:

```elixir
defmodule Atrium.DocumentsTest do
  use Atrium.TenantCase
  alias Atrium.Documents
  alias Atrium.Accounts

  # Helper: create a user to act as author/actor
  defp build_user(prefix) do
    {:ok, user} = Accounts.invite_user(prefix, %{
      email: "doc_user_#{System.unique_integer([:positive])}@example.com",
      name: "Doc User"
    })
    user
  end

  describe "create_document/3" do
    test "creates a document and snapshots version 1", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      attrs = %{title: "HR Policy", section_key: "hr", body_html: "<p>Hello</p>"}

      {:ok, doc} = Documents.create_document(prefix, attrs, user)

      assert doc.title == "HR Policy"
      assert doc.section_key == "hr"
      assert doc.status == "draft"
      assert doc.current_version == 1
      assert doc.author_id == user.id

      versions = Documents.list_versions(prefix, doc.id)
      assert length(versions) == 1
      assert hd(versions).version == 1
      assert hd(versions).title == "HR Policy"
    end

    test "returns error for missing required fields", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:error, %Ecto.Changeset{}} = Documents.create_document(prefix, %{}, user)
    end
  end

  describe "get_document!/2" do
    test "returns the document", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "T", section_key: "docs", body_html: ""}, user)
      assert Documents.get_document!(prefix, doc.id).id == doc.id
    end

    test "raises on missing id", %{tenant_prefix: prefix} do
      assert_raise Ecto.NoResultsError, fn ->
        Documents.get_document!(prefix, Ecto.UUID.generate())
      end
    end
  end

  describe "list_documents/3" do
    test "lists documents in a section", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, _} = Documents.create_document(prefix, %{title: "A", section_key: "hr", body_html: ""}, user)
      {:ok, _} = Documents.create_document(prefix, %{title: "B", section_key: "hr", body_html: ""}, user)
      {:ok, _} = Documents.create_document(prefix, %{title: "C", section_key: "docs", body_html: ""}, user)

      hr_docs = Documents.list_documents(prefix, "hr")
      assert Enum.all?(hr_docs, &(&1.section_key == "hr"))
      assert length(hr_docs) >= 2
    end
  end

  describe "update_document/4" do
    test "updates title+body and snapshots a new version", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "Old", section_key: "hr", body_html: "<p>old</p>"}, user)

      {:ok, updated} = Documents.update_document(prefix, doc, %{title: "New", body_html: "<p>new</p>"}, user)

      assert updated.title == "New"
      assert updated.current_version == 2

      versions = Documents.list_versions(prefix, doc.id)
      assert length(versions) == 2
    end

    test "cannot update a non-draft document", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "T", section_key: "hr", body_html: ""}, user)
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)

      assert {:error, :not_draft} = Documents.update_document(prefix, doc, %{title: "X"}, user)
    end
  end

  describe "list_versions/2" do
    test "returns versions ordered by version desc", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "V1", section_key: "hr", body_html: ""}, user)
      {:ok, doc} = Documents.update_document(prefix, doc, %{title: "V2", body_html: ""}, user)
      {:ok, _} = Documents.update_document(prefix, doc, %{title: "V3", body_html: ""}, user)

      versions = Documents.list_versions(prefix, doc.id)
      assert length(versions) == 3
      assert hd(versions).version == 3
    end
  end
end
```

- [ ] **Step 2: Run to verify failures**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium/documents_test.exs --only DocumentsTest 2>&1 | head -20
```
Expected: compile error (Documents module not yet defined).

- [ ] **Step 3: Write the Documents context module (CRUD + versions section)**

```elixir
# lib/atrium/documents.ex
defmodule Atrium.Documents do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Documents.{Document, DocumentVersion}

  # ---------------------------------------------------------------------------
  # CRUD
  # ---------------------------------------------------------------------------

  def create_document(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(attrs, :author_id, actor_user.id)

    Repo.transaction(fn ->
      with {:ok, doc} <- insert_document(prefix, attrs_with_author),
           {:ok, _ver} <- insert_version(prefix, doc, actor_user),
           {:ok, _} <- Audit.log(prefix, "document.created", %{
             actor: {:user, actor_user.id},
             resource: {"Document", doc.id},
             changes: %{"title" => [nil, doc.title], "section_key" => [nil, doc.section_key]}
           }) do
        doc
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_document!(prefix, id) do
    Repo.get!(Document, id, prefix: prefix)
  end

  def list_documents(prefix, section_key, opts \\ []) do
    query =
      from d in Document,
        where: d.section_key == ^section_key,
        order_by: [desc: d.inserted_at]

    query =
      case Keyword.get(opts, :subsection_slug) do
        nil -> query
        slug -> where(query, [d], d.subsection_slug == ^slug)
      end

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [d], d.status == ^status)
      end

    Repo.all(query, prefix: prefix)
  end

  def update_document(prefix, doc, attrs, actor_user) do
    if doc.status != "draft" do
      {:error, :not_draft}
    else
      Repo.transaction(fn ->
        with {:ok, updated} <- apply_update(prefix, doc, attrs),
             {:ok, _ver} <- insert_version(prefix, updated, actor_user),
             {:ok, _} <- Audit.log(prefix, "document.updated", %{
               actor: {:user, actor_user.id},
               resource: {"Document", updated.id},
               changes: Audit.changeset_diff(doc, updated)
             }) do
          updated
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Versions
  # ---------------------------------------------------------------------------

  def list_versions(prefix, document_id) do
    from(v in DocumentVersion,
      where: v.document_id == ^document_id,
      order_by: [desc: v.version]
    )
    |> Repo.all(prefix: prefix)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp insert_document(prefix, attrs) do
    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  defp apply_update(prefix, doc, attrs) do
    doc
    |> Document.update_changeset(attrs)
    |> Document.version_bump_changeset()
    |> Repo.update(prefix: prefix)
  end

  defp insert_version(prefix, doc, actor_user) do
    %DocumentVersion{}
    |> DocumentVersion.changeset(%{
      document_id: doc.id,
      version: doc.current_version,
      title: doc.title,
      body_html: doc.body_html,
      saved_by_id: actor_user.id,
      saved_at: DateTime.utc_now()
    })
    |> Repo.insert(prefix: prefix)
  end
end
```

- [ ] **Step 4: Run CRUD tests to verify they pass**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium/documents_test.exs 2>&1 | tail -20
```
Expected: All tests in documents_test.exs pass.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/documents.ex test/atrium/documents_test.exs
git commit -m "feat(phase-1a): add Documents context with CRUD and version snapshots"
```

---

## Task 4: Lifecycle Transitions

**Files:**
- Modify: `lib/atrium/documents.ex` — add lifecycle functions
- Modify: `test/atrium/documents_test.exs` — add lifecycle tests

- [ ] **Step 1: Write failing lifecycle tests**

Append to `test/atrium/documents_test.exs`:

```elixir
  describe "lifecycle transitions" do
    setup %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "Policy", section_key: "hr", body_html: "<p>v1</p>"}, user)
      %{doc: doc, user: user}
    end

    test "submit_for_review: draft → in_review", %{tenant_prefix: prefix, doc: doc, user: user} do
      {:ok, updated} = Documents.submit_for_review(prefix, doc, user)
      assert updated.status == "in_review"
    end

    test "submit_for_review: non-draft is rejected", %{tenant_prefix: prefix, doc: doc, user: user} do
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      assert {:error, :invalid_transition} = Documents.submit_for_review(prefix, doc, user)
    end

    test "reject_document: in_review → draft", %{tenant_prefix: prefix, doc: doc, user: user} do
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      {:ok, rejected} = Documents.reject_document(prefix, doc, user)
      assert rejected.status == "draft"
    end

    test "reject_document: must be in_review", %{tenant_prefix: prefix, doc: doc, user: user} do
      assert {:error, :invalid_transition} = Documents.reject_document(prefix, doc, user)
    end

    test "approve_document: in_review → approved, sets approved_by_id and approved_at", %{tenant_prefix: prefix, doc: doc, user: user} do
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      {:ok, approved} = Documents.approve_document(prefix, doc, user)
      assert approved.status == "approved"
      assert approved.approved_by_id == user.id
      assert approved.approved_at
    end

    test "approve_document: must be in_review", %{tenant_prefix: prefix, doc: doc, user: user} do
      assert {:error, :invalid_transition} = Documents.approve_document(prefix, doc, user)
    end

    test "archive_document: approved → archived", %{tenant_prefix: prefix, doc: doc, user: user} do
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      {:ok, doc} = Documents.approve_document(prefix, doc, user)
      {:ok, archived} = Documents.archive_document(prefix, doc, user)
      assert archived.status == "archived"
    end

    test "archive_document: must be approved", %{tenant_prefix: prefix, doc: doc, user: user} do
      assert {:error, :invalid_transition} = Documents.archive_document(prefix, doc, user)
    end
  end

  describe "audit events" do
    test "create_document emits document.created", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "Audit Me", section_key: "hr", body_html: ""}, user)
      history = Audit.history_for(prefix, "Document", doc.id)
      assert Enum.any?(history, &(&1.action == "document.created"))
    end

    test "update_document emits document.updated", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "Before", section_key: "hr", body_html: ""}, user)
      {:ok, _} = Documents.update_document(prefix, doc, %{title: "After", body_html: ""}, user)
      history = Audit.history_for(prefix, "Document", doc.id)
      assert Enum.any?(history, &(&1.action == "document.updated"))
    end

    test "lifecycle transitions emit correct audit events", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "T", section_key: "hr", body_html: ""}, user)
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      {:ok, doc} = Documents.approve_document(prefix, doc, user)
      {:ok, _} = Documents.archive_document(prefix, doc, user)
      history = Audit.history_for(prefix, "Document", doc.id)
      actions = Enum.map(history, & &1.action)
      assert "document.submitted" in actions
      assert "document.approved" in actions
      assert "document.archived" in actions
    end
  end
```

- [ ] **Step 2: Run to verify failures**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium/documents_test.exs 2>&1 | grep -E "undefined function|test.*FAILED" | head -10
```
Expected: failures — lifecycle functions not yet defined.

- [ ] **Step 3: Add lifecycle functions to lib/atrium/documents.ex**

Add these functions to `lib/atrium/documents.ex` after the `list_versions/2` function and before the private helpers section:

```elixir
  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  def submit_for_review(prefix, %Document{status: "draft"} = doc, actor_user) do
    transition(prefix, doc, "in_review", actor_user, "document.submitted")
  end

  def submit_for_review(_prefix, _doc, _actor_user), do: {:error, :invalid_transition}

  def reject_document(prefix, %Document{status: "in_review"} = doc, actor_user) do
    transition(prefix, doc, "draft", actor_user, "document.rejected")
  end

  def reject_document(_prefix, _doc, _actor_user), do: {:error, :invalid_transition}

  def approve_document(prefix, %Document{status: "in_review"} = doc, actor_user) do
    extra = %{approved_by_id: actor_user.id, approved_at: DateTime.utc_now()}

    Repo.transaction(fn ->
      with {:ok, updated} <- apply_status(prefix, doc, "approved", extra),
           {:ok, _} <- Audit.log(prefix, "document.approved", %{
             actor: {:user, actor_user.id},
             resource: {"Document", updated.id},
             changes: %{"status" => [doc.status, "approved"]}
           }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def approve_document(_prefix, _doc, _actor_user), do: {:error, :invalid_transition}

  def archive_document(prefix, %Document{status: "approved"} = doc, actor_user) do
    transition(prefix, doc, "archived", actor_user, "document.archived")
  end

  def archive_document(_prefix, _doc, _actor_user), do: {:error, :invalid_transition}
```

Add these private helpers at the bottom of the file (before the last `end`):

```elixir
  defp transition(prefix, doc, new_status, actor_user, audit_action) do
    Repo.transaction(fn ->
      with {:ok, updated} <- apply_status(prefix, doc, new_status, %{}),
           {:ok, _} <- Audit.log(prefix, audit_action, %{
             actor: {:user, actor_user.id},
             resource: {"Document", updated.id},
             changes: %{"status" => [doc.status, new_status]}
           }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp apply_status(prefix, doc, status, extra_attrs) do
    doc
    |> Document.status_changeset(status, extra_attrs)
    |> Repo.update(prefix: prefix)
  end
```

- [ ] **Step 4: Run all documents tests**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium/documents_test.exs 2>&1 | tail -20
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/documents.ex test/atrium/documents_test.exs
git commit -m "feat(phase-1a): add lifecycle transitions and audit events to Documents context"
```

---

## Task 5: Router + DocumentController

**Files:**
- Modify: `lib/atrium_web/router.ex`
- Create: `lib/atrium_web/controllers/document_controller.ex`
- Create: `lib/atrium_web/controllers/document_html.ex`

- [ ] **Step 1: Write failing controller tests**

```elixir
# test/atrium_web/controllers/document_controller_test.exs
defmodule AtriumWeb.DocumentControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.{Tenants, Accounts}
  alias Atrium.Tenants.Provisioner
  alias Atrium.Documents

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "doc_ctrl_test", name: "Doc Ctrl Test"})
    {:ok, tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop("doc_ctrl_test") end)

    prefix = Triplex.to_prefix("doc_ctrl_test")
    {:ok, user} = Accounts.invite_user(prefix, %{email: "ctrl@example.com", name: "Ctrl User"})
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })

    conn =
      build_conn()
      |> Map.put(:host, "doc_ctrl_test.atrium.example")
      |> post("/login", %{email: "ctrl@example.com", password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, "doc_ctrl_test.atrium.example")

    {:ok, conn: conn, prefix: prefix, user: user, tenant: tenant}
  end

  describe "GET /sections/:section_key/documents" do
    test "returns 200 for authenticated user with view permission", %{conn: conn} do
      conn = get(conn, "/sections/docs/documents")
      assert html_response(conn, 200) =~ "Documents"
    end
  end

  describe "GET /sections/:section_key/documents/new" do
    test "renders new form", %{conn: conn} do
      conn = get(conn, "/sections/docs/documents/new")
      assert html_response(conn, 200) =~ "trix-editor"
    end
  end

  describe "POST /sections/:section_key/documents" do
    test "creates document and redirects to show", %{conn: conn} do
      conn = post(conn, "/sections/docs/documents", %{
        document: %{title: "Test Doc", body_html: "<p>hello</p>"}
      })
      assert redirected_to(conn) =~ "/sections/docs/documents/"
    end

    test "re-renders new form on invalid attrs", %{conn: conn} do
      conn = post(conn, "/sections/docs/documents", %{document: %{title: ""}})
      assert html_response(conn, 422) =~ "trix-editor"
    end
  end

  describe "GET /sections/:section_key/documents/:id" do
    test "shows document", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "ShowMe", section_key: "docs", body_html: "<p>x</p>"}, user)
      conn = get(conn, "/sections/docs/documents/#{doc.id}")
      assert html_response(conn, 200) =~ "ShowMe"
    end
  end

  describe "GET /sections/:section_key/documents/:id/edit" do
    test "renders edit form for draft document", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "EditMe", section_key: "docs", body_html: "<p>y</p>"}, user)
      conn = get(conn, "/sections/docs/documents/#{doc.id}/edit")
      assert html_response(conn, 200) =~ "trix-editor"
    end
  end

  describe "PUT /sections/:section_key/documents/:id" do
    test "updates draft document and redirects", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "Old", section_key: "docs", body_html: ""}, user)
      conn = put(conn, "/sections/docs/documents/#{doc.id}", %{
        document: %{title: "New", body_html: "<p>new</p>"}
      })
      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
    end
  end

  describe "POST /sections/:section_key/documents/:id/submit" do
    test "transitions to in_review and redirects", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "Sub", section_key: "docs", body_html: ""}, user)
      conn = post(conn, "/sections/docs/documents/#{doc.id}/submit")
      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
      assert Documents.get_document!(prefix, doc.id).status == "in_review"
    end
  end

  describe "POST /sections/:section_key/documents/:id/reject" do
    test "transitions to draft and redirects", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "Rej", section_key: "docs", body_html: ""}, user)
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      conn = post(conn, "/sections/docs/documents/#{doc.id}/reject")
      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
      assert Documents.get_document!(prefix, doc.id).status == "draft"
    end
  end

  describe "POST /sections/:section_key/documents/:id/approve" do
    test "transitions to approved and redirects", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "App", section_key: "docs", body_html: ""}, user)
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      conn = post(conn, "/sections/docs/documents/#{doc.id}/approve")
      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
      assert Documents.get_document!(prefix, doc.id).status == "approved"
    end
  end

  describe "POST /sections/:section_key/documents/:id/archive" do
    test "transitions to archived and redirects", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "Arc", section_key: "docs", body_html: ""}, user)
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      {:ok, doc} = Documents.approve_document(prefix, doc, user)
      conn = post(conn, "/sections/docs/documents/#{doc.id}/archive")
      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
      assert Documents.get_document!(prefix, doc.id).status == "archived"
    end
  end
end
```

- [ ] **Step 2: Run to verify failures**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium_web/controllers/document_controller_test.exs 2>&1 | head -20
```
Expected: routing errors / undefined controller.

- [ ] **Step 3: Add routes to lib/atrium_web/router.ex**

In `lib/atrium_web/router.ex`, inside the authenticated scope (the `scope "/" do` block that has `pipe_through [AtriumWeb.Plugs.RequireUser, AtriumWeb.Plugs.AssignNav]`), add the document routes after the existing audit routes:

```elixir
      get  "/sections/:section_key/documents",             DocumentController, :index
      get  "/sections/:section_key/documents/new",         DocumentController, :new
      post "/sections/:section_key/documents",             DocumentController, :create
      get  "/sections/:section_key/documents/:id",         DocumentController, :show
      get  "/sections/:section_key/documents/:id/edit",    DocumentController, :edit
      put  "/sections/:section_key/documents/:id",         DocumentController, :update
      post "/sections/:section_key/documents/:id/submit",  DocumentController, :submit
      post "/sections/:section_key/documents/:id/reject",  DocumentController, :reject
      post "/sections/:section_key/documents/:id/approve", DocumentController, :approve
      post "/sections/:section_key/documents/:id/archive", DocumentController, :archive
```

- [ ] **Step 4: Create the DocumentController**

```elixir
# lib/atrium_web/controllers/document_controller.ex
defmodule AtriumWeb.DocumentController do
  use AtriumWeb, :controller
  alias Atrium.Documents
  alias Atrium.Documents.Document

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: fn conn -> {:section, conn.path_params["section_key"]} end]
       when action in [:index, :show]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: fn conn -> {:section, conn.path_params["section_key"]} end]
       when action in [:new, :create, :edit, :update, :submit]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :approve, target: fn conn -> {:section, conn.path_params["section_key"]} end]
       when action in [:reject, :approve, :archive]

  def index(conn, %{"section_key" => section_key} = params) do
    prefix = conn.assigns.tenant_prefix
    opts = []
    opts = if s = params["subsection_slug"], do: Keyword.put(opts, :subsection_slug, s), else: opts
    opts = if st = params["status"], do: Keyword.put(opts, :status, st), else: opts
    documents = Documents.list_documents(prefix, section_key, opts)
    render(conn, :index, documents: documents, section_key: section_key)
  end

  def new(conn, %{"section_key" => section_key}) do
    changeset = Document.changeset(%Document{}, %{})
    render(conn, :new, changeset: changeset, section_key: section_key)
  end

  def create(conn, %{"section_key" => section_key, "document" => doc_params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    attrs = Map.put(doc_params, "section_key", section_key)

    case Documents.create_document(prefix, attrs, user) do
      {:ok, doc} ->
        conn
        |> put_flash(:info, "Document created.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{doc.id}")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset, section_key: section_key, status: 422)
    end
  end

  def show(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    doc = Documents.get_document!(prefix, id)
    versions = Documents.list_versions(prefix, doc.id)
    render(conn, :show, document: doc, versions: versions, section_key: section_key)
  end

  def edit(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    doc = Documents.get_document!(prefix, id)
    changeset = Document.update_changeset(doc, %{})
    render(conn, :edit, document: doc, changeset: changeset, section_key: section_key)
  end

  def update(conn, %{"section_key" => section_key, "id" => id, "document" => doc_params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    doc = Documents.get_document!(prefix, id)

    case Documents.update_document(prefix, doc, doc_params, user) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, "Document updated.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{updated.id}")

      {:error, :not_draft} ->
        conn
        |> put_flash(:error, "Only draft documents can be edited.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")

      {:error, changeset} ->
        render(conn, :edit, document: doc, changeset: changeset, section_key: section_key, status: 422)
    end
  end

  def submit(conn, %{"section_key" => section_key, "id" => id}) do
    run_transition(conn, section_key, id, &Documents.submit_for_review/3, "Document submitted for review.")
  end

  def reject(conn, %{"section_key" => section_key, "id" => id}) do
    run_transition(conn, section_key, id, &Documents.reject_document/3, "Document returned to draft.")
  end

  def approve(conn, %{"section_key" => section_key, "id" => id}) do
    run_transition(conn, section_key, id, &Documents.approve_document/3, "Document approved.")
  end

  def archive(conn, %{"section_key" => section_key, "id" => id}) do
    run_transition(conn, section_key, id, &Documents.archive_document/3, "Document archived.")
  end

  defp run_transition(conn, section_key, id, transition_fn, success_msg) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    doc = Documents.get_document!(prefix, id)

    case transition_fn.(prefix, doc, user) do
      {:ok, _updated} ->
        conn
        |> put_flash(:info, success_msg)
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "This transition is not allowed in the current state.")
        |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")
    end
  end
end
```

- [ ] **Step 5: Create the HTML view module**

```elixir
# lib/atrium_web/controllers/document_html.ex
defmodule AtriumWeb.DocumentHTML do
  use AtriumWeb, :html

  embed_templates "document_html/*"
end
```

- [ ] **Step 6: Run controller tests (expect template errors, not routing errors)**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium_web/controllers/document_controller_test.exs 2>&1 | head -20
```
Expected: template not found errors (templates not yet created).

- [ ] **Step 7: Commit**

```bash
git add lib/atrium_web/router.ex \
        lib/atrium_web/controllers/document_controller.ex \
        lib/atrium_web/controllers/document_html.ex \
        test/atrium_web/controllers/document_controller_test.exs
git commit -m "feat(phase-1a): add DocumentController with all 10 routes"
```

---

## Task 6: HEEx Templates

**Files:**
- Create: `lib/atrium_web/controllers/document_html/index.html.heex`
- Create: `lib/atrium_web/controllers/document_html/show.html.heex`
- Create: `lib/atrium_web/controllers/document_html/new.html.heex`
- Create: `lib/atrium_web/controllers/document_html/edit.html.heex`

- [ ] **Step 1: Create the index template**

```bash
mkdir -p /Users/marcinwalczak/Kod/atrium/lib/atrium_web/controllers/document_html
```

```heex
<%# lib/atrium_web/controllers/document_html/index.html.heex %>
<main class="p-8">
  <div class="flex items-center justify-between mb-6">
    <h1 class="text-xl font-semibold">Documents — <%= @section_key %></h1>
    <a href={~p"/sections/#{@section_key}/documents/new"} class="rounded bg-slate-900 text-white px-4 py-2 text-sm">
      New document
    </a>
  </div>

  <form method="get" class="flex gap-2 mb-4">
    <select name="status" class="border rounded p-1 text-sm">
      <option value="">All statuses</option>
      <option value="draft">Draft</option>
      <option value="in_review">In Review</option>
      <option value="approved">Approved</option>
      <option value="archived">Archived</option>
    </select>
    <button type="submit" class="rounded bg-slate-200 px-3 py-1 text-sm">Filter</button>
  </form>

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
      <%= for doc <- @documents do %>
        <tr class="border-t hover:bg-slate-50">
          <td class="p-2">
            <a href={~p"/sections/#{@section_key}/documents/#{doc.id}"} class="text-blue-600 hover:underline">
              <%= doc.title %>
            </a>
          </td>
          <td class="p-2">
            <span class={"rounded px-2 py-0.5 text-xs font-medium #{status_badge_class(doc.status)}"}>
              <%= doc.status %>
            </span>
          </td>
          <td class="p-2">v<%= doc.current_version %></td>
          <td class="p-2"><%= Calendar.strftime(doc.updated_at, "%Y-%m-%d %H:%M") %></td>
        </tr>
      <% end %>
      <%= if @documents == [] do %>
        <tr><td colspan="4" class="p-4 text-center text-slate-500">No documents yet.</td></tr>
      <% end %>
    </tbody>
  </table>
</main>
```

- [ ] **Step 2: Add status_badge_class/1 helper to DocumentHTML**

Edit `lib/atrium_web/controllers/document_html.ex`:

```elixir
defmodule AtriumWeb.DocumentHTML do
  use AtriumWeb, :html

  embed_templates "document_html/*"

  def status_badge_class("draft"),     do: "bg-slate-100 text-slate-700"
  def status_badge_class("in_review"), do: "bg-yellow-100 text-yellow-700"
  def status_badge_class("approved"),  do: "bg-green-100 text-green-700"
  def status_badge_class("archived"),  do: "bg-slate-200 text-slate-500"
  def status_badge_class(_),           do: "bg-slate-100 text-slate-700"
end
```

- [ ] **Step 3: Create the show template**

```heex
<%# lib/atrium_web/controllers/document_html/show.html.heex %>
<main class="p-8 max-w-4xl">
  <div class="mb-4">
    <a href={~p"/sections/#{@section_key}/documents"} class="text-sm text-slate-500 hover:underline">
      ← Back to documents
    </a>
  </div>

  <div class="flex items-start justify-between mb-6">
    <div>
      <h1 class="text-2xl font-semibold"><%= @document.title %></h1>
      <p class="text-sm text-slate-500 mt-1">
        v<%= @document.current_version %> ·
        <span class={"rounded px-2 py-0.5 text-xs font-medium #{status_badge_class(@document.status)}"}>
          <%= @document.status %>
        </span>
      </p>
    </div>

    <div class="flex gap-2">
      <%= if @document.status == "draft" do %>
        <a href={~p"/sections/#{@section_key}/documents/#{@document.id}/edit"}
           class="rounded border px-3 py-1 text-sm">Edit</a>
        <form method="post" action={~p"/sections/#{@section_key}/documents/#{@document.id}/submit"}>
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button class="rounded bg-blue-600 text-white px-3 py-1 text-sm">Submit for review</button>
        </form>
      <% end %>
      <%= if @document.status == "in_review" do %>
        <form method="post" action={~p"/sections/#{@section_key}/documents/#{@document.id}/reject"}>
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button class="rounded border px-3 py-1 text-sm">Reject</button>
        </form>
        <form method="post" action={~p"/sections/#{@section_key}/documents/#{@document.id}/approve"}>
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button class="rounded bg-green-600 text-white px-3 py-1 text-sm">Approve</button>
        </form>
      <% end %>
      <%= if @document.status == "approved" do %>
        <form method="post" action={~p"/sections/#{@section_key}/documents/#{@document.id}/archive"}>
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button class="rounded border px-3 py-1 text-sm text-slate-600">Archive</button>
        </form>
      <% end %>
    </div>
  </div>

  <div class="prose max-w-none mb-8 border rounded p-4 bg-white">
    <%= if @document.body_html && @document.body_html != "" do %>
      <%= Phoenix.HTML.raw(@document.body_html) %>
    <% else %>
      <p class="text-slate-400 italic">No content yet.</p>
    <% end %>
  </div>

  <section class="mt-8">
    <h2 class="text-sm font-semibold text-slate-700 mb-2">Version history</h2>
    <table class="w-full text-sm border">
      <thead class="bg-slate-50">
        <tr>
          <th class="p-2 text-left">Version</th>
          <th class="p-2 text-left">Title</th>
          <th class="p-2 text-left">Saved at</th>
        </tr>
      </thead>
      <tbody>
        <%= for v <- @versions do %>
          <tr class="border-t">
            <td class="p-2">v<%= v.version %></td>
            <td class="p-2"><%= v.title %></td>
            <td class="p-2"><%= Calendar.strftime(v.saved_at, "%Y-%m-%d %H:%M:%S") %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </section>
</main>
```

- [ ] **Step 4: Create the new template**

```heex
<%# lib/atrium_web/controllers/document_html/new.html.heex %>
<main class="p-8 max-w-3xl">
  <div class="mb-4">
    <a href={~p"/sections/#{@section_key}/documents"} class="text-sm text-slate-500 hover:underline">
      ← Back to documents
    </a>
  </div>

  <h1 class="text-xl font-semibold mb-6">New document</h1>

  <.form :let={f} for={@changeset} action={~p"/sections/#{@section_key}/documents"} method="post">
    <div class="mb-4">
      <label class="block text-sm font-medium mb-1">Title</label>
      <.input field={f[:title]} type="text" class="w-full border rounded p-2" />
    </div>

    <div class="mb-4">
      <label class="block text-sm font-medium mb-1">Body</label>
      <div id="trix-container">
        <input type="hidden" id="document_body_html" name="document[body_html]" value={Phoenix.HTML.Form.input_value(f, :body_html) || ""} />
        <trix-editor input="document_body_html" class="border rounded min-h-48 p-2"></trix-editor>
      </div>
    </div>

    <div class="flex gap-2">
      <button type="submit" class="rounded bg-slate-900 text-white px-4 py-2">Save draft</button>
      <a href={~p"/sections/#{@section_key}/documents"} class="rounded border px-4 py-2">Cancel</a>
    </div>
  </.form>
</main>
```

- [ ] **Step 5: Create the edit template**

```heex
<%# lib/atrium_web/controllers/document_html/edit.html.heex %>
<main class="p-8 max-w-3xl">
  <div class="mb-4">
    <a href={~p"/sections/#{@section_key}/documents/#{@document.id}"} class="text-sm text-slate-500 hover:underline">
      ← Back to document
    </a>
  </div>

  <h1 class="text-xl font-semibold mb-6">Edit: <%= @document.title %></h1>

  <.form :let={f} for={@changeset} action={~p"/sections/#{@section_key}/documents/#{@document.id}"} method="post">
    <input type="hidden" name="_method" value="put" />

    <div class="mb-4">
      <label class="block text-sm font-medium mb-1">Title</label>
      <.input field={f[:title]} type="text" class="w-full border rounded p-2" />
    </div>

    <div class="mb-4">
      <label class="block text-sm font-medium mb-1">Body</label>
      <div id="trix-container">
        <input type="hidden" id="document_body_html" name="document[body_html]" value={Phoenix.HTML.Form.input_value(f, :body_html) || ""} />
        <trix-editor input="document_body_html" class="border rounded min-h-48 p-2"></trix-editor>
      </div>
    </div>

    <div class="flex gap-2">
      <button type="submit" class="rounded bg-slate-900 text-white px-4 py-2">Save changes</button>
      <a href={~p"/sections/#{@section_key}/documents/#{@document.id}"} class="rounded border px-4 py-2">Cancel</a>
    </div>
  </.form>
</main>
```

- [ ] **Step 6: Run all controller tests**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium_web/controllers/document_controller_test.exs 2>&1 | tail -30
```
Expected: All tests pass.

- [ ] **Step 7: Run full test suite to catch regressions**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test 2>&1 | tail -10
```
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/atrium_web/controllers/document_html.ex \
        lib/atrium_web/controllers/document_html/
git commit -m "feat(phase-1a): add HEEx templates with Trix editor island"
```

---

## Task 7: Milestone Tag

**Files:** none (git tag only)

- [ ] **Step 1: Run full test suite one final time**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test 2>&1 | tail -5
```
Expected: All tests pass with no failures.

- [ ] **Step 2: Tag the milestone**

```bash
cd /Users/marcinwalczak/Kod/atrium
git tag phase-1a-complete
```

- [ ] **Step 3: Verify tag exists**

```bash
git tag | grep phase-1a
```
Expected: `phase-1a-complete`
