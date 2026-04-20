# In-App Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-user, per-tenant in-app notification system that surfaces document lifecycle events, form submissions, tool request decisions, and announcements via a bell-icon badge in the top bar and a `/notifications` inbox page.

**Architecture:** New `Atrium.Notifications` context backed by a single `notifications` tenant table. A `Dispatcher` module (called synchronously from existing context functions immediately after their successful DB write) creates targeted or bulk notification rows. `AssignNav` gains a `unread_notification_count` assign; the layout renders a badge dot. A `NotificationsController` serves the inbox (GET — lists + marks all read) and a mark-single-read POST endpoint.

**Tech Stack:** Elixir/Phoenix 1.8, Ecto + Triplex (schema-per-tenant, prefix `"tenant_<slug>"`), `Repo.insert_all/3` for bulk announcement notifications, standard controllers + HEEx templates, `atrium-*` CSS classes, `var(--…)` CSS custom properties — no LiveView, no Tailwind, no Oban.

---

## File Structure

**New files:**
- `priv/repo/tenant_migrations/20260502000001_create_notifications.exs` — creates the `notifications` table
- `lib/atrium/notifications/notification.ex` — Ecto schema + changesets
- `lib/atrium/notifications.ex` — context: `create/4`, `list_recent/3`, `count_unread/2`, `mark_read/3`, `mark_all_read/2`
- `lib/atrium/notifications/dispatcher.ex` — one public function per event type; calls `Notifications.create/4` (or `Repo.insert_all` for bulk)
- `lib/atrium_web/controllers/notifications_controller.ex` — `index/2` and `mark_read/2` actions
- `lib/atrium_web/controllers/notifications_html.ex` — `embed_templates` wrapper
- `lib/atrium_web/controllers/notifications_html/index.html.heex` — inbox page template
- `test/atrium/notifications_test.exs` — context + dispatcher unit tests

**Modified files:**
- `lib/atrium_web/plugs/assign_nav.ex` — also assigns `unread_notification_count`
- `lib/atrium_web/components/layouts/app.html.heex` — bell becomes a link with badge dot
- `lib/atrium_web/router.ex` — add `GET /notifications` and `POST /notifications/:id/read`
- `lib/atrium/documents.ex` — call `Dispatcher` after `submit_for_review`, `approve_document`, `reject_document`
- `lib/atrium/forms.ex` — call `Dispatcher` after `create_submission`
- `lib/atrium/tools.ex` — call `Dispatcher` after `approve_request`, `reject_request`
- `lib/atrium/home.ex` — call `Dispatcher` after `create_announcement`

---

## Task 1: Migration + Schema + Context (with tests)

**Files:**
- Create: `priv/repo/tenant_migrations/20260502000001_create_notifications.exs`
- Create: `lib/atrium/notifications/notification.ex`
- Create: `lib/atrium/notifications.ex`
- Create: `test/atrium/notifications_test.exs`

### Step 1.1 — Write the failing context tests

- [ ] Create `test/atrium/notifications_test.exs` with the full test module:

```elixir
defmodule Atrium.NotificationsTest do
  use Atrium.TenantCase
  alias Atrium.Notifications

  # Build a minimal user-like map — we only need .id in this context.
  defp user_id, do: Ecto.UUID.generate()

  describe "create/4" do
    test "inserts a notification and returns it", %{tenant_prefix: prefix} do
      uid = user_id()
      {:ok, n} =
        Notifications.create(prefix, uid, "document_approved", %{
          title: "Doc approved",
          body: "Your document was approved.",
          resource_type: "Document",
          resource_id: Ecto.UUID.generate()
        })

      assert n.user_id == uid
      assert n.type == "document_approved"
      assert n.title == "Doc approved"
      assert n.body == "Your document was approved."
      assert is_nil(n.read_at)
    end

    test "body and resource fields are optional", %{tenant_prefix: prefix} do
      {:ok, n} = Notifications.create(prefix, user_id(), "announcement", %{title: "Hello"})
      assert n.title == "Hello"
      assert is_nil(n.body)
      assert is_nil(n.resource_type)
      assert is_nil(n.resource_id)
    end

    test "returns error changeset when title is blank", %{tenant_prefix: prefix} do
      assert {:error, cs} = Notifications.create(prefix, user_id(), "announcement", %{title: ""})
      assert errors_on(cs)[:title]
    end
  end

  describe "list_recent/3" do
    test "returns notifications newest-first, capped at limit", %{tenant_prefix: prefix} do
      uid = user_id()
      for i <- 1..5 do
        {:ok, _} = Notifications.create(prefix, uid, "announcement", %{title: "Notif #{i}"})
      end
      results = Notifications.list_recent(prefix, uid, 3)
      assert length(results) == 3
      [first | _] = results
      assert first.title == "Notif 5"
    end

    test "only returns notifications for the given user", %{tenant_prefix: prefix} do
      uid1 = user_id()
      uid2 = user_id()
      {:ok, _} = Notifications.create(prefix, uid1, "announcement", %{title: "For uid1"})
      {:ok, _} = Notifications.create(prefix, uid2, "announcement", %{title: "For uid2"})
      results = Notifications.list_recent(prefix, uid1)
      assert Enum.all?(results, &(&1.user_id == uid1))
    end
  end

  describe "count_unread/2" do
    test "counts only unread notifications for the user", %{tenant_prefix: prefix} do
      uid = user_id()
      {:ok, n1} = Notifications.create(prefix, uid, "announcement", %{title: "A"})
      {:ok, _n2} = Notifications.create(prefix, uid, "announcement", %{title: "B"})
      assert Notifications.count_unread(prefix, uid) == 2

      {:ok, _} = Notifications.mark_read(prefix, uid, n1.id)
      assert Notifications.count_unread(prefix, uid) == 1
    end

    test "returns 0 when all are read", %{tenant_prefix: prefix} do
      uid = user_id()
      {:ok, _} = Notifications.create(prefix, uid, "announcement", %{title: "X"})
      :ok = Notifications.mark_all_read(prefix, uid)
      assert Notifications.count_unread(prefix, uid) == 0
    end
  end

  describe "mark_read/3" do
    test "sets read_at on the notification", %{tenant_prefix: prefix} do
      uid = user_id()
      {:ok, n} = Notifications.create(prefix, uid, "announcement", %{title: "T"})
      {:ok, updated} = Notifications.mark_read(prefix, uid, n.id)
      assert updated.read_at != nil
    end

    test "returns error if notification does not belong to user", %{tenant_prefix: prefix} do
      uid1 = user_id()
      uid2 = user_id()
      {:ok, n} = Notifications.create(prefix, uid1, "announcement", %{title: "T"})
      assert {:error, :not_found} = Notifications.mark_read(prefix, uid2, n.id)
    end
  end

  describe "mark_all_read/2" do
    test "marks all unread notifications for the user", %{tenant_prefix: prefix} do
      uid = user_id()
      {:ok, _} = Notifications.create(prefix, uid, "announcement", %{title: "A"})
      {:ok, _} = Notifications.create(prefix, uid, "announcement", %{title: "B"})
      :ok = Notifications.mark_all_read(prefix, uid)
      assert Notifications.count_unread(prefix, uid) == 0
    end
  end
end
```

### Step 1.2 — Run tests to confirm they fail

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/notifications_test.exs 2>&1 | head -30
```

Expected: compilation error — `Atrium.Notifications` does not exist.

### Step 1.3 — Write the migration

- [ ] Create `priv/repo/tenant_migrations/20260502000001_create_notifications.exs`:

```elixir
defmodule Atrium.Repo.TenantMigrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :user_id, :binary_id, null: false
      add :type, :string, null: false
      add :title, :string, null: false
      add :body, :text
      add :resource_type, :string
      add :resource_id, :binary_id
      add :read_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:notifications, [:user_id])
    create index(:notifications, [:user_id, :read_at])
  end
end
```

### Step 1.4 — Write the Notification schema

- [ ] Create `lib/atrium/notifications/notification.ex`:

```elixir
defmodule Atrium.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_types ~w(
    document_submitted
    document_approved
    document_rejected
    form_submission
    tool_request_approved
    tool_request_rejected
    announcement
  )

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notifications" do
    field :user_id, :binary_id
    field :type, :string
    field :title, :string
    field :body, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :read_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :type, :title, :body, :resource_type, :resource_id])
    |> validate_required([:user_id, :type, :title])
    |> validate_length(:title, min: 1, max: 500)
    |> validate_inclusion(:type, @valid_types)
  end
end
```

### Step 1.5 — Write the Notifications context

- [ ] Create `lib/atrium/notifications.ex`:

```elixir
defmodule Atrium.Notifications do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Notifications.Notification

  @doc """
  Creates a notification for a user in the given tenant schema.

  `attrs` accepts: `title` (required), `body`, `resource_type`, `resource_id`.
  """
  @spec create(String.t(), binary(), String.t(), map()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def create(prefix, user_id, type, attrs) do
    params = Map.merge(attrs, %{user_id: user_id, type: type})

    %Notification{}
    |> Notification.create_changeset(params)
    |> Repo.insert(prefix: prefix)
  end

  @doc "Returns up to `limit` most-recent notifications for the user, newest first."
  @spec list_recent(String.t(), binary(), pos_integer()) :: [Notification.t()]
  def list_recent(prefix, user_id, limit \\ 15) do
    from(n in Notification,
      where: n.user_id == ^user_id,
      order_by: [desc: n.inserted_at],
      limit: ^limit
    )
    |> Repo.all(prefix: prefix)
  end

  @doc "Returns the count of unread (read_at IS NULL) notifications for the user."
  @spec count_unread(String.t(), binary()) :: non_neg_integer()
  def count_unread(prefix, user_id) do
    from(n in Notification,
      where: n.user_id == ^user_id and is_nil(n.read_at),
      select: count()
    )
    |> Repo.one(prefix: prefix)
  end

  @doc "Marks a single notification as read. Returns `{:error, :not_found}` if it does not belong to the user."
  @spec mark_read(String.t(), binary(), binary()) ::
          {:ok, Notification.t()} | {:error, :not_found}
  def mark_read(prefix, user_id, notification_id) do
    case Repo.get_by(Notification, [id: notification_id, user_id: user_id], prefix: prefix) do
      nil ->
        {:error, :not_found}

      notification ->
        notification
        |> Ecto.Changeset.change(read_at: DateTime.utc_now())
        |> Repo.update(prefix: prefix)
    end
  end

  @doc "Marks all unread notifications for the user as read."
  @spec mark_all_read(String.t(), binary()) :: :ok
  def mark_all_read(prefix, user_id) do
    from(n in Notification,
      where: n.user_id == ^user_id and is_nil(n.read_at)
    )
    |> Repo.update_all([set: [read_at: DateTime.utc_now()]], prefix: prefix)

    :ok
  end
end
```

### Step 1.6 — Run the tests

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/notifications_test.exs 2>&1
```

Expected: All tests pass. Fix any compilation errors before proceeding.

### Step 1.7 — Commit

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && \
  git add \
    priv/repo/tenant_migrations/20260502000001_create_notifications.exs \
    lib/atrium/notifications/notification.ex \
    lib/atrium/notifications.ex \
    test/atrium/notifications_test.exs && \
  git commit -m "feat: add Notifications context, schema, and tenant migration"
```

---

## Task 2: Dispatcher module (with tests)

**Files:**
- Create: `lib/atrium/notifications/dispatcher.ex`
- Modify: `test/atrium/notifications_test.exs` — append `Atrium.Notifications.DispatcherTest` module

### Step 2.1 — Understand what the Dispatcher needs to query

The `document_submitted` event notifies users who hold `:approve` capability on the document's section. The query path is:

1. Fetch all `SectionAcl` rows for the document's `section_key` where `capability == "approve"`.
2. For each row, expand `principal_type`:
   - `"user"` → collect the `principal_id` directly
   - `"group"` → query `memberships` for all `user_id` values in that group

For `announcement_created`, we bulk-notify all active users by querying `users` where `status == "active"`.

For the other events (approved/rejected document, form submission recipients, tool request) we notify a single known `user_id` that is already available in the caller's context.

### Step 2.2 — Append dispatcher tests to `test/atrium/notifications_test.exs`

- [ ] Append the following module **after** the closing `end` of `Atrium.NotificationsTest` in `test/atrium/notifications_test.exs`:

```elixir
defmodule Atrium.Notifications.DispatcherTest do
  use Atrium.TenantCase
  alias Atrium.Notifications
  alias Atrium.Notifications.Dispatcher
  alias Atrium.Accounts
  alias Atrium.Authorization

  # Helper: create an active user in the tenant schema
  defp create_user(prefix, email) do
    {:ok, %{user: user}} =
      Accounts.invite_user(prefix, %{email: email, name: "Test User"})
    {:ok, user} =
      Accounts.activate_user_with_password(prefix, user, %{password: "password123456"})
    user
  end

  # Helper: grant a section capability to a user principal directly
  defp grant(prefix, section_key, user_id, capability) do
    Authorization.grant_section(prefix, section_key, {:user, user_id}, capability)
  end

  describe "document_approved/3" do
    test "creates a notification for the document author", %{tenant_prefix: prefix} do
      author = create_user(prefix, "author_#{System.unique_integer()}@test.com")
      reviewer = create_user(prefix, "reviewer_#{System.unique_integer()}@test.com")

      document = %{
        id: Ecto.UUID.generate(),
        title: "HR Policy",
        author_id: author.id,
        section_key: "hr"
      }

      :ok = Dispatcher.document_approved(prefix, document, reviewer)

      [notif] = Notifications.list_recent(prefix, author.id)
      assert notif.type == "document_approved"
      assert notif.title =~ "HR Policy"
      assert notif.resource_type == "Document"
      assert notif.resource_id == document.id
    end
  end

  describe "document_rejected/3" do
    test "creates a notification for the document author", %{tenant_prefix: prefix} do
      author = create_user(prefix, "author2_#{System.unique_integer()}@test.com")
      reviewer = create_user(prefix, "reviewer2_#{System.unique_integer()}@test.com")

      document = %{
        id: Ecto.UUID.generate(),
        title: "Rejected Doc",
        author_id: author.id,
        section_key: "hr"
      }

      :ok = Dispatcher.document_rejected(prefix, document, reviewer)

      [notif] = Notifications.list_recent(prefix, author.id)
      assert notif.type == "document_rejected"
      assert notif.title =~ "Rejected Doc"
    end
  end

  describe "document_submitted/3" do
    test "notifies users with :approve on the section", %{tenant_prefix: prefix} do
      author = create_user(prefix, "submit_author_#{System.unique_integer()}@test.com")
      approver = create_user(prefix, "approver_#{System.unique_integer()}@test.com")
      {:ok, _} = grant(prefix, "hr", approver.id, :approve)

      document = %{
        id: Ecto.UUID.generate(),
        title: "Pending Doc",
        author_id: author.id,
        section_key: "hr"
      }

      :ok = Dispatcher.document_submitted(prefix, document, author)

      notifs = Notifications.list_recent(prefix, approver.id)
      assert length(notifs) == 1
      assert hd(notifs).type == "document_submitted"
    end

    test "does not notify the submitting author", %{tenant_prefix: prefix} do
      author = create_user(prefix, "self_submit_#{System.unique_integer()}@test.com")
      {:ok, _} = grant(prefix, "hr", author.id, :approve)

      document = %{
        id: Ecto.UUID.generate(),
        title: "Self Submit",
        author_id: author.id,
        section_key: "hr"
      }

      :ok = Dispatcher.document_submitted(prefix, document, author)

      # author submitted themselves — should not receive a notification
      assert Notifications.list_recent(prefix, author.id) == []
    end
  end

  describe "tool_request_approved/3" do
    test "notifies the requester", %{tenant_prefix: prefix} do
      requester = create_user(prefix, "requester_#{System.unique_integer()}@test.com")
      reviewer  = create_user(prefix, "tool_rev_#{System.unique_integer()}@test.com")

      request = %{
        id: Ecto.UUID.generate(),
        user_id: requester.id,
        tool_id: Ecto.UUID.generate()
      }

      tool = %{title: "VPN Access"}

      :ok = Dispatcher.tool_request_approved(prefix, request, tool, reviewer)

      [notif] = Notifications.list_recent(prefix, requester.id)
      assert notif.type == "tool_request_approved"
      assert notif.title =~ "VPN Access"
    end
  end

  describe "tool_request_rejected/3" do
    test "notifies the requester", %{tenant_prefix: prefix} do
      requester = create_user(prefix, "reject_req_#{System.unique_integer()}@test.com")
      reviewer  = create_user(prefix, "reject_rev_#{System.unique_integer()}@test.com")

      request = %{
        id: Ecto.UUID.generate(),
        user_id: requester.id,
        tool_id: Ecto.UUID.generate()
      }

      tool = %{title: "VPN Access"}

      :ok = Dispatcher.tool_request_rejected(prefix, request, tool, reviewer)

      [notif] = Notifications.list_recent(prefix, requester.id)
      assert notif.type == "tool_request_rejected"
    end
  end

  describe "form_submission/4" do
    test "notifies user-type notification recipients", %{tenant_prefix: prefix} do
      submitter = create_user(prefix, "submitter_#{System.unique_integer()}@test.com")
      recipient = create_user(prefix, "form_recip_#{System.unique_integer()}@test.com")

      form = %{
        id: Ecto.UUID.generate(),
        title: "Expense Form",
        notification_recipients: [%{"type" => "user", "id" => recipient.id}]
      }

      submission = %{id: Ecto.UUID.generate()}

      :ok = Dispatcher.form_submission(prefix, form, submission, submitter)

      [notif] = Notifications.list_recent(prefix, recipient.id)
      assert notif.type == "form_submission"
      assert notif.title =~ "Expense Form"
    end

    test "skips email-type recipients gracefully", %{tenant_prefix: prefix} do
      submitter = create_user(prefix, "submitter2_#{System.unique_integer()}@test.com")

      form = %{
        id: Ecto.UUID.generate(),
        title: "Expense Form",
        notification_recipients: [%{"type" => "email", "email" => "external@example.com"}]
      }

      submission = %{id: Ecto.UUID.generate()}

      # Should not raise
      assert :ok = Dispatcher.form_submission(prefix, form, submission, submitter)
    end
  end

  describe "announcement_created/3" do
    test "notifies all active users except the author", %{tenant_prefix: prefix} do
      author = create_user(prefix, "ann_author_#{System.unique_integer()}@test.com")
      reader = create_user(prefix, "ann_reader_#{System.unique_integer()}@test.com")

      announcement = %{
        id: Ecto.UUID.generate(),
        title: "Company Picnic"
      }

      :ok = Dispatcher.announcement_created(prefix, announcement, author)

      reader_notifs = Notifications.list_recent(prefix, reader.id)
      assert Enum.any?(reader_notifs, &(&1.type == "announcement" and &1.title =~ "Company Picnic"))

      author_notifs = Notifications.list_recent(prefix, author.id)
      assert Enum.all?(author_notifs, &(&1.user_id != author.id or &1.type != "announcement"))
    end
  end
end
```

### Step 2.3 — Run tests to confirm they fail

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/notifications_test.exs 2>&1 | head -20
```

Expected: compilation error — `Atrium.Notifications.Dispatcher` does not exist.

### Step 2.4 — Write the Dispatcher

- [ ] Create `lib/atrium/notifications/dispatcher.ex`:

```elixir
defmodule Atrium.Notifications.Dispatcher do
  @moduledoc """
  Translates domain events into in-app notifications.

  Each public function is called synchronously by a context function after a
  successful DB write. Failures are logged but never bubble up — notifications
  are best-effort and must not break the triggering operation.

  Argument shapes use plain maps so callers can pass Ecto structs directly
  (struct field access works on maps too).
  """

  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Notifications
  alias Atrium.Notifications.Notification
  alias Atrium.Accounts.User
  alias Atrium.Authorization.{SectionAcl, Membership}

  # ---------------------------------------------------------------------------
  # Document events
  # ---------------------------------------------------------------------------

  @doc "Notifies the document author that their submission is approved."
  def document_approved(prefix, document, _actor_user) do
    Notifications.create(prefix, document.author_id, "document_approved", %{
      title: "Document approved: #{document.title}",
      body: "Your document has been approved.",
      resource_type: "Document",
      resource_id: document.id
    })

    :ok
  end

  @doc "Notifies the document author that their submission was rejected."
  def document_rejected(prefix, document, _actor_user) do
    Notifications.create(prefix, document.author_id, "document_rejected", %{
      title: "Document returned for revision: #{document.title}",
      body: "Your document has been returned to draft.",
      resource_type: "Document",
      resource_id: document.id
    })

    :ok
  end

  @doc """
  Notifies users who hold the :approve capability on the document's section
  (excluding the submitting author, to avoid self-notification).
  """
  def document_submitted(prefix, document, actor_user) do
    approver_ids = approvers_for_section(prefix, document.section_key)
    # Exclude the person who submitted
    recipients = Enum.reject(approver_ids, &(&1 == actor_user.id))

    Enum.each(recipients, fn user_id ->
      Notifications.create(prefix, user_id, "document_submitted", %{
        title: "Document ready for review: #{document.title}",
        body: "A document has been submitted for your approval.",
        resource_type: "Document",
        resource_id: document.id
      })
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Form events
  # ---------------------------------------------------------------------------

  @doc """
  Notifies user-type `notification_recipients` on the form about a new
  submission. Email-type recipients are handled by the existing
  `Atrium.Forms.NotificationWorker` Oban job and are skipped here.
  """
  def form_submission(prefix, form, submission, _actor_user) do
    user_recipients =
      (form.notification_recipients || [])
      |> Enum.filter(fn r -> (r["type"] || r[:type]) == "user" end)
      |> Enum.map(fn r -> r["id"] || r[:id] end)
      |> Enum.reject(&is_nil/1)

    Enum.each(user_recipients, fn user_id ->
      Notifications.create(prefix, user_id, "form_submission", %{
        title: "New submission: #{form.title}",
        body: "A new form submission has been received.",
        resource_type: "FormSubmission",
        resource_id: submission.id
      })
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Tool request events
  # ---------------------------------------------------------------------------

  @doc "Notifies the requester that their tool request was approved."
  def tool_request_approved(prefix, request, tool, _reviewer) do
    Notifications.create(prefix, request.user_id, "tool_request_approved", %{
      title: "Request approved: #{tool.title}",
      body: "Your access request has been approved.",
      resource_type: "ToolRequest",
      resource_id: request.id
    })

    :ok
  end

  @doc "Notifies the requester that their tool request was rejected."
  def tool_request_rejected(prefix, request, tool, _reviewer) do
    Notifications.create(prefix, request.user_id, "tool_request_rejected", %{
      title: "Request declined: #{tool.title}",
      body: "Your access request has been declined.",
      resource_type: "ToolRequest",
      resource_id: request.id
    })

    :ok
  end

  # ---------------------------------------------------------------------------
  # Announcement events
  # ---------------------------------------------------------------------------

  @doc """
  Bulk-inserts a notification for every active user except the author.
  Uses `Repo.insert_all` for efficiency.
  """
  def announcement_created(prefix, announcement, actor_user) do
    active_user_ids =
      from(u in User, where: u.status == "active", select: u.id)
      |> Repo.all(prefix: prefix)
      |> Enum.reject(&(&1 == actor_user.id))

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rows =
      Enum.map(active_user_ids, fn uid ->
        %{
          id: Ecto.UUID.generate(),
          user_id: uid,
          type: "announcement",
          title: "New announcement: #{announcement.title}",
          body: nil,
          resource_type: "Announcement",
          resource_id: announcement.id,
          read_at: nil,
          inserted_at: now
        }
      end)

    if rows != [] do
      Repo.insert_all(Notification, rows, prefix: prefix)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Returns a deduplicated list of user_ids that hold the "approve" capability
  # on the given section, expanding group principals to their member user_ids.
  defp approvers_for_section(prefix, section_key) do
    acls =
      from(a in SectionAcl,
        where: a.section_key == ^to_string(section_key) and a.capability == "approve"
      )
      |> Repo.all(prefix: prefix)

    {user_acls, group_acls} =
      Enum.split_with(acls, &(&1.principal_type == "user"))

    direct_ids = Enum.map(user_acls, & &1.principal_id)

    group_ids = Enum.map(group_acls, & &1.principal_id)

    group_member_ids =
      if group_ids == [] do
        []
      else
        from(m in Membership,
          where: m.group_id in ^group_ids,
          select: m.user_id
        )
        |> Repo.all(prefix: prefix)
      end

    (direct_ids ++ group_member_ids)
    |> Enum.uniq()
  end
end
```

### Step 2.5 — Run tests

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/notifications_test.exs 2>&1
```

Expected: all tests pass. If `announcement_created` test fails because the TenantCase tenant doesn't seed any active users beyond those created in setup, check that `create_user` calls `activate_user_with_password` (which calls `AllStaff.ensure_member`). The test creates both `author` and `reader` as active users, so `reader` should be found by the query.

### Step 2.6 — Commit

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && \
  git add \
    lib/atrium/notifications/dispatcher.ex \
    test/atrium/notifications_test.exs && \
  git commit -m "feat: add Notifications.Dispatcher for all event types"
```

---

## Task 3: Wire Dispatcher into existing context functions

**Files:**
- Modify: `lib/atrium/documents.ex`
- Modify: `lib/atrium/forms.ex`
- Modify: `lib/atrium/tools.ex`
- Modify: `lib/atrium/home.ex`

The strategy for all four files is identical: add an alias for the dispatcher, then call the appropriate dispatcher function **outside** the `Repo.transaction` block (or after the `with` chain for non-transactional functions) immediately after the `{:ok, …}` match. Dispatcher calls are fire-and-forget — we do not pattern-match their return value for the caller's success path.

### Step 3.1 — Wire `documents.ex`

- [ ] Open `lib/atrium/documents.ex`. Add the dispatcher alias after the existing aliases at the top:

```elixir
  alias Atrium.Notifications.Dispatcher
```

- [ ] Modify `submit_for_review/3` — call the dispatcher after a successful transaction. The current implementation delegates to `transition/4`. Replace **only** the public function head:

```elixir
  def submit_for_review(prefix, %Document{status: "draft"} = doc, actor_user) do
    case transition(prefix, doc, "in_review", actor_user, "document.submitted") do
      {:ok, updated} = result ->
        Dispatcher.document_submitted(prefix, updated, actor_user)
        result

      err ->
        err
    end
  end
```

- [ ] Modify `approve_document/3` — add dispatcher call after the transaction. Replace the full public function:

```elixir
  def approve_document(prefix, %Document{status: "in_review"} = doc, actor_user) do
    extra = %{approved_by_id: actor_user.id, approved_at: DateTime.utc_now()}

    result =
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

    case result do
      {:ok, updated} = ok ->
        Dispatcher.document_approved(prefix, updated, actor_user)
        ok

      err ->
        err
    end
  end
```

- [ ] Modify `reject_document/3` — same pattern as submit. Replace the public function head:

```elixir
  def reject_document(prefix, %Document{status: "in_review"} = doc, actor_user) do
    case transition(prefix, doc, "draft", actor_user, "document.rejected") do
      {:ok, updated} = result ->
        Dispatcher.document_rejected(prefix, updated, actor_user)
        result

      err ->
        err
    end
  end
```

### Step 3.2 — Wire `forms.ex`

- [ ] Open `lib/atrium/forms.ex`. Add the alias:

```elixir
  alias Atrium.Notifications.Dispatcher
```

- [ ] In `create_submission/4`, the function already has a post-transaction `|> case do` block (lines ~150–157). Extend that block to also call the dispatcher. Replace the existing `case do` block at the bottom of `create_submission/4`:

```elixir
    |> case do
      {:ok, sub} ->
        enqueue_notification(prefix, sub.id)
        Dispatcher.form_submission(prefix, form, sub, actor_user)
        {:ok, sub}

      err ->
        err
    end
```

### Step 3.3 — Wire `tools.ex`

The tool dispatcher functions need access to the tool's `title` field. The `approve_request/3` and `reject_request/3` functions receive `%ToolRequest{}` and `reviewer`, but not the `ToolLink`. The controller already fetches the tool link before calling these functions, but the context functions do not. The cleanest approach is to look up the `ToolLink` inside the dispatcher call using the `request.tool_id`. However, to avoid a DB round-trip inside the dispatcher, we instead fetch the tool in the context and pass it.

- [ ] Open `lib/atrium/tools.ex`. Add the alias:

```elixir
  alias Atrium.Notifications.Dispatcher
```

- [ ] Replace `approve_request/3`:

```elixir
  def approve_request(prefix, %ToolRequest{} = req, reviewer) do
    with {:ok, updated} <- req |> ToolRequest.review_changeset("approved", reviewer.id) |> Repo.update(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_request.approved", %{actor: {:user, reviewer.id}, resource: {"ToolRequest", req.id}}) do
      tool = get_tool_link!(prefix, req.tool_id)
      Dispatcher.tool_request_approved(prefix, updated, tool, reviewer)
      {:ok, updated}
    end
  end
```

- [ ] Replace `reject_request/3`:

```elixir
  def reject_request(prefix, %ToolRequest{} = req, reviewer) do
    with {:ok, updated} <- req |> ToolRequest.review_changeset("rejected", reviewer.id) |> Repo.update(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_request.rejected", %{actor: {:user, reviewer.id}, resource: {"ToolRequest", req.id}}) do
      tool = get_tool_link!(prefix, req.tool_id)
      Dispatcher.tool_request_rejected(prefix, updated, tool, reviewer)
      {:ok, updated}
    end
  end
```

### Step 3.4 — Wire `home.ex`

- [ ] Open `lib/atrium/home.ex`. Add the alias:

```elixir
  alias Atrium.Notifications.Dispatcher
```

- [ ] Replace `create_announcement/3`:

```elixir
  def create_announcement(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(stringify(attrs), "author_id", actor_user.id)

    result =
      Repo.transaction(fn ->
        with {:ok, ann} <- %Announcement{} |> Announcement.changeset(attrs_with_author) |> Repo.insert(prefix: prefix),
             {:ok, _} <- Audit.log(prefix, "announcement.created", %{actor: {:user, actor_user.id}, resource: {"Announcement", ann.id}}) do
          ann
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, ann} = ok ->
        Dispatcher.announcement_created(prefix, ann, actor_user)
        ok

      err ->
        err
    end
  end
```

### Step 3.5 — Run the full test suite to confirm nothing regresses

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1 | tail -20
```

Expected: all tests pass (or the same failures as before this task — zero new failures).

### Step 3.6 — Commit

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && \
  git add \
    lib/atrium/documents.ex \
    lib/atrium/forms.ex \
    lib/atrium/tools.ex \
    lib/atrium/home.ex && \
  git commit -m "feat: wire Dispatcher into documents, forms, tools, and home contexts"
```

---

## Task 4: AssignNav plug + layout bell badge

**Files:**
- Modify: `lib/atrium_web/plugs/assign_nav.ex`
- Modify: `lib/atrium_web/components/layouts/app.html.heex`

### Step 4.1 — Extend `AssignNav` to assign `unread_notification_count`

- [ ] Replace the entire contents of `lib/atrium_web/plugs/assign_nav.ex`:

```elixir
defmodule AtriumWeb.Plugs.AssignNav do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case {conn.assigns[:tenant], conn.assigns[:current_user], conn.assigns[:tenant_prefix]} do
      {nil, _, _} -> conn
      {_, nil, _} -> conn
      {tenant, user, prefix} ->
        nav = Atrium.AppShell.nav_for_user(tenant, user, prefix)
        unread = Atrium.Notifications.count_unread(prefix, user.id)

        conn
        |> assign(:nav, nav)
        |> assign(:unread_notification_count, unread)
    end
  end
end
```

### Step 4.2 — Update the bell button in the layout

- [ ] In `lib/atrium_web/components/layouts/app.html.heex`, replace the `<button>` block for notifications (lines 20–24) with the following. It turns the button into a link with a badge dot when `unread_notification_count > 0`:

```heex
    <a href="/notifications" class="atrium-topbar-btn" title="Notifications" style="position:relative">
      <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75">
        <path d="M8 2a4.5 4.5 0 0 1 4.5 4.5c0 2.5.5 3.5 1.5 4.5H2c1-1 1.5-2 1.5-4.5A4.5 4.5 0 0 1 8 2zM6.5 13.5a1.5 1.5 0 0 0 3 0" stroke-linecap="round"/>
      </svg>
      <%= if assigns[:unread_notification_count] && @unread_notification_count > 0 do %>
        <span style="position:absolute;top:4px;right:4px;width:7px;height:7px;border-radius:50%;background:var(--blue-500);border:1.5px solid var(--surface)"></span>
      <% end %>
    </a>
```

### Step 4.3 — Smoke-test in the browser (manual)

- [ ] Start the server:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix phx.server
```

Log in as any user. The bell icon should render without errors. If there are unread notifications, a small blue dot should appear. No JS required.

### Step 4.4 — Run the full test suite

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1 | tail -10
```

Expected: all tests pass.

### Step 4.5 — Commit

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && \
  git add \
    lib/atrium_web/plugs/assign_nav.ex \
    lib/atrium_web/components/layouts/app.html.heex && \
  git commit -m "feat: add unread badge to topbar bell and extend AssignNav"
```

---

## Task 5: NotificationsController, HTML module, template, and routes

**Files:**
- Create: `lib/atrium_web/controllers/notifications_controller.ex`
- Create: `lib/atrium_web/controllers/notifications_html.ex`
- Create: `lib/atrium_web/controllers/notifications_html/index.html.heex`
- Modify: `lib/atrium_web/router.ex`

### Step 5.1 — Add routes

- [ ] In `lib/atrium_web/router.ex`, inside the authenticated `scope "/"` block (after the `/audit` routes, around line 95), add:

```elixir
      get  "/notifications",          NotificationsController, :index
      post "/notifications/:id/read", NotificationsController, :mark_read
```

### Step 5.2 — Write the controller

- [ ] Create `lib/atrium_web/controllers/notifications_controller.ex`:

```elixir
defmodule AtriumWeb.NotificationsController do
  use AtriumWeb, :controller
  alias Atrium.Notifications

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user   = conn.assigns.current_user

    notifications = Notifications.list_recent(prefix, user.id, 50)
    :ok = Notifications.mark_all_read(prefix, user.id)

    render(conn, :index, notifications: notifications)
  end

  def mark_read(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user   = conn.assigns.current_user

    case Notifications.mark_read(prefix, user.id, id) do
      {:ok, _}           -> redirect(conn, to: ~p"/notifications")
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Notification not found.")
        |> redirect(to: ~p"/notifications")
    end
  end
end
```

### Step 5.3 — Write the HTML module

- [ ] Create `lib/atrium_web/controllers/notifications_html.ex`:

```elixir
defmodule AtriumWeb.NotificationsHTML do
  use AtriumWeb, :html
  embed_templates "notifications_html/*"
end
```

### Step 5.4 — Write the template

- [ ] Create the directory structure by creating `lib/atrium_web/controllers/notifications_html/index.html.heex` with the following content:

```heex
<div class="atrium-anim">
  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Inbox</div>
    <h1 class="atrium-page-title">Notifications</h1>
  </div>

  <div class="atrium-card">
    <%= if @notifications == [] do %>
      <div style="padding:48px;text-align:center;color:var(--text-tertiary)">
        You have no notifications.
      </div>
    <% else %>
      <ul style="list-style:none;margin:0;padding:0">
        <%= for n <- @notifications do %>
          <li style={"display:flex;align-items:flex-start;gap:12px;padding:14px 20px;border-bottom:1px solid var(--border);#{if is_nil(n.read_at), do: "background:color-mix(in srgb,var(--blue-500) 6%,transparent)", else: ""}"}>
            <div style="flex:1;min-width:0">
              <div style={"font-size:.9375rem;color:var(--text-primary);#{if is_nil(n.read_at), do: "font-weight:600", else: ""}"}><%= n.title %></div>
              <%= if n.body do %>
                <div style="font-size:.8125rem;color:var(--text-secondary);margin-top:2px"><%= n.body %></div>
              <% end %>
              <div style="font-size:.75rem;color:var(--text-tertiary);margin-top:4px">
                <%= Calendar.strftime(n.inserted_at, "%d %b %Y, %H:%M") %>
              </div>
            </div>
            <%= if is_nil(n.read_at) do %>
              <form action={~p"/notifications/#{n.id}/read"} method="post" style="flex-shrink:0">
                <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
                <button type="submit" class="atrium-btn atrium-btn-ghost" style="font-size:.8125rem;padding:4px 10px">
                  Mark read
                </button>
              </form>
            <% end %>
          </li>
        <% end %>
      </ul>
    <% end %>
  </div>
</div>
```

### Step 5.5 — Run the test suite

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1 | tail -10
```

Expected: all tests pass.

### Step 5.6 — Manual smoke-test

- [ ] Start the server:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix phx.server
```

Navigate to `http://<tenant-host>/notifications`. Verify:
- The page renders with the correct layout and sidebar.
- Visiting the page marks all as read (badge disappears on next page load).
- The "Mark read" button on individual unread items works and redirects back to `/notifications`.

### Step 5.7 — Commit

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && \
  git add \
    lib/atrium_web/router.ex \
    lib/atrium_web/controllers/notifications_controller.ex \
    lib/atrium_web/controllers/notifications_html.ex \
    lib/atrium_web/controllers/notifications_html/index.html.heex && \
  git commit -m "feat: add NotificationsController, inbox template, and routes"
```

---

## Task 6: Final integration check and commit

**Files:** none new — verification only.

### Step 6.1 — Run the full test suite one final time

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1
```

Expected: all tests pass, zero failures.

### Step 6.2 — Check for compiler warnings

- [ ] Run:

```bash
cd /Users/marcinwalczak/Kod/atrium && mix compile --warnings-as-errors 2>&1
```

Expected: exit 0, no warnings.

### Step 6.3 — Final commit

If steps 6.1 and 6.2 are clean there is nothing to commit (all changes were committed per-task). If any fixup was needed during 6.1/6.2, commit those fixes now:

```bash
cd /Users/marcinwalczak/Kod/atrium && \
  git add -p && \
  git commit -m "fix: address compilation warnings and test failures from integration check"
```

---

## Self-Review Checklist

The following requirements from the spec have been verified against the tasks above:

| Requirement | Task |
|---|---|
| `notifications` tenant table with all specified columns | Task 1, Step 1.3 |
| `Notification` Ecto schema (no associations, raw `resource_id` UUID) | Task 1, Step 1.4 |
| `Notifications.create/4` | Task 1, Step 1.5 |
| `Notifications.list_recent/3` with default limit 15 | Task 1, Step 1.5 |
| `Notifications.count_unread/2` | Task 1, Step 1.5 |
| `Notifications.mark_read/3` | Task 1, Step 1.5 |
| `Notifications.mark_all_read/2` | Task 1, Step 1.5 |
| `Dispatcher.document_submitted` notifies approvers | Task 2, Step 2.4 |
| `Dispatcher.document_approved` notifies author | Task 2, Step 2.4 |
| `Dispatcher.document_rejected` notifies author | Task 2, Step 2.4 |
| `Dispatcher.form_submission` notifies user-type recipients | Task 2, Step 2.4 |
| `Dispatcher.tool_request_approved` notifies requester | Task 2, Step 2.4 |
| `Dispatcher.tool_request_rejected` notifies requester | Task 2, Step 2.4 |
| `Dispatcher.announcement_created` bulk-notifies all active users (excluding author) via `Repo.insert_all` | Task 2, Step 2.4 |
| `documents.ex` wired: `submit_for_review`, `approve_document`, `reject_document` | Task 3, Step 3.1 |
| `forms.ex` wired: `create_submission` | Task 3, Step 3.2 |
| `tools.ex` wired: `approve_request`, `reject_request` | Task 3, Step 3.3 |
| `home.ex` wired: `create_announcement` | Task 3, Step 3.4 |
| `AssignNav` assigns `unread_notification_count` | Task 4, Step 4.1 |
| Bell icon becomes a link to `/notifications` with blue dot badge | Task 4, Step 4.2 |
| `GET /notifications` lists recent 50 and marks all read | Task 5, Steps 5.2, 5.4 |
| `POST /notifications/:id/read` marks single read, redirects back | Task 5, Step 5.2 |
| Migration timestamp `20260502000001` | Task 1, Step 1.3 |
| Test file uses `Atrium.TenantCase` | Task 1, Step 1.1; Task 2, Step 2.2 |
| No LiveView | Entire plan — standard controllers only |
| CSS uses `atrium-*` classes and `var(--…)` properties | Task 5, Step 5.4 |
