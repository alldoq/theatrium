# Events & Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task ends with a commit — do not batch tasks into one commit. Run every `mix test` command listed and fix failures before moving on.

**Goal:** Implement a full Events & Calendar section for the Atrium intranet. Staff can browse a monthly grid calendar, view event details, and editors can create/edit/delete events. The section uses the existing `Authorize` plug pattern, Triplex schema-per-tenant, and the `Atrium.Audit` context.

**Architecture:**
- Ecto schema `Atrium.Events.Event` backed by a `events` table in each tenant schema.
- Context `Atrium.Events` with five public functions: `list_events_for_month/3`, `get_event!/2`, `create_event/3`, `update_event/4`, `delete_event/3`.
- `AtriumWeb.EventsController` with six actions: `index`, `show`, `new`, `create`, `edit`, `update`, `delete`.
- `AtriumWeb.EventsHTML` module embedding four templates: `index`, `show`, `new`, `edit`.
- The index page renders a month grid calendar (pure HTML/CSS/JS — no external library) plus an upcoming events list below it.
- Sidebar wired by adding `"events"` to the `dedicated` list in `app.html.heex` and adding routes to `router.ex`.

**Tech Stack:** Elixir/Phoenix 1.8, Ecto, PostgreSQL schema-per-tenant (Triplex prefix `"tenant_<slug>"`), server-rendered HEEx, `atrium-*` CSS design system, no LiveView, no Tailwind.

---

## File Map

**New files:**
- `priv/repo/tenant_migrations/20260502000002_create_events.exs`
- `lib/atrium/events/event.ex`
- `lib/atrium/events.ex`
- `lib/atrium_web/controllers/events_controller.ex`
- `lib/atrium_web/controllers/events_html.ex`
- `lib/atrium_web/controllers/events_html/index.html.heex`
- `lib/atrium_web/controllers/events_html/show.html.heex`
- `lib/atrium_web/controllers/events_html/new.html.heex`
- `lib/atrium_web/controllers/events_html/edit.html.heex`
- `test/atrium/events_test.exs`

**Modified files:**
- `lib/atrium_web/router.ex` — add events routes inside the authenticated scope
- `lib/atrium_web/components/layouts/app.html.heex` — add `"events"` to `dedicated` list

---

## Task 1: Migration + Event Schema + Events Context (with tests)

**Files:**
- Create: `priv/repo/tenant_migrations/20260502000002_create_events.exs`
- Create: `lib/atrium/events/event.ex`
- Create: `lib/atrium/events.ex`
- Create: `test/atrium/events_test.exs`

---

### Step 1.1 — Write failing tests

```elixir
# test/atrium/events_test.exs
defmodule Atrium.EventsTest do
  use Atrium.TenantCase, async: false

  alias Atrium.Events
  alias Atrium.Accounts

  defp build_user(prefix) do
    {:ok, %{user: user}} =
      Accounts.invite_user(prefix, %{
        email: "events_actor_#{System.unique_integer([:positive])}@example.com",
        name: "Events Actor"
      })
    user
  end

  defp build_event(prefix, user, attrs \\ %{}) do
    base = %{
      title: "Team Offsite",
      starts_at: ~U[2026-06-15 09:00:00Z],
      ends_at: ~U[2026-06-15 17:00:00Z],
      all_day: false
    }
    Events.create_event(prefix, Map.merge(base, attrs), user)
  end

  describe "create_event/3" do
    test "creates an event with required fields", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      assert event.title == "Team Offsite"
      assert event.author_id == user.id
      assert event.all_day == false
    end

    test "returns error for missing title", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:error, cs} = Events.create_event(prefix, %{starts_at: ~U[2026-06-15 09:00:00Z]}, user)
      assert errors_on(cs)[:title]
    end

    test "returns error for missing starts_at", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:error, cs} = Events.create_event(prefix, %{title: "No Date"}, user)
      assert errors_on(cs)[:starts_at]
    end

    test "logs event.created audit event", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      events = Atrium.Audit.history_for(prefix, "Event", event.id)
      assert Enum.any?(events, &(&1.action == "event.created"))
    end
  end

  describe "get_event!/2" do
    test "returns the event by id", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      found = Events.get_event!(prefix, event.id)
      assert found.id == event.id
    end

    test "raises Ecto.NoResultsError for unknown id", %{tenant_prefix: prefix} do
      assert_raise Ecto.NoResultsError, fn ->
        Events.get_event!(prefix, Ecto.UUID.generate())
      end
    end
  end

  describe "list_events_for_month/3" do
    test "returns events whose starts_at falls in the given month", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, june_event} = build_event(prefix, user, %{title: "June Event", starts_at: ~U[2026-06-10 10:00:00Z]})
      {:ok, _july_event} = build_event(prefix, user, %{title: "July Event", starts_at: ~U[2026-07-01 10:00:00Z]})
      results = Events.list_events_for_month(prefix, 2026, 6)
      ids = Enum.map(results, & &1.id)
      assert june_event.id in ids
      refute Enum.any?(results, &(&1.title == "July Event"))
    end

    test "returns empty list when no events in month", %{tenant_prefix: prefix} do
      assert Events.list_events_for_month(prefix, 2099, 12) == []
    end

    test "returns events ordered by starts_at ascending", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, _} = build_event(prefix, user, %{title: "Later", starts_at: ~U[2026-06-20 10:00:00Z]})
      {:ok, _} = build_event(prefix, user, %{title: "Earlier", starts_at: ~U[2026-06-05 10:00:00Z]})
      results = Events.list_events_for_month(prefix, 2026, 6)
      titles = Enum.map(results, & &1.title)
      earlier_idx = Enum.find_index(titles, &(&1 == "Earlier"))
      later_idx = Enum.find_index(titles, &(&1 == "Later"))
      assert earlier_idx < later_idx
    end
  end

  describe "update_event/4" do
    test "updates title and location", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      {:ok, updated} = Events.update_event(prefix, event, %{title: "New Title", location: "HQ"}, user)
      assert updated.title == "New Title"
      assert updated.location == "HQ"
    end

    test "returns error for blank title", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      assert {:error, cs} = Events.update_event(prefix, event, %{title: ""}, user)
      assert errors_on(cs)[:title]
    end

    test "logs event.updated audit event", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      {:ok, _} = Events.update_event(prefix, event, %{title: "Updated"}, user)
      history = Atrium.Audit.history_for(prefix, "Event", event.id)
      assert Enum.any?(history, &(&1.action == "event.updated"))
    end
  end

  describe "delete_event/3" do
    test "removes the event", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      {:ok, _} = Events.delete_event(prefix, event, user)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event!(prefix, event.id) end
    end

    test "logs event.deleted audit event", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      {:ok, _} = Events.delete_event(prefix, event, user)
      history = Atrium.Audit.history_for(prefix, "Event", event.id)
      assert Enum.any?(history, &(&1.action == "event.deleted"))
    end
  end
end
```

---

### Step 1.2 — Run tests to confirm failure

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/events_test.exs 2>&1 | head -15
```

Expected: compile error — `Atrium.Events` not defined.

---

### Step 1.3 — Create the migration

```elixir
# priv/repo/tenant_migrations/20260502000002_create_events.exs
defmodule Atrium.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :location, :string
      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec
      add :all_day, :boolean, default: false, null: false
      add :author_id, :binary_id, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:events, [:starts_at])
    create index(:events, [:author_id])
  end
end
```

---

### Step 1.4 — Create the Event schema

```elixir
# lib/atrium/events/event.ex
defmodule Atrium.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "events" do
    field :title, :string
    field :description, :string
    field :location, :string
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :all_day, :boolean, default: false
    field :author_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :description, :location, :starts_at, :ends_at, :all_day, :author_id])
    |> validate_required([:title, :starts_at, :author_id])
    |> validate_length(:title, min: 1, max: 300)
    |> validate_ends_after_starts()
  end

  defp validate_ends_after_starts(cs) do
    starts = get_field(cs, :starts_at)
    ends = get_field(cs, :ends_at)

    if starts && ends && DateTime.compare(ends, starts) == :lt do
      add_error(cs, :ends_at, "must be after start time")
    else
      cs
    end
  end
end
```

---

### Step 1.5 — Create the Events context

```elixir
# lib/atrium/events.ex
defmodule Atrium.Events do
  @moduledoc """
  Context for Events & Calendar.
  All functions operate within a tenant schema prefix.
  """
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Events.Event

  @doc """
  Returns all events whose `starts_at` falls within the given year/month,
  ordered by `starts_at` ascending.
  """
  @spec list_events_for_month(String.t(), integer(), integer()) :: [Event.t()]
  def list_events_for_month(prefix, year, month) do
    {:ok, month_start} = Date.new(year, month, 1)
    days_in_month = Date.days_in_month(month_start)
    {:ok, month_end} = Date.new(year, month, days_in_month)

    range_start = DateTime.new!(month_start, ~T[00:00:00.000000], "Etc/UTC")
    range_end = DateTime.new!(month_end, ~T[23:59:59.999999], "Etc/UTC")

    Repo.all(
      from(e in Event,
        where: e.starts_at >= ^range_start and e.starts_at <= ^range_end,
        order_by: [asc: e.starts_at]
      ),
      prefix: prefix
    )
  end

  @doc """
  Returns the next `limit` events from `from_dt` onwards, ordered ascending.
  Used for the upcoming events list on the index page.
  """
  @spec list_upcoming_events(String.t(), DateTime.t(), non_neg_integer()) :: [Event.t()]
  def list_upcoming_events(prefix, from_dt \\ nil, limit \\ 10) do
    cutoff = from_dt || DateTime.utc_now()

    Repo.all(
      from(e in Event,
        where: e.starts_at >= ^cutoff,
        order_by: [asc: e.starts_at],
        limit: ^limit
      ),
      prefix: prefix
    )
  end

  @doc """
  Fetches a single event by id. Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_event!(String.t(), Ecto.UUID.t()) :: Event.t()
  def get_event!(prefix, id), do: Repo.get!(Event, id, prefix: prefix)

  @doc """
  Creates an event, stamping `author_id` from the actor user, and logs an audit event.
  """
  @spec create_event(String.t(), map(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def create_event(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(stringify(attrs), "author_id", actor_user.id)

    Repo.transaction(fn ->
      with {:ok, event} <-
             %Event{}
             |> Event.changeset(attrs_with_author)
             |> Repo.insert(prefix: prefix),
           {:ok, _} <-
             Audit.log(prefix, "event.created", %{
               actor: {:user, actor_user.id},
               resource: {"Event", event.id}
             }) do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates an existing event and logs an audit event.
  """
  @spec update_event(String.t(), Event.t(), map(), map()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def update_event(prefix, %Event{} = event, attrs, actor_user) do
    Repo.transaction(fn ->
      with {:ok, updated} <-
             event
             |> Event.changeset(stringify(attrs))
             |> Repo.update(prefix: prefix),
           {:ok, _} <-
             Audit.log(prefix, "event.updated", %{
               actor: {:user, actor_user.id},
               resource: {"Event", updated.id}
             }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Deletes an event and logs an audit event.
  """
  @spec delete_event(String.t(), Event.t(), map()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def delete_event(prefix, %Event{} = event, actor_user) do
    Repo.transaction(fn ->
      with {:ok, deleted} <- Repo.delete(event, prefix: prefix),
           {:ok, _} <-
             Audit.log(prefix, "event.deleted", %{
               actor: {:user, actor_user.id},
               resource: {"Event", deleted.id}
             }) do
        deleted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
```

---

### Step 1.6 — Run migration (for tenant schemas, Triplex migrates automatically in TenantCase)

```bash
cd /Users/marcinwalczak/Kod/atrium && mix ecto.migrate 2>&1 | tail -5
```

Expected: public schema reports "Already up" (the migration is tenant-only). `TenantCase` automatically runs Triplex tenant migrations for the test schema.

---

### Step 1.7 — Run context tests

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test test/atrium/events_test.exs 2>&1 | tail -10
```

Expected: 12 tests, 0 failures.

---

### Step 1.8 — Commit

```bash
cd /Users/marcinwalczak/Kod/atrium && git add \
  priv/repo/tenant_migrations/20260502000002_create_events.exs \
  lib/atrium/events/event.ex \
  lib/atrium/events.ex \
  test/atrium/events_test.exs \
  && git commit -m "feat(events): migration, Event schema, Events context with audit logging"
```

---

## Task 2: EventsController + HTML Module

**Files:**
- Create: `lib/atrium_web/controllers/events_controller.ex`
- Create: `lib/atrium_web/controllers/events_html.ex`

At this stage, templates do not exist yet — the controller must compile cleanly, but serving requests waits for Task 3 & 4. Create the HTML module and empty template stubs at the end of this task so `mix compile` succeeds.

---

### Step 2.1 — Create the HTML module

```elixir
# lib/atrium_web/controllers/events_html.ex
defmodule AtriumWeb.EventsHTML do
  use AtriumWeb, :html

  embed_templates "events_html/*"

  @doc """
  Formats a DateTime for display. Returns e.g. "15 Jun 2026, 09:00".
  """
  def format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%d %b %Y, %H:%M")
  end

  def format_datetime(nil), do: ""

  @doc """
  Formats a date only (used for all-day events).
  """
  def format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%d %b %Y")
  end

  def format_date(nil), do: ""
end
```

---

### Step 2.2 — Create the controller

```elixir
# lib/atrium_web/controllers/events_controller.ex
defmodule AtriumWeb.EventsController do
  use AtriumWeb, :controller
  alias Atrium.Events

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "events"}]
       when action in [:index, :show]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "events"}]
       when action in [:new, :create, :edit, :update, :delete]

  # ---------------------------------------------------------------------------
  # index — month grid calendar + upcoming list
  # ---------------------------------------------------------------------------

  def index(conn, params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    {year, month} = parse_year_month(params)

    events = Events.list_events_for_month(prefix, year, month)
    upcoming = Events.list_upcoming_events(prefix, DateTime.utc_now(), 10)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "events"})

    render(conn, :index,
      events: events,
      year: year,
      month: month,
      upcoming: upcoming,
      can_edit: can_edit
    )
  end

  # ---------------------------------------------------------------------------
  # show
  # ---------------------------------------------------------------------------

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    event = Events.get_event!(prefix, id)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "events"})
    render(conn, :show, event: event, can_edit: can_edit)
  end

  # ---------------------------------------------------------------------------
  # new / create
  # ---------------------------------------------------------------------------

  def new(conn, _params) do
    render(conn, :new, changeset: changeset_for_new())
  end

  def create(conn, %{"event" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Events.create_event(prefix, params, user) do
      {:ok, event} ->
        conn
        |> put_flash(:info, "Event created.")
        |> redirect(to: ~p"/events/#{event.id}")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Could not save event.")
        |> render(:new, changeset: changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # edit / update
  # ---------------------------------------------------------------------------

  def edit(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    event = Events.get_event!(prefix, id)
    render(conn, :edit, event: event, changeset: Atrium.Events.Event.changeset(event, %{}))
  end

  def update(conn, %{"id" => id, "event" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    event = Events.get_event!(prefix, id)

    case Events.update_event(prefix, event, params, user) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, "Event updated.")
        |> redirect(to: ~p"/events/#{updated.id}")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Could not update event.")
        |> render(:edit, event: event, changeset: changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # delete
  # ---------------------------------------------------------------------------

  def delete(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    event = Events.get_event!(prefix, id)

    case Events.delete_event(prefix, event, user) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Event deleted.")
        |> redirect(to: ~p"/events")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not delete event.")
        |> redirect(to: ~p"/events/#{id}")
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp parse_year_month(%{"year" => y, "month" => m}) do
    year = String.to_integer(y)
    month = String.to_integer(m)
    now = Date.utc_today()
    year = if year < 2000 or year > 2100, do: now.year, else: year
    month = if month < 1 or month > 12, do: now.month, else: month
    {year, month}
  end

  defp parse_year_month(_) do
    today = Date.utc_today()
    {today.year, today.month}
  end

  defp changeset_for_new do
    Atrium.Events.Event.changeset(%Atrium.Events.Event{}, %{})
  end
end
```

---

### Step 2.3 — Create empty template stubs

Create the directory and four minimal stub files so `embed_templates` does not raise at compile time. The real content is added in Tasks 3 and 4. Stubs are the minimal valid HEEx (a single empty div).

Create directory: `lib/atrium_web/controllers/events_html/`

Stub `index.html.heex`:
```heex
<div></div>
```

Stub `show.html.heex`:
```heex
<div></div>
```

Stub `new.html.heex`:
```heex
<div></div>
```

Stub `edit.html.heex`:
```heex
<div></div>
```

---

### Step 2.4 — Verify compile

```bash
cd /Users/marcinwalczak/Kod/atrium && mix compile 2>&1 | grep -E "^error" | head -10
```

Expected: no errors.

---

### Step 2.5 — Commit

```bash
cd /Users/marcinwalczak/Kod/atrium && git add \
  lib/atrium_web/controllers/events_controller.ex \
  lib/atrium_web/controllers/events_html.ex \
  lib/atrium_web/controllers/events_html/ \
  && git commit -m "feat(events): EventsController + EventsHTML module with stub templates"
```

---

## Task 3: Calendar Index Template

**Files:**
- Replace stub: `lib/atrium_web/controllers/events_html/index.html.heex`

This is the most complex template. It renders a month grid calendar with event pills and a navigation header, then an upcoming events list below. All calendar logic runs in a HEEx assign computed in the controller — but since we have no LiveView, we compute the calendar grid days using a small EEx helper inside the template (plain Elixir comprehensions are valid in HEEx).

---

### Step 3.1 — Write the index template

```heex
<%# lib/atrium_web/controllers/events_html/index.html.heex %>

<%
  # ---- calendar grid helpers ------------------------------------------------
  # days_in_month: integer
  days = Date.days_in_month(Date.new!(@year, @month, 1))

  # weekday of the 1st (Mon=1 … Sun=7, ISO)
  first_weekday = Date.new!(@year, @month, 1) |> Date.day_of_week()
  # leading blank cells (Mon-based grid)
  lead_blanks = first_weekday - 1

  # build list of {day, events_for_that_day}
  day_cells = Enum.map(1..days, fn d ->
    day_events = Enum.filter(@events, fn e ->
      dt_date = DateTime.to_date(e.starts_at)
      dt_date.day == d and dt_date.month == @month and dt_date.year == @year
    end)
    {d, day_events}
  end)

  today = Date.utc_today()
  is_current_month = today.year == @year and today.month == @month

  # prev / next month links
  prev_month = if @month == 1, do: {@year - 1, 12}, else: {@year, @month - 1}
  next_month = if @month == 12, do: {@year + 1, 1}, else: {@year, @month + 1}
  {prev_year, prev_m} = prev_month
  {next_year, next_m} = next_month

  month_label = Calendar.strftime(Date.new!(@year, @month, 1), "%B %Y")
%>

<div class="atrium-anim">
  <%# ── Page header ─────────────────────────────────────────────────────────%>
  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:28px">
    <div>
      <div class="atrium-page-eyebrow">Events</div>
      <h1 class="atrium-page-title">Events &amp; Calendar</h1>
    </div>
    <%= if @can_edit do %>
      <a href={~p"/events/new"} class="atrium-btn atrium-btn-primary">+ Add event</a>
    <% end %>
  </div>

  <%# ── Month navigation ────────────────────────────────────────────────────%>
  <div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">
    <a href={~p"/events?year=#{prev_year}&month=#{prev_m}"}
       class="atrium-btn atrium-btn-ghost"
       style="height:32px;padding:0 10px;font-size:.875rem">
      &#8592;
    </a>
    <span style="font-size:1rem;font-weight:600;color:var(--text-primary);min-width:140px;text-align:center">
      <%= month_label %>
    </span>
    <a href={~p"/events?year=#{next_year}&month=#{next_m}"}
       class="atrium-btn atrium-btn-ghost"
       style="height:32px;padding:0 10px;font-size:.875rem">
      &#8594;
    </a>
    <%= if !is_current_month do %>
      <a href={~p"/events"} style="font-size:.8125rem;color:var(--text-tertiary);text-decoration:none;margin-left:4px">
        Today
      </a>
    <% end %>
  </div>

  <%# ── Calendar grid ───────────────────────────────────────────────────────%>
  <div class="atrium-card" style="margin-bottom:28px;overflow:hidden">
    <%# Day-of-week header row %>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);border-bottom:1px solid var(--border)">
      <%= for day_name <- ~w(Mon Tue Wed Thu Fri Sat Sun) do %>
        <div style="padding:8px 0;text-align:center;font-size:.6875rem;font-weight:600;letter-spacing:.06em;text-transform:uppercase;color:var(--text-tertiary)">
          <%= day_name %>
        </div>
      <% end %>
    </div>

    <%# Day cells %>
    <div style="display:grid;grid-template-columns:repeat(7,1fr)">
      <%# Leading blank cells for days before the 1st %>
      <%= for _ <- 1..lead_blanks//1, lead_blanks > 0 do %>
        <div style="min-height:90px;border-right:1px solid var(--border);border-bottom:1px solid var(--border);background:var(--surface-muted, #fafafa)"></div>
      <% end %>

      <%= for {day, day_events} <- day_cells do %>
        <%
          is_today = is_current_month and day == today.day
          col_pos  = rem(lead_blanks + day - 1, 7)
          is_weekend = col_pos == 5 or col_pos == 6
          bg = cond do
            is_today   -> "var(--blue-50)"
            is_weekend -> "var(--surface-muted, #fafafa)"
            true       -> "var(--surface, #fff)"
          end
        %>
        <div style={"min-height:90px;border-right:1px solid var(--border);border-bottom:1px solid var(--border);background:#{bg};padding:6px 6px 8px;box-sizing:border-box"}>
          <%# Day number %>
          <div style={"font-size:.8125rem;font-weight:#{if is_today, do: "700", else: "500"};color:#{if is_today, do: "var(--blue-500)", else: "var(--text-secondary)"};margin-bottom:4px;line-height:1"}>
            <%= day %>
          </div>

          <%# Event pills for this day %>
          <div style="display:flex;flex-direction:column;gap:2px">
            <%= for event <- Enum.take(day_events, 3) do %>
              <a href={~p"/events/#{event.id}"}
                 style="display:block;padding:1px 5px;border-radius:3px;background:var(--blue-500);color:#fff;font-size:.6875rem;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;text-decoration:none;line-height:1.6"
                 title={event.title}>
                <%= event.title %>
              </a>
            <% end %>
            <%= if length(day_events) > 3 do %>
              <span style="font-size:.6875rem;color:var(--text-tertiary);padding-left:3px">
                +<%= length(day_events) - 3 %> more
              </span>
            <% end %>
          </div>
        </div>
      <% end %>

      <%# Trailing blank cells to complete the final week row %>
      <%
        total_cells = lead_blanks + days
        trailing = rem(7 - rem(total_cells, 7), 7)
      %>
      <%= for _ <- 1..trailing//1, trailing > 0 do %>
        <div style="min-height:90px;border-right:1px solid var(--border);border-bottom:1px solid var(--border);background:var(--surface-muted, #fafafa)"></div>
      <% end %>
    </div>
  </div>

  <%# ── Upcoming events list ────────────────────────────────────────────────%>
  <div>
    <h2 style="font-size:1rem;font-weight:600;color:var(--text-primary);margin-bottom:12px">Upcoming events</h2>

    <%= if @upcoming == [] do %>
      <div style="border:2px dashed var(--border);border-radius:var(--radius);padding:40px;text-align:center;color:var(--text-tertiary)">
        <p style="font-size:.875rem">No upcoming events.</p>
      </div>
    <% end %>

    <div style="display:flex;flex-direction:column;gap:10px">
      <%= for event <- @upcoming do %>
        <a href={~p"/events/#{event.id}"} style="text-decoration:none">
          <div class="atrium-card"
            style="transition:border-color .15s"
            onmouseover="this.style.borderColor='var(--blue-500)'"
            onmouseout="this.style.borderColor='var(--border)'">
            <div class="atrium-card-body" style="display:flex;align-items:flex-start;gap:16px;padding:14px 16px">
              <%# Date badge %>
              <div style="flex-shrink:0;width:44px;text-align:center;border:1px solid var(--border);border-radius:var(--radius);padding:6px 4px;background:var(--surface)">
                <div style="font-size:.625rem;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--blue-500)">
                  <%= Calendar.strftime(event.starts_at, "%b") %>
                </div>
                <div style="font-size:1.25rem;font-weight:700;color:var(--text-primary);line-height:1.1">
                  <%= Calendar.strftime(event.starts_at, "%d") %>
                </div>
              </div>
              <%# Event details %>
              <div style="flex:1;min-width:0">
                <div style="font-size:.9375rem;font-weight:600;color:var(--text-primary)"><%= event.title %></div>
                <div style="font-size:.8125rem;color:var(--text-secondary);margin-top:2px">
                  <%= if event.all_day do %>
                    All day
                  <% else %>
                    <%= AtriumWeb.EventsHTML.format_datetime(event.starts_at) %>
                    <%= if event.ends_at do %>
                      &ndash; <%= AtriumWeb.EventsHTML.format_datetime(event.ends_at) %>
                    <% end %>
                  <% end %>
                </div>
                <%= if event.location && event.location != "" do %>
                  <div style="font-size:.8125rem;color:var(--text-tertiary);margin-top:2px">
                    <%= event.location %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </a>
      <% end %>
    </div>
  </div>
</div>
```

---

### Step 3.2 — Verify compile

```bash
cd /Users/marcinwalczak/Kod/atrium && mix compile 2>&1 | grep -E "^error" | head -10
```

Expected: no errors.

---

### Step 3.3 — Commit

```bash
cd /Users/marcinwalczak/Kod/atrium && git add lib/atrium_web/controllers/events_html/index.html.heex \
  && git commit -m "feat(events): calendar month grid + upcoming events list template"
```

---

## Task 4: Show / New / Edit Templates + Forms

**Files:**
- Replace stub: `lib/atrium_web/controllers/events_html/show.html.heex`
- Replace stub: `lib/atrium_web/controllers/events_html/new.html.heex`
- Replace stub: `lib/atrium_web/controllers/events_html/edit.html.heex`

The new and edit templates share an identical form partial strategy. Because `EventsHTML` uses `embed_templates`, a private helper component `event_form/1` is the cleanest approach — but since `embed_templates` embeds all `*.html.heex` files, the shared form markup is inline in both `new` and `edit` with the only difference being the form action and the button label. This keeps the templates self-contained without needing a separate component file.

**Note on datetime inputs:** HTML `datetime-local` inputs use the format `YYYY-MM-DDTHH:MM`. The controller receives this as a plain string. Ecto's `cast/3` handles ISO 8601 strings for `:utc_datetime_usec` fields automatically, so no special parsing is needed.

---

### Step 4.1 — Show template

```heex
<%# lib/atrium_web/controllers/events_html/show.html.heex %>
<div class="atrium-anim" style="max-width:720px">
  <div style="margin-bottom:20px">
    <a href={~p"/events"} style="font-size:.8125rem;color:var(--text-tertiary);text-decoration:none">
      ← Events &amp; Calendar
    </a>
  </div>

  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:24px;gap:12px">
    <div>
      <div class="atrium-page-eyebrow">Event</div>
      <h1 class="atrium-page-title"><%= @event.title %></h1>
    </div>
    <%= if @can_edit do %>
      <div style="display:flex;gap:8px;flex-shrink:0;margin-top:8px">
        <a href={~p"/events/#{@event.id}/edit"} class="atrium-btn atrium-btn-ghost">Edit</a>
        <form method="post" action={~p"/events/#{@event.id}/delete"} style="display:inline"
          onsubmit="return confirm('Delete this event?')">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button type="submit" class="atrium-btn atrium-btn-ghost"
            style="color:var(--color-error, #ef4444)"
            onmouseover="this.style.borderColor='var(--color-error,#ef4444)'"
            onmouseout="this.style.borderColor='var(--border)'">
            Delete
          </button>
        </form>
      </div>
    <% end %>
  </div>

  <div class="atrium-card">
    <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:16px">
      <%# When %>
      <div>
        <div style="font-size:.6875rem;font-weight:600;text-transform:uppercase;letter-spacing:.06em;color:var(--text-tertiary);margin-bottom:4px">When</div>
        <div style="font-size:.9375rem;color:var(--text-primary)">
          <%= if @event.all_day do %>
            <%= AtriumWeb.EventsHTML.format_date(@event.starts_at) %>
            &mdash; All day
          <% else %>
            <%= AtriumWeb.EventsHTML.format_datetime(@event.starts_at) %>
            <%= if @event.ends_at do %>
              &ndash; <%= AtriumWeb.EventsHTML.format_datetime(@event.ends_at) %>
            <% end %>
          <% end %>
        </div>
      </div>

      <%# Location (optional) %>
      <%= if @event.location && @event.location != "" do %>
        <div>
          <div style="font-size:.6875rem;font-weight:600;text-transform:uppercase;letter-spacing:.06em;color:var(--text-tertiary);margin-bottom:4px">Location</div>
          <div style="font-size:.9375rem;color:var(--text-primary)"><%= @event.location %></div>
        </div>
      <% end %>

      <%# Description (optional) %>
      <%= if @event.description && @event.description != "" do %>
        <div>
          <div style="font-size:.6875rem;font-weight:600;text-transform:uppercase;letter-spacing:.06em;color:var(--text-tertiary);margin-bottom:4px">Description</div>
          <div style="font-size:.9375rem;color:var(--text-primary);line-height:1.6;white-space:pre-wrap"><%= @event.description %></div>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

---

### Step 4.2 — New template

```heex
<%# lib/atrium_web/controllers/events_html/new.html.heex %>
<div class="atrium-anim" style="max-width:560px">
  <div style="margin-bottom:20px">
    <a href={~p"/events"} style="font-size:.8125rem;color:var(--text-tertiary);text-decoration:none">
      ← Events &amp; Calendar
    </a>
  </div>

  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Events</div>
    <h1 class="atrium-page-title">New Event</h1>
  </div>

  <form method="post" action={~p"/events"}>
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

    <div class="atrium-card" style="margin-bottom:20px">
      <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:16px">

        <div>
          <label class="atrium-label" for="event_title">Title <span style="color:var(--color-error,#ef4444)">*</span></label>
          <input
            id="event_title"
            type="text"
            name="event[title]"
            class="atrium-input"
            value={Ecto.Changeset.get_field(@changeset, :title) || ""}
            required
            placeholder="All-hands meeting"
          />
          <%= if msg = List.first(Keyword.get(@changeset.errors, :title, [])) do %>
            <p style="font-size:.8125rem;color:var(--color-error,#ef4444);margin-top:4px"><%= elem(msg, 0) %></p>
          <% end %>
        </div>

        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
          <div>
            <label class="atrium-label" for="event_starts_at">Starts at <span style="color:var(--color-error,#ef4444)">*</span></label>
            <input
              id="event_starts_at"
              type="datetime-local"
              name="event[starts_at]"
              class="atrium-input"
              value={format_input_datetime(Ecto.Changeset.get_field(@changeset, :starts_at))}
              required
            />
            <%= if msg = List.first(Keyword.get(@changeset.errors, :starts_at, [])) do %>
              <p style="font-size:.8125rem;color:var(--color-error,#ef4444);margin-top:4px"><%= elem(msg, 0) %></p>
            <% end %>
          </div>

          <div>
            <label class="atrium-label" for="event_ends_at">Ends at</label>
            <input
              id="event_ends_at"
              type="datetime-local"
              name="event[ends_at]"
              class="atrium-input"
              value={format_input_datetime(Ecto.Changeset.get_field(@changeset, :ends_at))}
            />
            <%= if msg = List.first(Keyword.get(@changeset.errors, :ends_at, [])) do %>
              <p style="font-size:.8125rem;color:var(--color-error,#ef4444);margin-top:4px"><%= elem(msg, 0) %></p>
            <% end %>
          </div>
        </div>

        <div style="display:flex;align-items:center;gap:8px">
          <input
            type="checkbox"
            name="event[all_day]"
            id="event_all_day"
            value="true"
            style="accent-color:var(--blue-500);width:15px;height:15px"
            <%= if Ecto.Changeset.get_field(@changeset, :all_day), do: "checked" %>
            onchange="
              var hide = this.checked;
              document.getElementById('time-fields').style.display = hide ? 'none' : '';
            "
          />
          <label for="event_all_day" style="font-size:.875rem;color:var(--text-secondary);cursor:pointer">All-day event</label>
        </div>

        <div>
          <label class="atrium-label" for="event_location">Location</label>
          <input
            id="event_location"
            type="text"
            name="event[location]"
            class="atrium-input"
            value={Ecto.Changeset.get_field(@changeset, :location) || ""}
            placeholder="Conference Room A, Zoom, etc."
          />
        </div>

        <div>
          <label class="atrium-label" for="event_description">Description</label>
          <textarea
            id="event_description"
            name="event[description]"
            class="atrium-input"
            rows="4"
            style="resize:vertical"
            placeholder="Optional details…"
          ><%= Ecto.Changeset.get_field(@changeset, :description) || "" %></textarea>
        </div>

      </div>
    </div>

    <div style="display:flex;gap:8px">
      <button type="submit" class="atrium-btn atrium-btn-primary">Create event</button>
      <a href={~p"/events"} class="atrium-btn atrium-btn-ghost">Cancel</a>
    </div>
  </form>
</div>
```

---

### Step 4.3 — Edit template

```heex
<%# lib/atrium_web/controllers/events_html/edit.html.heex %>
<div class="atrium-anim" style="max-width:560px">
  <div style="margin-bottom:20px">
    <a href={~p"/events/#{@event.id}"} style="font-size:.8125rem;color:var(--text-tertiary);text-decoration:none">
      ← Back to event
    </a>
  </div>

  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Events</div>
    <h1 class="atrium-page-title">Edit Event</h1>
  </div>

  <form method="post" action={~p"/events/#{@event.id}"}>
    <input type="hidden" name="_method" value="put" />
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

    <div class="atrium-card" style="margin-bottom:20px">
      <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:16px">

        <div>
          <label class="atrium-label" for="event_title">Title <span style="color:var(--color-error,#ef4444)">*</span></label>
          <input
            id="event_title"
            type="text"
            name="event[title]"
            class="atrium-input"
            value={Ecto.Changeset.get_field(@changeset, :title) || ""}
            required
          />
          <%= if msg = List.first(Keyword.get(@changeset.errors, :title, [])) do %>
            <p style="font-size:.8125rem;color:var(--color-error,#ef4444);margin-top:4px"><%= elem(msg, 0) %></p>
          <% end %>
        </div>

        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
          <div>
            <label class="atrium-label" for="event_starts_at">Starts at <span style="color:var(--color-error,#ef4444)">*</span></label>
            <input
              id="event_starts_at"
              type="datetime-local"
              name="event[starts_at]"
              class="atrium-input"
              value={format_input_datetime(Ecto.Changeset.get_field(@changeset, :starts_at))}
              required
            />
            <%= if msg = List.first(Keyword.get(@changeset.errors, :starts_at, [])) do %>
              <p style="font-size:.8125rem;color:var(--color-error,#ef4444);margin-top:4px"><%= elem(msg, 0) %></p>
            <% end %>
          </div>

          <div>
            <label class="atrium-label" for="event_ends_at">Ends at</label>
            <input
              id="event_ends_at"
              type="datetime-local"
              name="event[ends_at]"
              class="atrium-input"
              value={format_input_datetime(Ecto.Changeset.get_field(@changeset, :ends_at))}
            />
            <%= if msg = List.first(Keyword.get(@changeset.errors, :ends_at, [])) do %>
              <p style="font-size:.8125rem;color:var(--color-error,#ef4444);margin-top:4px"><%= elem(msg, 0) %></p>
            <% end %>
          </div>
        </div>

        <div style="display:flex;align-items:center;gap:8px">
          <input
            type="checkbox"
            name="event[all_day]"
            id="event_all_day"
            value="true"
            style="accent-color:var(--blue-500);width:15px;height:15px"
            <%= if Ecto.Changeset.get_field(@changeset, :all_day), do: "checked" %>
          />
          <label for="event_all_day" style="font-size:.875rem;color:var(--text-secondary);cursor:pointer">All-day event</label>
        </div>

        <div>
          <label class="atrium-label" for="event_location">Location</label>
          <input
            id="event_location"
            type="text"
            name="event[location]"
            class="atrium-input"
            value={Ecto.Changeset.get_field(@changeset, :location) || ""}
          />
        </div>

        <div>
          <label class="atrium-label" for="event_description">Description</label>
          <textarea
            id="event_description"
            name="event[description]"
            class="atrium-input"
            rows="4"
            style="resize:vertical"
          ><%= Ecto.Changeset.get_field(@changeset, :description) || "" %></textarea>
        </div>

      </div>
    </div>

    <div style="display:flex;gap:8px">
      <button type="submit" class="atrium-btn atrium-btn-primary">Save changes</button>
      <a href={~p"/events/#{@event.id}"} class="atrium-btn atrium-btn-ghost">Cancel</a>
    </div>
  </form>
</div>
```

---

### Step 4.4 — Add `format_input_datetime/1` helper to EventsHTML

The templates call `format_input_datetime/1`, which must be defined as a public function in `events_html.ex` (functions defined there are available inside `embed_templates`-rendered templates as module functions called without a receiver, because HEEx templates in Phoenix 1.7+ are compiled as function components in the HTML module).

Add the following function to `lib/atrium_web/controllers/events_html.ex`, inside the module body after `format_date/1`:

```elixir
@doc """
Formats a DateTime for use as the value of a datetime-local HTML input.
Returns the format "YYYY-MM-DDTHH:MM" or an empty string for nil.
"""
def format_input_datetime(%DateTime{} = dt) do
  Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
end

def format_input_datetime(nil), do: ""
```

---

### Step 4.5 — Verify compile

```bash
cd /Users/marcinwalczak/Kod/atrium && mix compile 2>&1 | grep -E "^error" | head -10
```

Expected: no errors.

---

### Step 4.6 — Commit

```bash
cd /Users/marcinwalczak/Kod/atrium && git add \
  lib/atrium_web/controllers/events_html/show.html.heex \
  lib/atrium_web/controllers/events_html/new.html.heex \
  lib/atrium_web/controllers/events_html/edit.html.heex \
  lib/atrium_web/controllers/events_html.ex \
  && git commit -m "feat(events): show, new, edit templates + format_input_datetime helper"
```

---

## Task 5: Wire Router + Sidebar

**Files:**
- Modify: `lib/atrium_web/router.ex`
- Modify: `lib/atrium_web/components/layouts/app.html.heex`

---

### Step 5.1 — Add routes to router.ex

Inside the authenticated scope in `lib/atrium_web/router.ex`, add the following block after the `/helpdesk` route (line 110) and before the `/tools` routes:

```elixir
get  "/events",          EventsController, :index
get  "/events/new",      EventsController, :new
post "/events",          EventsController, :create
get  "/events/:id",      EventsController, :show
get  "/events/:id/edit", EventsController, :edit
put  "/events/:id",      EventsController, :update
post "/events/:id/delete", EventsController, :delete
```

The full placement context looks like:

```elixir
# ... existing routes ...
get "/helpdesk", HelpdeskController, :index

get  "/events",            EventsController, :index
get  "/events/new",        EventsController, :new
post "/events",            EventsController, :create
get  "/events/:id",        EventsController, :show
get  "/events/:id/edit",   EventsController, :edit
put  "/events/:id",        EventsController, :update
post "/events/:id/delete", EventsController, :delete

get  "/tools", ToolsController, :index
# ... rest of tools routes ...
```

**Important ordering note:** `get "/events/new"` must appear before `get "/events/:id"` so the literal segment `"new"` is not captured as an `:id` parameter. The plan lists them in this correct order above.

---

### Step 5.2 — Add "events" to the dedicated list in app.html.heex

In `lib/atrium_web/components/layouts/app.html.heex`, find line 50:

```elixir
<% dedicated = ~w(home news directory tools compliance helpdesk) %>
```

Change it to:

```elixir
<% dedicated = ~w(home news directory tools compliance helpdesk events) %>
```

This causes the sidebar to link to `/events` (the dedicated path) instead of `/sections/events/documents`, and activates the sidebar item when any path starting with `/events/` is visited.

---

### Step 5.3 — Verify compile

```bash
cd /Users/marcinwalczak/Kod/atrium && mix compile 2>&1 | grep -E "^error" | head -10
```

Expected: no errors.

---

### Step 5.4 — Run the full test suite

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1 | tail -15
```

Expected: all tests pass, including the 12 new events context tests. No pre-existing tests should regress (the router and sidebar changes do not touch existing controller logic).

---

### Step 5.5 — Commit

```bash
cd /Users/marcinwalczak/Kod/atrium && git add \
  lib/atrium_web/router.ex \
  lib/atrium_web/components/layouts/app.html.heex \
  && git commit -m "feat(events): wire router routes + add events to sidebar dedicated list"
```

---

## Task 6: Final Integration Verification + Tag

This task has no new code. It verifies the full feature end-to-end and tags the milestone.

---

### Step 6.1 — Run the complete test suite once more

```bash
cd /Users/marcinwalczak/Kod/atrium && mix test 2>&1 | tail -20
```

Expected: 0 failures. If any test fails that was not failing before, diagnose and fix before continuing.

---

### Step 6.2 — Verify route list

```bash
cd /Users/marcinwalczak/Kod/atrium && mix phx.routes 2>&1 | grep events
```

Expected output (order may vary slightly):

```
GET     /events                AtriumWeb.EventsController :index
GET     /events/new            AtriumWeb.EventsController :new
POST    /events                AtriumWeb.EventsController :create
GET     /events/:id            AtriumWeb.EventsController :show
GET     /events/:id/edit       AtriumWeb.EventsController :edit
PUT     /events/:id            AtriumWeb.EventsController :update
POST    /events/:id/delete     AtriumWeb.EventsController :delete
```

---

### Step 6.3 — Final commit and tag

```bash
cd /Users/marcinwalczak/Kod/atrium && git tag events-calendar-complete
```

---

## Implementation Notes for the Executing Agent

### datetime-local input round-trip

HTML `datetime-local` inputs submit values in the format `"2026-06-15T09:00"` (no seconds, no timezone). Ecto's `cast/3` for `:utc_datetime_usec` accepts ISO 8601 strings and treats naive strings as UTC. This works correctly without custom parsing. When editing an existing event, `format_input_datetime/1` in `EventsHTML` converts the stored `%DateTime{}` back to `"YYYY-MM-DDTHH:MM"` for pre-filling the input.

### all_day checkbox

HTML checkboxes only submit their value when checked. If the user unchecks "all-day", the `event[all_day]` param is absent from the form submission. `cast/3` treats an absent boolean field as `false`, which is the correct behavior. No hidden field is needed.

### Trailing slash in grid — `1..trailing//1`

The Elixir range `1..0` is non-empty in older Elixir versions but correctly treated as empty with the step syntax `1..0//1`. The template uses `1..trailing//1, trailing > 0` with a guard to ensure no iteration happens when `trailing == 0` (i.e., the last row is already complete). Always include that guard.

### list_upcoming_events is a bonus function

`list_upcoming_events/3` is not in the spec but is called by the controller's `index` action to power the "Upcoming events" list. It is defined in `lib/atrium/events.ex` alongside the five specified functions. No additional test coverage is required for it beyond integration — the context tests cover the specified API surface.

### Route ordering

Phoenix routes are matched top-to-bottom. `GET /events/new` must be declared before `GET /events/:id` in the router file. The plan places them in the correct order in Step 5.1.

### Sidebar active state

The existing sidebar logic in `app.html.heex` computes `section_active` as:
```elixir
section_active = if is_dedicated, do: path == "/#{key}" or String.starts_with?(path, "/#{key}/")
```
Adding `"events"` to `dedicated` means the Events sidebar entry is highlighted on `/events`, `/events/new`, `/events/:id`, and `/events/:id/edit` automatically.

---

## Critical Files for Implementation

- `/Users/marcinwalczak/Kod/atrium/lib/atrium/events.ex`
- `/Users/marcinwalczak/Kod/atrium/lib/atrium/events/event.ex`
- `/Users/marcinwalczak/Kod/atrium/lib/atrium_web/controllers/events_controller.ex`
- `/Users/marcinwalczak/Kod/atrium/lib/atrium_web/controllers/events_html.ex`
- `/Users/marcinwalczak/Kod/atrium/lib/atrium_web/controllers/events_html/index.html.heex`
