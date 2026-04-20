# Feedback & Surveys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Feedback & Surveys section a dedicated landing page that shows published surveys to all staff (with a "Fill in" CTA) and gives P&C editors a management view with submission counts. Add it to the nav as a dedicated section.

**Architecture:** New `FeedbackController` at `/feedback` (dedicated, like `ComplianceController`). Reuses all existing `Forms` context and generic `FormController` routes for the actual form/submission management. The landing page is a thin wrapper: staff see published surveys with a call-to-action; P&C sees all statuses + submission count. Add "feedback" to the `dedicated` nav list in `app.html.heex`.

**Tech Stack:** Phoenix 1.8, Ecto, `atrium-*` CSS, no LiveView, no Tailwind.

---

## File Structure

**New files:**
- `lib/atrium_web/controllers/feedback_controller.ex`
- `lib/atrium_web/controllers/feedback_html.ex`
- `lib/atrium_web/controllers/feedback_html/index.html.heex`

**Modified files:**
- `lib/atrium_web/router.ex` — add `get "/feedback", FeedbackController, :index`
- `lib/atrium_web/components/layouts/app.html.heex` — add "feedback" to dedicated list
- `lib/atrium/forms.ex` — add `count_submissions/2` helper

---

## Task 1: FeedbackController + HTML module + template + route + nav

**Files:**
- Create: `lib/atrium_web/controllers/feedback_controller.ex`
- Create: `lib/atrium_web/controllers/feedback_html.ex`
- Create: `lib/atrium_web/controllers/feedback_html/index.html.heex`
- Modify: `lib/atrium_web/router.ex`
- Modify: `lib/atrium_web/components/layouts/app.html.heex`
- Modify: `lib/atrium/forms.ex`
- Create: `test/atrium_web/controllers/feedback_controller_test.exs`

### Controller

```elixir
# lib/atrium_web/controllers/feedback_controller.ex
defmodule AtriumWeb.FeedbackController do
  use AtriumWeb, :controller
  alias Atrium.Forms

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "feedback"}]
       when action in [:index]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "feedback"})

    published = Forms.list_forms(prefix, "feedback", status: "published")

    {all_forms, submission_counts} =
      if can_edit do
        forms = Forms.list_forms(prefix, "feedback")
        counts = Map.new(forms, fn f -> {f.id, Forms.count_submissions(prefix, f.id)} end)
        {forms, counts}
      else
        {published, %{}}
      end

    render(conn, :index,
      published: published,
      all_forms: all_forms,
      submission_counts: submission_counts,
      can_edit: can_edit
    )
  end
end
```

### HTML module

```elixir
# lib/atrium_web/controllers/feedback_html.ex
defmodule AtriumWeb.FeedbackHTML do
  use AtriumWeb, :html
  embed_templates "feedback_html/*"
end
```

### `count_submissions/2` in `lib/atrium/forms.ex`

Add this public function alongside the other `list_submissions` functions:

```elixir
def count_submissions(prefix, form_id) do
  Repo.aggregate(
    from(s in FormSubmission, where: s.form_id == ^form_id),
    :count,
    :id,
    prefix: prefix
  )
end
```

### Template `lib/atrium_web/controllers/feedback_html/index.html.heex`

```heex
<div class="atrium-anim">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:28px">
    <div>
      <div class="atrium-page-eyebrow">Feedback</div>
      <h1 class="atrium-page-title">Feedback &amp; Surveys</h1>
    </div>
    <%= if @can_edit do %>
      <a href={~p"/sections/feedback/forms/new"} class="atrium-btn atrium-btn-primary">New survey</a>
    <% end %>
  </div>

  <%= if !@can_edit do %>
    <%# Staff view: published surveys only %>
    <div class="atrium-card">
      <div class="atrium-card-header"><div class="atrium-card-title">Open surveys</div></div>
      <table class="atrium-table">
        <thead>
          <tr>
            <th>Survey</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <%= for form <- @published do %>
            <tr>
              <td style="font-weight:500"><%= form.title %></td>
              <td style="text-align:right">
                <a href={~p"/sections/feedback/forms/#{form.id}/submit"} class="atrium-btn atrium-btn-primary" style="height:28px;font-size:.8125rem">Fill in</a>
              </td>
            </tr>
          <% end %>
          <%= if @published == [] do %>
            <tr><td colspan="2" style="padding:32px;text-align:center;color:var(--text-tertiary)">No open surveys right now.</td></tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <%# P&C editor view: all forms with submission counts %>
    <div class="atrium-card">
      <div class="atrium-card-header"><div class="atrium-card-title">All surveys</div></div>
      <table class="atrium-table">
        <thead>
          <tr>
            <th>Survey</th>
            <th>Status</th>
            <th>Responses</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <%= for form <- @all_forms do %>
            <tr>
              <td style="font-weight:500">
                <a href={~p"/sections/feedback/forms/#{form.id}"} style="color:var(--text-primary);text-decoration:none"><%= form.title %></a>
              </td>
              <td>
                <span class={"atrium-badge atrium-badge-#{form.status}"}><%= form.status %></span>
              </td>
              <td style="font-size:.875rem;color:var(--text-secondary)">
                <%= Map.get(@submission_counts, form.id, 0) %>
              </td>
              <td style="text-align:right">
                <%= if form.status == "published" do %>
                  <a href={~p"/sections/feedback/forms/#{form.id}/submissions"} class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.8125rem">Responses</a>
                <% else %>
                  <a href={~p"/sections/feedback/forms/#{form.id}"} class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.8125rem">View</a>
                <% end %>
              </td>
            </tr>
          <% end %>
          <%= if @all_forms == [] do %>
            <tr><td colspan="4" style="padding:32px;text-align:center;color:var(--text-tertiary)">No surveys yet. <a href={~p"/sections/feedback/forms/new"} style="color:var(--blue-600)">Create one</a>.</td></tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% end %>
</div>
```

### Router change

In `lib/atrium_web/router.ex`, add after `get "/compliance", ComplianceController, :index`:

```elixir
get "/feedback", FeedbackController, :index
```

### Nav change

In `lib/atrium_web/components/layouts/app.html.heex`, change:

```elixir
<% dedicated = ~w(home news directory tools compliance helpdesk events learning) %>
```

to:

```elixir
<% dedicated = ~w(home news directory tools compliance helpdesk events learning feedback) %>
```

### Test

```elixir
# test/atrium_web/controllers/feedback_controller_test.exs
defmodule AtriumWeb.FeedbackControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Accounts, Authorization, Tenants, Forms}
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "fb_#{:erlang.unique_integer([:positive])}"
    host = "#{slug}.atrium.example"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Feedback Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: staff}} = Accounts.invite_user(prefix, %{
      email: "fb_staff_#{System.unique_integer([:positive])}@example.com",
      name: "Staff"
    })
    {:ok, staff} = Accounts.activate_user_with_password(prefix, staff, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "feedback", {:user, staff.id}, :view)

    {:ok, %{user: editor}} = Accounts.invite_user(prefix, %{
      email: "fb_editor_#{System.unique_integer([:positive])}@example.com",
      name: "Editor"
    })
    {:ok, editor} = Accounts.activate_user_with_password(prefix, editor, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "feedback", {:user, editor.id}, :view)
    Authorization.grant_section(prefix, "feedback", {:user, editor.id}, :edit)

    staff_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: staff.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    editor_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: editor.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    {:ok, staff_conn: staff_conn, editor_conn: editor_conn, prefix: prefix, staff: staff, editor: editor}
  end

  defp create_published_form(prefix, user) do
    {:ok, form} = Forms.create_form(prefix, %{
      "title" => "Q1 Pulse Survey",
      "section_key" => "feedback"
    }, user)
    {:ok, form} = Forms.publish_form(prefix, form, [
      %{"id" => "q1", "type" => "text", "label" => "How are you?", "required" => false}
    ], user)
    form
  end

  test "GET /feedback shows open surveys to staff", %{staff_conn: staff_conn, prefix: prefix, editor: editor} do
    create_published_form(prefix, editor)
    conn = get(staff_conn, "/feedback")
    assert html_response(conn, 200) =~ "Q1 Pulse Survey"
  end

  test "GET /feedback does not show draft surveys to staff", %{staff_conn: staff_conn, prefix: prefix, editor: editor} do
    {:ok, _} = Forms.create_form(prefix, %{"title" => "Draft Survey", "section_key" => "feedback"}, editor)
    conn = get(staff_conn, "/feedback")
    html = html_response(conn, 200)
    refute html =~ "Draft Survey"
  end

  test "GET /feedback shows all surveys + submission counts to editors", %{editor_conn: editor_conn, prefix: prefix, editor: editor} do
    create_published_form(prefix, editor)
    conn = get(editor_conn, "/feedback")
    html = html_response(conn, 200)
    assert html =~ "Q1 Pulse Survey"
    assert html =~ "published"
    assert html =~ "Responses"
  end

  test "GET /feedback shows New survey button to editors", %{editor_conn: editor_conn} do
    conn = get(editor_conn, "/feedback")
    assert html_response(conn, 200) =~ "New survey"
  end

  test "GET /feedback does not show New survey button to staff", %{staff_conn: staff_conn} do
    conn = get(staff_conn, "/feedback")
    html = html_response(conn, 200)
    refute html =~ "New survey"
  end
end
```

### Steps

- [ ] **Step 1: Write failing tests**

Write `test/atrium_web/controllers/feedback_controller_test.exs` as above. Run `mix test test/atrium_web/controllers/feedback_controller_test.exs` — expect failure (route not found).

- [ ] **Step 2: Add `count_submissions/2` to `lib/atrium/forms.ex`**

Add the function as specified above. Check that `FormSubmission` is already aliased in the module (it is — `alias Atrium.Forms.{Form, FormVersion, FormSubmission, FormSubmissionReview}`).

- [ ] **Step 3: Create `lib/atrium_web/controllers/feedback_html.ex`**

As specified above.

- [ ] **Step 4: Create `lib/atrium_web/controllers/feedback_controller.ex`**

As specified above.

- [ ] **Step 5: Create `lib/atrium_web/controllers/feedback_html/index.html.heex`**

As specified above. Create the `feedback_html/` directory first.

- [ ] **Step 6: Add route to `lib/atrium_web/router.ex`**

Add `get "/feedback", FeedbackController, :index` after the compliance route.

- [ ] **Step 7: Add "feedback" to dedicated nav list in `lib/atrium_web/components/layouts/app.html.heex`**

Change the dedicated list as specified above.

- [ ] **Step 8: Run all tests**

```bash
mix test test/atrium_web/controllers/feedback_controller_test.exs
```

Expected: 5 tests, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add lib/atrium/forms.ex \
        lib/atrium_web/controllers/feedback_controller.ex \
        lib/atrium_web/controllers/feedback_html.ex \
        lib/atrium_web/controllers/feedback_html/index.html.heex \
        lib/atrium_web/router.ex \
        lib/atrium_web/components/layouts/app.html.heex \
        test/atrium_web/controllers/feedback_controller_test.exs
git commit -m "feat: add Feedback & Surveys dedicated landing page with P&C analysis view"
```
