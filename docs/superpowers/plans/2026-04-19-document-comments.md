# Document Commenting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users with `:view` access to a document to leave threaded comments on it. Editors and the comment author can delete comments. Comments appear below the document sheet on the show page.

**Architecture:** New tenant-scoped `document_comments` table. `Atrium.Documents.Comment` Ecto schema. New functions in `Atrium.Documents` context: `list_comments/2`, `add_comment/3`, `delete_comment/3`. Two new controller actions on `DocumentController`: `create_comment/2` and `delete_comment/2`. Comments rendered in `show.html.heex` below the doc sheet, above version history. No LiveView — plain form POST + redirect.

**Tech Stack:** Phoenix 1.8, Ecto, PostgreSQL (Triplex tenant prefix via `priv/repo/tenant_migrations/`), `atrium-*` CSS, no LiveView, no Tailwind.

---

## File Structure

**New files:**
- `priv/repo/tenant_migrations/20260419000006_create_document_comments.exs`
- `lib/atrium/documents/comment.ex`
- `test/atrium/documents/comment_test.exs`

**Modified files:**
- `lib/atrium/documents.ex` — add `list_comments/2`, `add_comment/3`, `delete_comment/3`
- `lib/atrium_web/controllers/document_controller.ex` — add `create_comment/2`, `delete_comment/2` actions + plug entries
- `lib/atrium_web/controllers/document_html/show.html.heex` — add comments section below doc sheet
- `lib/atrium_web/router.ex` — add `POST /sections/:section_key/documents/:id/comments` and `POST /sections/:section_key/documents/:id/comments/:cid/delete`

---

## Task 1: Migration + Schema + Context functions

**Files:**
- Create: `priv/repo/tenant_migrations/20260419000006_create_document_comments.exs`
- Create: `lib/atrium/documents/comment.ex`
- Modify: `lib/atrium/documents.ex`
- Create: `test/atrium/documents/comment_test.exs`

### Schema

```
document_comments
  id            :binary_id PK
  document_id   :binary_id NOT NULL FK documents (on_delete: :delete_all)
  author_id     :binary_id NOT NULL
  body          :text NOT NULL
  inserted_at   :utc_datetime_usec
  updated_at    :utc_datetime_usec
```

- [ ] **Step 1: Write the failing migration test**

```elixir
# test/atrium/documents/comment_test.exs
defmodule Atrium.Documents.CommentTest do
  use Atrium.TenantCase, async: false

  alias Atrium.Documents
  alias Atrium.Documents.Comment

  test "add_comment/3 creates a comment", %{prefix: prefix, user: user} do
    {:ok, doc} = Documents.create_document(prefix, %{
      "title" => "Test Doc",
      "section_key" => "docs",
      "body_html" => ""
    }, user)

    {:ok, comment} = Documents.add_comment(prefix, doc.id, %{
      body: "Nice doc",
      author_id: user.id
    })

    assert comment.body == "Nice doc"
    assert comment.author_id == user.id
    assert comment.document_id == doc.id
  end

  test "list_comments/2 returns comments for a document ordered oldest first", %{prefix: prefix, user: user} do
    {:ok, doc} = Documents.create_document(prefix, %{
      "title" => "Test Doc",
      "section_key" => "docs",
      "body_html" => ""
    }, user)

    {:ok, _} = Documents.add_comment(prefix, doc.id, %{body: "First", author_id: user.id})
    {:ok, _} = Documents.add_comment(prefix, doc.id, %{body: "Second", author_id: user.id})

    comments = Documents.list_comments(prefix, doc.id)
    assert length(comments) == 2
    assert hd(comments).body == "First"
  end

  test "delete_comment/2 removes a comment", %{prefix: prefix, user: user} do
    {:ok, doc} = Documents.create_document(prefix, %{
      "title" => "Test Doc",
      "section_key" => "docs",
      "body_html" => ""
    }, user)

    {:ok, comment} = Documents.add_comment(prefix, doc.id, %{body: "Delete me", author_id: user.id})
    assert :ok = Documents.delete_comment(prefix, comment.id)
    assert Documents.list_comments(prefix, doc.id) == []
  end

  test "add_comment/3 requires body", %{prefix: prefix, user: user} do
    {:ok, doc} = Documents.create_document(prefix, %{
      "title" => "Test Doc",
      "section_key" => "docs",
      "body_html" => ""
    }, user)

    assert {:error, changeset} = Documents.add_comment(prefix, doc.id, %{body: "", author_id: user.id})
    assert changeset.errors[:body]
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/atrium/documents/comment_test.exs
```

Expected: compilation error (Comment module doesn't exist yet)

- [ ] **Step 3: Write the migration**

```elixir
# priv/repo/tenant_migrations/20260419000006_create_document_comments.exs
defmodule Atrium.Repo.TenantMigrations.CreateDocumentComments do
  use Ecto.Migration

  def change do
    create table(:document_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, :binary_id, null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:document_comments, [:document_id])
  end
end
```

- [ ] **Step 4: Write the Comment schema**

```elixir
# lib/atrium/documents/comment.ex
defmodule Atrium.Documents.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "document_comments" do
    field :document_id, :binary_id
    field :author_id, :binary_id
    field :body, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:document_id, :author_id, :body])
    |> validate_required([:document_id, :author_id, :body])
    |> validate_length(:body, min: 1, max: 4000)
  end
end
```

- [ ] **Step 5: Add context functions to `lib/atrium/documents.ex`**

Add these functions at the end of the module (before the last `end`):

```elixir
alias Atrium.Documents.Comment

def list_comments(prefix, document_id) do
  Repo.all(
    from(c in Comment,
      where: c.document_id == ^document_id,
      order_by: [asc: c.inserted_at]
    ),
    prefix: prefix
  )
end

def add_comment(prefix, document_id, attrs) do
  attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  attrs = Map.put(attrs, "document_id", document_id)

  %Comment{}
  |> Comment.changeset(attrs)
  |> Repo.insert(prefix: prefix)
end

def delete_comment(prefix, comment_id) do
  case Repo.get(Comment, comment_id, prefix: prefix) do
    nil -> :ok
    comment ->
      case Repo.delete(comment, prefix: prefix) do
        {:ok, _} -> :ok
        {:error, _} = err -> err
      end
  end
end
```

- [ ] **Step 6: Run tenant migrations**

```bash
mix triplex.migrate
```

Expected: migration applied successfully

- [ ] **Step 7: Run tests**

```bash
mix test test/atrium/documents/comment_test.exs
```

Expected: 4 tests, 0 failures

- [ ] **Step 8: Commit**

```bash
git add priv/repo/tenant_migrations/20260419000006_create_document_comments.exs \
        lib/atrium/documents/comment.ex \
        lib/atrium/documents.ex \
        test/atrium/documents/comment_test.exs
git commit -m "feat: add document_comments table, schema, and context functions"
```

---

## Task 2: Controller actions + routes + template

**Files:**
- Modify: `lib/atrium_web/controllers/document_controller.ex`
- Modify: `lib/atrium_web/router.ex`
- Modify: `lib/atrium_web/controllers/document_html/show.html.heex`
- Create: `test/atrium_web/controllers/document_comments_test.exs`

### Routes to add (inside the `pipe_through [:authenticated]` scope, after existing document routes)

```elixir
post "/sections/:section_key/documents/:id/comments",             DocumentController, :create_comment
post "/sections/:section_key/documents/:id/comments/:cid/delete", DocumentController, :delete_comment
```

### Controller actions

**Plug addition** — add to the existing plug block (`:view` for create_comment; `:view` for delete_comment since author check is in action):

```elixir
plug AtriumWeb.Plugs.Authorize,
     [capability: :view, target: &__MODULE__.section_target/1]
     when action in [:create_comment, :delete_comment]
```

**Actions:**

```elixir
def create_comment(conn, %{"section_key" => section_key, "id" => id, "comment" => %{"body" => body}}) do
  prefix = conn.assigns.tenant_prefix
  user = conn.assigns.current_user

  case Documents.add_comment(prefix, id, %{body: body, author_id: user.id}) do
    {:ok, _} ->
      conn
      |> put_flash(:info, "Comment added.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}#comments")
    {:error, _changeset} ->
      conn
      |> put_flash(:error, "Comment cannot be blank.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}#comments")
  end
end

def delete_comment(conn, %{"section_key" => section_key, "id" => id, "cid" => cid}) do
  prefix = conn.assigns.tenant_prefix
  user = conn.assigns.current_user
  can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, section_key})

  comment = Atrium.Repo.get(Atrium.Documents.Comment, cid, prefix: prefix)

  cond do
    is_nil(comment) ->
      conn |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}#comments")
    can_edit || comment.author_id == user.id ->
      Documents.delete_comment(prefix, cid)
      conn
      |> put_flash(:info, "Comment deleted.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}#comments")
    true ->
      conn
      |> put_flash(:error, "Not authorised.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}#comments")
  end
end
```

**Also update `show/2`** to assign `@comments` and `@can_edit`:

```elixir
def show(conn, %{"section_key" => section_key, "id" => id}) do
  prefix = conn.assigns.tenant_prefix
  user = conn.assigns.current_user
  doc = Documents.get_document!(prefix, id)
  versions = Documents.list_versions(prefix, doc.id)
  history = Atrium.Audit.history_for(prefix, "Document", doc.id)
  comments = Documents.list_comments(prefix, doc.id)
  can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, section_key})
  render(conn, :show,
    document: doc,
    versions: versions,
    history: history,
    comments: comments,
    can_edit: can_edit,
    section_key: section_key,
    current_user: user
  )
end
```

### Comments section in `show.html.heex`

Insert this block inside `.doc-meta-panel`, **before** the version history card:

```heex
<%# Comments %>
<div id="comments" class="atrium-card" style="margin-bottom:12px">
  <div class="atrium-card-header">
    <span class="atrium-card-title">Comments</span>
    <span style="font-size:.8125rem;color:var(--text-tertiary)"><%= length(@comments) %></span>
  </div>
  <%= if @comments == [] do %>
    <div style="padding:24px;text-align:center;color:var(--text-tertiary);font-size:.875rem">No comments yet.</div>
  <% end %>
  <%= for comment <- @comments do %>
    <div style="padding:14px 16px;border-bottom:1px solid var(--border);display:flex;gap:12px;align-items:flex-start">
      <div style="width:28px;height:28px;border-radius:50%;background:var(--blue-100);display:flex;align-items:center;justify-content:center;font-size:.75rem;font-weight:600;color:var(--blue-600);flex-shrink:0">
        <%= String.first(String.upcase("?")) %>
      </div>
      <div style="flex:1;min-width:0">
        <div style="font-size:.8125rem;color:var(--text-tertiary);margin-bottom:4px">
          <%= Calendar.strftime(comment.inserted_at, "%d %b %Y %H:%M") %>
        </div>
        <div style="font-size:.875rem;color:var(--text-primary);white-space:pre-wrap"><%= comment.body %></div>
      </div>
      <%= if @can_edit || comment.author_id == @current_user.id do %>
        <form method="post" action={~p"/sections/#{@section_key}/documents/#{@document.id}/comments/#{comment.id}/delete"} style="flex-shrink:0">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button type="submit" style="background:none;border:none;cursor:pointer;color:var(--text-tertiary);padding:2px 4px;font-size:.75rem" title="Delete comment">✕</button>
        </form>
      <% end %>
    </div>
  <% end %>
  <div style="padding:14px 16px;border-top:1px solid var(--border)">
    <form method="post" action={~p"/sections/#{@section_key}/documents/#{@document.id}/comments"}>
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <textarea name="comment[body]" placeholder="Add a comment…" style="width:100%;border:1px solid var(--border);border-radius:var(--radius);padding:8px 10px;font-size:.875rem;resize:vertical;min-height:64px;font-family:inherit;color:var(--text-primary);background:var(--surface)" required></textarea>
      <div style="margin-top:8px;display:flex;justify-content:flex-end">
        <button type="submit" class="atrium-btn atrium-btn-primary" style="height:32px;font-size:.8125rem">Post comment</button>
      </div>
    </form>
  </div>
</div>
```

### Test

```elixir
# test/atrium_web/controllers/document_comments_test.exs
defmodule AtriumWeb.DocumentCommentsTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Learning, Accounts, Authorization, Tenants, Documents}
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "dc_#{:erlang.unique_integer([:positive])}"
    host = "#{slug}.atrium.example"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Doc Comments Test"})
    {:ok, _tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "dc_#{System.unique_integer([:positive])}@example.com",
      name: "DC User"
    })
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })

    Authorization.grant_section(prefix, "docs", {:user, user.id}, :view)

    conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: user.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    {:ok, doc} = Documents.create_document(prefix, %{
      "title" => "Test Doc",
      "section_key" => "docs",
      "body_html" => "<p>Hello</p>"
    }, user)

    {:ok, conn: conn, user: user, prefix: prefix, doc: doc}
  end

  test "POST /sections/docs/documents/:id/comments creates a comment", %{conn: conn, doc: doc} do
    conn = post(conn, "/sections/docs/documents/#{doc.id}/comments", %{"comment" => %{"body" => "Great doc!"}})
    assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
  end

  test "GET /sections/docs/documents/:id shows comments", %{conn: conn, doc: doc, prefix: prefix, user: user} do
    {:ok, _} = Documents.add_comment(prefix, doc.id, %{body: "Hello comment", author_id: user.id})
    conn = get(conn, "/sections/docs/documents/#{doc.id}")
    assert html_response(conn, 200) =~ "Hello comment"
  end

  test "POST delete comment removes it", %{conn: conn, doc: doc, prefix: prefix, user: user} do
    {:ok, comment} = Documents.add_comment(prefix, doc.id, %{body: "Delete me", author_id: user.id})
    conn = post(conn, "/sections/docs/documents/#{doc.id}/comments/#{comment.id}/delete")
    assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
    assert Documents.list_comments(prefix, doc.id) == []
  end
end
```

- [ ] **Step 1: Write failing controller test**

Write `test/atrium_web/controllers/document_comments_test.exs` as above.

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/atrium_web/controllers/document_comments_test.exs
```

Expected: compile error or route not found

- [ ] **Step 3: Add routes to `lib/atrium_web/router.ex`**

After the line `post "/sections/:section_key/documents/upload_image", DocumentController, :upload_image`:

```elixir
post "/sections/:section_key/documents/:id/comments",             DocumentController, :create_comment
post "/sections/:section_key/documents/:id/comments/:cid/delete", DocumentController, :delete_comment
```

- [ ] **Step 4: Add plug + actions to `lib/atrium_web/controllers/document_controller.ex`**

Add the plug entry and both actions as specified above. Update `show/2` to assign `@comments`, `@can_edit`, `@current_user`.

- [ ] **Step 5: Update `show.html.heex`**

Insert the comments card inside `.doc-meta-panel` before the version history card, as specified above.

- [ ] **Step 6: Run tests**

```bash
mix test test/atrium_web/controllers/document_comments_test.exs test/atrium/documents/comment_test.exs
```

Expected: 7 tests, 0 failures

- [ ] **Step 7: Commit**

```bash
git add lib/atrium_web/router.ex \
        lib/atrium_web/controllers/document_controller.ex \
        lib/atrium_web/controllers/document_html/show.html.heex \
        test/atrium_web/controllers/document_comments_test.exs
git commit -m "feat: add document commenting (create, delete, show in document view)"
```
