# Global Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global `/search?q=` page that performs ILIKE queries across documents, users, and tool links — filtered by what the current user is authorised to see — and wire the topbar search input to navigate there on Enter or ⌘K.

**Architecture:** A new `Atrium.Search` context owns all three ILIKE queries (no new DB extensions). `AtriumWeb.SearchController` calls those functions, applies per-section permission checks inline, and hands grouped results to a single HEEx template. The topbar search input is wired with a small vanilla-JS snippet added to `app.js`. No LiveView, no new dependencies.

**Tech Stack:** Elixir/Phoenix 1.8, Ecto + Triplex (schema-per-tenant prefix), `Atrium.Authorization.Policy.can?/4`, `atrium-*` CSS design system, vanilla JS (already in `assets/js/app.js`).

---

## File map

| File | Action | Purpose |
|---|---|---|
| `lib/atrium/search.ex` | Create | Context: `search_documents/3`, `search_users/3`, `search_tools/2` |
| `lib/atrium_web/controllers/search_controller.ex` | Create | `GET /search` — orchestrates queries + permission checks |
| `lib/atrium_web/controllers/search_html.ex` | Create | HTML module — embeds templates |
| `lib/atrium_web/controllers/search_html/index.html.heex` | Create | Results page template |
| `lib/atrium_web/router.ex` | Modify | Add `get "/search", SearchController, :index` inside authenticated scope |
| `lib/atrium_web/components/layouts/app.html.heex` | Modify | Wire `id`, `phx-no-intercept`, and JS to topbar search input |
| `assets/js/app.js` | Modify | Add topbar search JS (Enter + ⌘K) |
| `test/atrium/search_test.exs` | Create | Context-level tests using `Atrium.TenantCase` |

---

## Task 1: Search context (`lib/atrium/search.ex`) with tests

**Files:**
- Create: `lib/atrium/search.ex`
- Create: `test/atrium/search_test.exs`

### Background

This context is the only place that touches SQL. It knows nothing about HTTP or permissions — the controller decides what to call. Each function takes `prefix` (e.g. `"tenant_acme"`) as its first argument, matching the pattern used throughout the codebase (see `Atrium.Documents`, `Atrium.Tools`).

Three public functions:

- `search_documents(prefix, query, section_keys)` — ILIKE on `title` and `body_html` in the `documents` table, filtered to the given `section_keys` list and `status: "approved"`. Returns `[%Document{}]`.
- `search_users(prefix, query)` — ILIKE on `name`, `email`, `role`, `department` in the `users` table, filtered to `status: "active"`. Returns `[%User{}]`.
- `search_tools(prefix, query)` — ILIKE on `label` and `description` in the `tool_links` table, no status filter. Returns `[%ToolLink{}]`.

All functions return `[]` when `query` has fewer than 2 characters (guard at the top of each function). Results are ordered by `inserted_at DESC` so newest appears first.

The ILIKE pattern is `"%#{query}%"` — PostgreSQL handles case-insensitivity via `ILIKE`. Ecto exposes this through `ilike/2` in `Ecto.Query`.

- [ ] **Step 1: Write the failing tests**

```elixir
# test/atrium/search_test.exs
defmodule Atrium.SearchTest do
  use Atrium.TenantCase
  alias Atrium.Search
  alias Atrium.Accounts
  alias Atrium.Documents
  alias Atrium.Tools

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_user(prefix, attrs \\ %{}) do
    default = %{
      email: "user_#{System.unique_integer([:positive])}@example.com",
      name: "Search User"
    }
    {:ok, %{user: user, token: raw}} = Accounts.invite_user(prefix, Map.merge(default, attrs))
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    user
  end

  defp create_document(prefix, author, attrs \\ %{}) do
    default = %{title: "Default Doc", section_key: "compliance", body_html: "<p>body</p>"}
    {:ok, doc} = Documents.create_document(prefix, Map.merge(default, attrs), author)
    # Approve via internal transition so search can find it
    {:ok, doc} = Documents.approve_document(prefix, submit_to_review(prefix, doc, author), author)
    doc
  end

  defp submit_to_review(prefix, doc, author) do
    {:ok, reviewed} = Documents.submit_for_review(prefix, doc, author)
    reviewed
  end

  defp create_tool(prefix, author, attrs \\ %{}) do
    default = %{
      label: "Default Tool",
      description: "A tool description",
      kind: "link",
      url: "https://example.com"
    }
    {:ok, tool} = Tools.create_tool_link(prefix, Map.merge(default, attrs), author)
    tool
  end

  # ---------------------------------------------------------------------------
  # search_documents/3
  # ---------------------------------------------------------------------------

  describe "search_documents/3" do
    test "returns approved documents matching title", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _doc = create_document(prefix, author, %{title: "Parental Leave Policy", section_key: "hr"})

      results = Search.search_documents(prefix, "parental", ["hr"])
      assert length(results) == 1
      assert hd(results).title == "Parental Leave Policy"
    end

    test "returns approved documents matching body_html", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _doc = create_document(prefix, author, %{
        title: "HR Policy",
        section_key: "hr",
        body_html: "<p>remote working guidelines</p>"
      })

      results = Search.search_documents(prefix, "remote working", ["hr"])
      assert length(results) == 1
    end

    test "returns [] when query is shorter than 2 chars", %{tenant_prefix: prefix} do
      assert Search.search_documents(prefix, "a", ["hr"]) == []
      assert Search.search_documents(prefix, "", ["hr"]) == []
    end

    test "does not return documents from sections not in section_keys", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _doc = create_document(prefix, author, %{title: "Compliance Doc", section_key: "compliance"})

      results = Search.search_documents(prefix, "Compliance", ["hr"])
      assert results == []
    end

    test "returns [] when section_keys is empty", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _doc = create_document(prefix, author, %{title: "Anything", section_key: "hr"})

      assert Search.search_documents(prefix, "anything", []) == []
    end

    test "is case-insensitive", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _doc = create_document(prefix, author, %{title: "Annual Report", section_key: "compliance"})

      assert length(Search.search_documents(prefix, "ANNUAL", ["compliance"])) == 1
      assert length(Search.search_documents(prefix, "annual", ["compliance"])) == 1
    end

    test "does not return draft documents", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      # create_document creates and immediately approves; we just insert a raw draft
      {:ok, _draft} = Documents.create_document(
        prefix,
        %{title: "Draft Policy", section_key: "hr", body_html: "draft"},
        author
      )

      results = Search.search_documents(prefix, "Draft Policy", ["hr"])
      assert results == []
    end
  end

  # ---------------------------------------------------------------------------
  # search_users/2
  # ---------------------------------------------------------------------------

  describe "search_users/2" do
    test "matches active users by name", %{tenant_prefix: prefix} do
      _alice = create_user(prefix, %{email: "alice@example.com", name: "Alice Wonderland"})

      results = Search.search_users(prefix, "wonderland")
      assert Enum.any?(results, &(&1.name == "Alice Wonderland"))
    end

    test "matches active users by email", %{tenant_prefix: prefix} do
      _bob = create_user(prefix, %{email: "bob.unique@example.com", name: "Bob Smith"})

      results = Search.search_users(prefix, "bob.unique")
      assert Enum.any?(results, &(&1.email == "bob.unique@example.com"))
    end

    test "matches by role and department", %{tenant_prefix: prefix} do
      user = create_user(prefix, %{email: "eng@example.com", name: "Eng Person"})
      {:ok, _} = Accounts.update_profile(prefix, user, %{
        name: "Eng Person",
        role: "Senior Engineer",
        department: "Platform"
      })

      assert Enum.any?(Search.search_users(prefix, "Senior Engineer"), &(&1.email == "eng@example.com"))
      assert Enum.any?(Search.search_users(prefix, "Platform"), &(&1.email == "eng@example.com"))
    end

    test "returns [] when query is shorter than 2 chars", %{tenant_prefix: prefix} do
      assert Search.search_users(prefix, "x") == []
      assert Search.search_users(prefix, "") == []
    end

    test "does not return suspended users", %{tenant_prefix: prefix} do
      user = create_user(prefix, %{email: "suspended@example.com", name: "Suspended Person"})
      {:ok, _} = Accounts.suspend_user(prefix, user)

      results = Search.search_users(prefix, "Suspended Person")
      assert results == []
    end
  end

  # ---------------------------------------------------------------------------
  # search_tools/2
  # ---------------------------------------------------------------------------

  describe "search_tools/2" do
    test "matches tools by label", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _tool = create_tool(prefix, author, %{label: "Jira Tickets", url: "https://jira.example.com"})

      results = Search.search_tools(prefix, "jira")
      assert Enum.any?(results, &(&1.label == "Jira Tickets"))
    end

    test "matches tools by description", %{tenant_prefix: prefix} do
      author = create_user(prefix)
      _tool = create_tool(prefix, author, %{
        label: "Some Tool",
        description: "Used for performance reviews",
        url: "https://perf.example.com"
      })

      results = Search.search_tools(prefix, "performance reviews")
      assert Enum.any?(results, &(&1.label == "Some Tool"))
    end

    test "returns [] when query is shorter than 2 chars", %{tenant_prefix: prefix} do
      assert Search.search_tools(prefix, "x") == []
    end
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
mix test test/atrium/search_test.exs
```

Expected: compilation error — `Atrium.Search` does not exist yet.

- [ ] **Step 3: Implement `lib/atrium/search.ex`**

```elixir
# lib/atrium/search.ex
defmodule Atrium.Search do
  @moduledoc """
  Cross-entity full-text search using ILIKE queries.

  All functions accept a `prefix` (Triplex tenant schema prefix, e.g.
  `"tenant_acme"`) and a `query` string. Results are empty when the query
  is shorter than 2 characters.

  Permission checks are NOT performed here — the caller (SearchController)
  is responsible for passing only the section_keys the user can view.
  """

  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Documents.Document
  alias Atrium.Accounts.User
  alias Atrium.Tools.ToolLink

  @min_query_length 2

  @doc """
  Search approved documents across the given section_keys.

  Returns `[%Document{}]` ordered by `inserted_at DESC`.
  Returns `[]` if `query` is fewer than #{@min_query_length} characters or
  if `section_keys` is empty.
  """
  @spec search_documents(String.t(), String.t(), [String.t()]) :: [Document.t()]
  def search_documents(_prefix, query, _section_keys)
      when byte_size(query) < @min_query_length,
      do: []

  def search_documents(_prefix, _query, []), do: []

  def search_documents(prefix, query, section_keys) do
    pattern = "%#{query}%"

    from(d in Document,
      where: d.section_key in ^section_keys,
      where: d.status == "approved",
      where: ilike(d.title, ^pattern) or ilike(d.body_html, ^pattern),
      order_by: [desc: d.inserted_at]
    )
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Search active users by name, email, role, or department.

  Returns `[%User{}]` ordered by `inserted_at DESC`.
  Returns `[]` if `query` is fewer than #{@min_query_length} characters.
  """
  @spec search_users(String.t(), String.t()) :: [User.t()]
  def search_users(_prefix, query)
      when byte_size(query) < @min_query_length,
      do: []

  def search_users(prefix, query) do
    pattern = "%#{query}%"

    from(u in User,
      where: u.status == "active",
      where:
        ilike(u.name, ^pattern) or
          ilike(u.email, ^pattern) or
          ilike(u.role, ^pattern) or
          ilike(u.department, ^pattern),
      order_by: [desc: u.inserted_at]
    )
    |> Repo.all(prefix: prefix)
  end

  @doc """
  Search tool links by label or description.

  Returns `[%ToolLink{}]` ordered by `inserted_at DESC`.
  Returns `[]` if `query` is fewer than #{@min_query_length} characters.
  """
  @spec search_tools(String.t(), String.t()) :: [ToolLink.t()]
  def search_tools(_prefix, query)
      when byte_size(query) < @min_query_length,
      do: []

  def search_tools(prefix, query) do
    pattern = "%#{query}%"

    from(t in ToolLink,
      where: ilike(t.label, ^pattern) or ilike(t.description, ^pattern),
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all(prefix: prefix)
  end
end
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
mix test test/atrium/search_test.exs
```

Expected: all tests pass. If a test for `search_users` matching by `role`/`department` fails, check that `Accounts.update_profile/3` is called with `prefix` as first arg — it follows the same pattern as `Accounts.suspend_user/2`.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/search.ex test/atrium/search_test.exs
git commit -m "feat: add Atrium.Search context with ILIKE queries for documents, users, tools"
```

---

## Task 2: SearchController, HTML module, and template

**Files:**
- Create: `lib/atrium_web/controllers/search_controller.ex`
- Create: `lib/atrium_web/controllers/search_html.ex`
- Create: `lib/atrium_web/controllers/search_html/index.html.heex`

### Background

The controller pattern in this app is:

1. `use AtriumWeb, :controller`
2. Optional `plug AtriumWeb.Plugs.Authorize` guards at the top
3. An action function that reads from `conn.assigns` (not a `plug`) and renders via the matching HTML module

For search there is no single section to gate — instead the controller collects the sections the user can view (from `conn.assigns.nav`) and passes those section keys to `Search.search_documents/3`. This avoids duplicating permission logic. The nav already contains only sections the user can see (built by `AssignNav` plug from `AppShell.nav_for_user/3`).

The `assigns.nav` list has the shape `[%{key: atom(), name: String.t(), ...}]`. So `Enum.map(nav, & to_string(&1.key))` gives all viewable section keys.

Users appear only when the user can view the `directory` section. Tools appear only when the user can view the `tools` section. Both checks use `Policy.can?/4` directly in the controller, consistent with how `ComplianceController` and `ToolsController` call it.

Minimum query length is 2 characters — enforced by `Atrium.Search` functions, but the controller also skips running any queries when the query is `nil` or shorter than 2 chars.

- [ ] **Step 1: Write `lib/atrium_web/controllers/search_controller.ex`**

```elixir
# lib/atrium_web/controllers/search_controller.ex
defmodule AtriumWeb.SearchController do
  use AtriumWeb, :controller

  alias Atrium.Search
  alias Atrium.Authorization.Policy

  @min_query_length 2

  def index(conn, params) do
    query = params["q"] || ""
    prefix = conn.assigns.tenant_prefix
    user   = conn.assigns.current_user
    nav    = conn.assigns.nav

    {documents, users, tools} =
      if String.length(query) >= @min_query_length do
        viewable_section_keys = Enum.map(nav, &to_string(&1.key))

        docs =
          Search.search_documents(prefix, query, viewable_section_keys)

        found_users =
          if Policy.can?(prefix, user, :view, {:section, "directory"}) do
            Search.search_users(prefix, query)
          else
            []
          end

        found_tools =
          if Policy.can?(prefix, user, :view, {:section, "tools"}) do
            Search.search_tools(prefix, query)
          else
            []
          end

        {docs, found_users, found_tools}
      else
        {[], [], []}
      end

    render(conn, :index,
      query: query,
      documents: documents,
      users: users,
      tools: tools
    )
  end
end
```

- [ ] **Step 2: Write `lib/atrium_web/controllers/search_html.ex`**

```elixir
# lib/atrium_web/controllers/search_html.ex
defmodule AtriumWeb.SearchHTML do
  use AtriumWeb, :html
  embed_templates "search_html/*"
end
```

- [ ] **Step 3: Write `lib/atrium_web/controllers/search_html/index.html.heex`**

Study `compliance_html/index.html.heex` and `directory_html/index.html.heex` for layout conventions: `atrium-anim` wrapper, `atrium-page-eyebrow` + `atrium-page-title`, `atrium-card` + `atrium-card-header` + `atrium-card-title`, `atrium-table`, CSS variables for text colours.

```heex
<%# lib/atrium_web/controllers/search_html/index.html.heex %>
<div class="atrium-anim">
  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Search</div>
    <h1 class="atrium-page-title">Search</h1>
  </div>

  <form method="get" action={~p"/search"} style="margin-bottom:28px">
    <div style="position:relative;max-width:480px;display:flex;gap:8px">
      <div style="position:relative;flex:1">
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75"
             style="width:14px;height:14px;position:absolute;left:10px;top:50%;transform:translateY(-50%);color:var(--text-tertiary);pointer-events:none">
          <circle cx="7" cy="7" r="4.5"/><path d="M11 11l2.5 2.5" stroke-linecap="round"/>
        </svg>
        <input
          type="text"
          name="q"
          value={@query}
          placeholder="Search everything…"
          class="atrium-input"
          style="padding-left:32px"
          autofocus
        />
      </div>
      <button type="submit" class="atrium-btn atrium-btn-primary">Search</button>
    </div>
  </form>

  <%# ── Empty / too-short state ── %>
  <%= if @query == "" do %>
    <div style="padding:48px;text-align:center;color:var(--text-tertiary);font-size:.875rem">
      Type at least 2 characters to search across documents, people, and tools.
    </div>
  <% end %>

  <%= if @query != "" and String.length(@query) < 2 do %>
    <div style="padding:48px;text-align:center;color:var(--text-tertiary);font-size:.875rem">
      Query too short — please enter at least 2 characters.
    </div>
  <% end %>

  <%# ── No results state ── %>
  <%= if String.length(@query) >= 2 and @documents == [] and @users == [] and @tools == [] do %>
    <div style="padding:48px;text-align:center;color:var(--text-tertiary);font-size:.875rem">
      No results for <strong style="color:var(--text-primary)">"<%= @query %>"</strong>.
    </div>
  <% end %>

  <%# ── Documents ── %>
  <%= if @documents != [] do %>
    <div class="atrium-card" style="margin-bottom:16px">
      <div class="atrium-card-header">
        <div class="atrium-card-title">Documents</div>
        <span class="atrium-badge"><%= length(@documents) %></span>
      </div>
      <table class="atrium-table">
        <thead>
          <tr>
            <th>Title</th>
            <th>Section</th>
            <th>Approved</th>
          </tr>
        </thead>
        <tbody>
          <%= for doc <- @documents do %>
            <tr
              onclick={"window.location='#{~p"/sections/#{doc.section_key}/documents/#{doc.id}"}'"}
              style="cursor:pointer"
            >
              <td style="font-weight:500">
                <a
                  href={~p"/sections/#{doc.section_key}/documents/#{doc.id}"}
                  style="color:var(--text-primary);text-decoration:none"
                >
                  <%= doc.title %>
                </a>
              </td>
              <td style="font-size:.8125rem;color:var(--text-secondary)">
                <%= doc.section_key %>
              </td>
              <td style="font-size:.8125rem;color:var(--text-secondary)">
                <%= if doc.approved_at, do: Calendar.strftime(doc.approved_at, "%d %b %Y"), else: "—" %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% end %>

  <%# ── People ── %>
  <%= if @users != [] do %>
    <div class="atrium-card" style="margin-bottom:16px">
      <div class="atrium-card-header">
        <div class="atrium-card-title">People</div>
        <span class="atrium-badge"><%= length(@users) %></span>
      </div>
      <table class="atrium-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Role</th>
            <th>Department</th>
          </tr>
        </thead>
        <tbody>
          <%= for user <- @users do %>
            <tr
              onclick={"window.location='#{~p"/directory/#{user.id}"}'"}
              style="cursor:pointer"
            >
              <td>
                <div style="display:flex;align-items:center;gap:10px">
                  <div class="atrium-user-avatar" style="width:28px;height:28px;font-size:.6875rem;flex-shrink:0">
                    <%= user.name |> String.split() |> Enum.map(&String.first/1) |> Enum.take(2) |> Enum.join() %>
                  </div>
                  <a
                    href={~p"/directory/#{user.id}"}
                    style="color:var(--text-primary);text-decoration:none;font-weight:500"
                  >
                    <%= user.name %>
                  </a>
                </div>
              </td>
              <td style="font-size:.8125rem;color:var(--text-secondary)"><%= user.role || "—" %></td>
              <td style="font-size:.8125rem;color:var(--text-secondary)"><%= user.department || "—" %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% end %>

  <%# ── Tools ── %>
  <%= if @tools != [] do %>
    <div class="atrium-card">
      <div class="atrium-card-header">
        <div class="atrium-card-title">Tools</div>
        <span class="atrium-badge"><%= length(@tools) %></span>
      </div>
      <table class="atrium-table">
        <thead>
          <tr>
            <th>Label</th>
            <th>Description</th>
            <th>Kind</th>
          </tr>
        </thead>
        <tbody>
          <%= for tool <- @tools do %>
            <tr
              onclick={"window.location='#{~p"/tools"}'"}
              style="cursor:pointer"
            >
              <td style="font-weight:500">
                <a href={~p"/tools"} style="color:var(--text-primary);text-decoration:none">
                  <%= tool.label %>
                </a>
              </td>
              <td style="font-size:.8125rem;color:var(--text-secondary)">
                <%= tool.description || "—" %>
              </td>
              <td>
                <span class="atrium-badge"><%= tool.kind %></span>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% end %>
</div>
```

- [ ] **Step 4: Verify the app compiles**

```bash
mix compile --warnings-as-errors
```

Expected: no errors or warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium_web/controllers/search_controller.ex \
        lib/atrium_web/controllers/search_html.ex \
        lib/atrium_web/controllers/search_html/index.html.heex
git commit -m "feat: add SearchController, SearchHTML module, and search results template"
```

---

## Task 3: Wire router + topbar search input (⌘K and Enter)

**Files:**
- Modify: `lib/atrium_web/router.ex` — add one route
- Modify: `lib/atrium_web/components/layouts/app.html.heex` — add `id` + `data-search-input` to the existing input
- Modify: `assets/js/app.js` — append topbar search JS

### Background

The router change is one line inside the existing `pipe_through [:authenticated]` scope (around line 91 in the current file). Add it directly after the existing `get "/audit/export"` cluster, before `/home` — it doesn't matter exactly where inside the scope, but grouping it near simple get routes keeps it readable.

The topbar input currently has no `id` or `name`. To navigate on submit, add `id="topbar-search"` so the JS can find it. Also add `data-search-input` as a hook marker — a consistent pattern when JS needs to target a specific element without coupling to CSS class names.

The ⌘K shortcut focuses the input; pressing Enter in the focused input navigates to `/search?q=<value>`. Pressing Escape blurs it. This is implemented as a small self-contained IIFE appended to `app.js`.

- [ ] **Step 1: Add the route to `lib/atrium_web/router.ex`**

Open the file. Inside the `scope "/" do` block that has `pipe_through [:authenticated]` (lines 90–170), add one line after `get "/audit/export", AuditViewerController, :export`:

```elixir
      get "/search", SearchController, :index
```

The relevant section of the file should look like this after the change:

```elixir
    scope "/" do
      pipe_through [:authenticated]
      get "/", PageController, :home
      get "/audit", AuditViewerController, :index
      get "/audit/export", AuditViewerController, :export

      get "/search", SearchController, :index

      get  "/home",                              HomeController, :show
      # ... rest unchanged
    end
```

- [ ] **Step 2: Add `id` and `data-search-input` to the topbar input in `lib/atrium_web/components/layouts/app.html.heex`**

Find the existing topbar search input (line 15):

```heex
    <input type="text" placeholder="Search…" />
```

Replace it with:

```heex
    <input
      type="text"
      id="topbar-search"
      data-search-input
      placeholder="Search…"
      autocomplete="off"
    />
```

The surrounding `<div class="atrium-topbar-search">` and SVG icon are unchanged.

- [ ] **Step 3: Append topbar search JS to `assets/js/app.js`**

Add the following block at the bottom of `assets/js/app.js`, after the existing `mountIslands()` call and its `DOMContentLoaded` guard:

```js
// ── Topbar search: Enter navigates, ⌘K (or Ctrl+K) focuses ──────────────────
;(function () {
  function getInput() {
    return document.getElementById("topbar-search")
  }

  document.addEventListener("keydown", function (e) {
    const input = getInput()
    if (!input) return

    // ⌘K on Mac, Ctrl+K on Windows/Linux — focus the search input
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault()
      input.focus()
      input.select()
      return
    }

    // Escape — blur if the input is focused
    if (e.key === "Escape" && document.activeElement === input) {
      input.blur()
    }
  })

  document.addEventListener("DOMContentLoaded", function () {
    const input = getInput()
    if (!input) return

    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        e.preventDefault()
        const q = input.value.trim()
        if (q.length >= 2) {
          window.location.href = "/search?q=" + encodeURIComponent(q)
        }
      }
    })
  })
})()
```

- [ ] **Step 4: Verify the app compiles and routes are correct**

```bash
mix compile --warnings-as-errors
mix phx.routes | grep search
```

Expected output from the routes command:
```
GET  /search  AtriumWeb.SearchController :index
```

- [ ] **Step 5: Run the full test suite to confirm nothing regressed**

```bash
mix test
```

Expected: all existing tests pass. The new search tests from Task 1 also pass.

- [ ] **Step 6: Commit**

```bash
git add lib/atrium_web/router.ex \
        lib/atrium_web/components/layouts/app.html.heex \
        assets/js/app.js
git commit -m "feat: wire /search route and topbar search input with Enter + cmd-K navigation"
```

---

## Task 4: Final integration commit

**Files:** none new — smoke-test and tidy up.

- [ ] **Step 1: Run the full test suite one final time**

```bash
mix test
```

Expected: green. If any test fails, fix it before proceeding.

- [ ] **Step 2: Verify the search page renders without crash in dev**

Start the dev server (`mix phx.server`) and visit:

- `http://<tenant-host>/search` — should render an empty state ("Type at least 2 characters…").
- `http://<tenant-host>/search?q=a` — should render the "query too short" message.
- `http://<tenant-host>/search?q=po` — should render results (or "No results") with no crash.
- Press ⌘K in the browser — topbar input should focus.
- Type `po` in the topbar input and press Enter — should navigate to `/search?q=po`.

- [ ] **Step 3: Final commit**

```bash
git add -p   # stage any last-minute fixes only
git commit -m "feat: global search — context, controller, template, topbar wiring"
```

If there were no last-minute changes, skip this step (the previous commits already capture everything).

---

## Self-review

### Spec coverage

| Requirement | Task |
|---|---|
| `Atrium.Search` context with `search_documents/3`, `search_users/3`, `search_tools/2` | Task 1 |
| ILIKE queries, minimum 2-char guard | Task 1 |
| Filter documents by sections user can view | Task 2 (controller: `viewable_section_keys` from `nav`) |
| Only `status: "approved"` documents | Task 1 (`search_documents` query) |
| Users only if user can view `directory` | Task 2 (controller `Policy.can?` check) |
| Tools only if user can view `tools` | Task 2 (controller `Policy.can?` check) |
| Results grouped by type | Task 2 (template: three separate `atrium-card` blocks) |
| Empty query shows empty state | Task 2 (template: `@query == ""` branch) |
| `GET /search?q=` route in authenticated scope | Task 3 |
| Topbar input wired to navigate on Enter | Task 3 |
| ⌘K focuses topbar input | Task 3 |
| TDD — failing test first | Task 1 steps 1–2 |
| Frequent commits | Each task ends with a commit step |
| Existing patterns followed exactly | Controller uses `use AtriumWeb, :controller` + `conn.assigns`; HTML module uses `embed_templates`; template uses `atrium-*` classes + CSS vars |

### Type consistency check

- `search_documents(prefix, query, section_keys)` — called in controller as `Search.search_documents(prefix, query, viewable_section_keys)` where `viewable_section_keys` is `[String.t()]`. Matches spec.
- `search_users(prefix, query)` — two-arg. Controller calls `Search.search_users(prefix, query)`. Matches.
- `search_tools(prefix, query)` — two-arg. Controller calls `Search.search_tools(prefix, query)`. Matches.
- Template assigns: `@query`, `@documents`, `@users`, `@tools` — all assigned in `render/3` call in controller. No mismatch.
