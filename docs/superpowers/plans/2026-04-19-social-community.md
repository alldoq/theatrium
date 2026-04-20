# Social / Community Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Community section with a discussion board where all staff can post topics and reply, with editors able to pin and delete any post.

**Architecture:** New `Atrium.Community` context with `community_posts` and `community_replies` tables. `CommunityController` at `/community` (dedicated nav). Posts have a title + body; replies have a body only. Editors can delete any post/reply; authors can delete their own. Add "community" to the dedicated nav list.

**Tech Stack:** Phoenix 1.8, Ecto, Triplex schema-per-tenant, `atrium-*` CSS, no LiveView, no Tailwind.

---

## File Structure

**New files:**
- `priv/repo/tenant_migrations/20260502000005_create_community.exs`
- `lib/atrium/community/post.ex`
- `lib/atrium/community/reply.ex`
- `lib/atrium/community.ex`
- `lib/atrium_web/controllers/community_controller.ex`
- `lib/atrium_web/controllers/community_html.ex`
- `lib/atrium_web/controllers/community_html/index.html.heex`
- `lib/atrium_web/controllers/community_html/show.html.heex`
- `lib/atrium_web/controllers/community_html/new.html.heex`
- `test/atrium/community_test.exs`
- `test/atrium_web/controllers/community_controller_test.exs`

**Modified files:**
- `lib/atrium_web/router.ex` — add community routes
- `lib/atrium_web/components/layouts/app.html.heex` — add "community" to dedicated list

---

## Task 1: Migration + schemas + context + unit tests

**Files:**
- Create: `priv/repo/tenant_migrations/20260502000005_create_community.exs`
- Create: `lib/atrium/community/post.ex`
- Create: `lib/atrium/community/reply.ex`
- Create: `lib/atrium/community.ex`
- Create: `test/atrium/community_test.exs`

### Migration

```elixir
# priv/repo/tenant_migrations/20260502000005_create_community.exs
defmodule Atrium.Repo.TenantMigrations.CreateCommunity do
  use Ecto.Migration

  def change do
    create table(:community_posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :author_id, :binary_id, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :pinned, :boolean, null: false, default: false
      timestamps(type: :timestamptz)
    end

    create index(:community_posts, [:inserted_at])

    create table(:community_replies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:community_posts, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, :binary_id, null: false
      add :body, :text, null: false
      timestamps(type: :timestamptz)
    end

    create index(:community_replies, [:post_id])
  end
end
```

### Schema: Post

```elixir
# lib/atrium/community/post.ex
defmodule Atrium.Community.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_posts" do
    field :author_id, :binary_id
    field :title, :string
    field :body, :string
    field :pinned, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:author_id, :title, :body, :pinned])
    |> validate_required([:author_id, :title, :body])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:body, min: 1, max: 10000)
  end
end
```

### Schema: Reply

```elixir
# lib/atrium/community/reply.ex
defmodule Atrium.Community.Reply do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_replies" do
    field :post_id, :binary_id
    field :author_id, :binary_id
    field :body, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reply, attrs) do
    reply
    |> cast(attrs, [:post_id, :author_id, :body])
    |> validate_required([:post_id, :author_id, :body])
    |> validate_length(:body, min: 1, max: 4000)
  end
end
```

### Context

```elixir
# lib/atrium/community.ex
defmodule Atrium.Community do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Community.{Post, Reply}

  def list_posts(prefix) do
    Repo.all(
      from(p in Post, order_by: [desc: p.pinned, desc: p.inserted_at]),
      prefix: prefix
    )
  end

  def get_post!(prefix, id) do
    Repo.get!(Post, id, prefix: prefix)
  end

  def create_post(prefix, attrs) do
    changeset = Post.changeset(%Post{}, stringify(attrs))
    Repo.insert(changeset, prefix: prefix)
  end

  def delete_post(prefix, post_id) do
    case Repo.get(Post, post_id, prefix: prefix) do
      nil -> {:error, :not_found}
      post ->
        case Repo.delete(post, prefix: prefix) do
          {:ok, _} -> :ok
          {:error, _} = err -> err
        end
    end
  end

  def pin_post(prefix, post_id) do
    case Repo.get(Post, post_id, prefix: prefix) do
      nil -> {:error, :not_found}
      post ->
        post
        |> Post.changeset(%{"pinned" => true})
        |> Repo.update(prefix: prefix)
    end
  end

  def unpin_post(prefix, post_id) do
    case Repo.get(Post, post_id, prefix: prefix) do
      nil -> {:error, :not_found}
      post ->
        post
        |> Post.changeset(%{"pinned" => false})
        |> Repo.update(prefix: prefix)
    end
  end

  def list_replies(prefix, post_id) do
    Repo.all(
      from(r in Reply, where: r.post_id == ^post_id, order_by: [asc: r.inserted_at]),
      prefix: prefix
    )
  end

  def add_reply(prefix, post_id, attrs) do
    changeset = Reply.changeset(%Reply{}, Map.put(stringify(attrs), "post_id", post_id))
    Repo.insert(changeset, prefix: prefix)
  end

  def get_reply(prefix, reply_id) do
    Repo.get(Reply, reply_id, prefix: prefix)
  end

  def delete_reply(prefix, reply_id) do
    case Repo.get(Reply, reply_id, prefix: prefix) do
      nil -> {:error, :not_found}
      reply ->
        case Repo.delete(reply, prefix: prefix) do
          {:ok, _} -> :ok
          {:error, _} = err -> err
        end
    end
  end

  def count_replies(prefix, post_id) do
    Repo.aggregate(
      from(r in Reply, where: r.post_id == ^post_id),
      :count,
      :id,
      prefix: prefix
    )
  end

  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
```

### Tests

```elixir
# test/atrium/community_test.exs
defmodule Atrium.CommunityTest do
  use Atrium.TenantCase

  alias Atrium.Community

  test "create_post/2 creates a post", %{prefix: prefix, user: user} do
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Hello", "body" => "World"})
    assert post.title == "Hello"
    assert post.author_id == user.id
    assert post.pinned == false
  end

  test "list_posts/1 returns pinned first", %{prefix: prefix, user: user} do
    {:ok, normal} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Normal", "body" => "B"})
    {:ok, pinned} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Pinned", "body" => "B"})
    Community.pin_post(prefix, pinned.id)
    posts = Community.list_posts(prefix)
    pinned_ids = posts |> Enum.filter(& &1.pinned) |> Enum.map(& &1.id)
    normal_ids = posts |> Enum.reject(& &1.pinned) |> Enum.map(& &1.id)
    assert pinned.id in pinned_ids
    assert normal.id in normal_ids
    assert Enum.find_index(posts, & &1.id == pinned.id) < Enum.find_index(posts, & &1.id == normal.id)
  end

  test "delete_post/2 removes post", %{prefix: prefix, user: user} do
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Del", "body" => "B"})
    assert :ok = Community.delete_post(prefix, post.id)
    assert_raise Ecto.NoResultsError, fn -> Community.get_post!(prefix, post.id) end
  end

  test "delete_post/2 returns error for missing post", %{prefix: prefix} do
    assert {:error, :not_found} = Community.delete_post(prefix, Ecto.UUID.generate())
  end

  test "add_reply/3 and list_replies/2", %{prefix: prefix, user: user} do
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "T", "body" => "B"})
    {:ok, _} = Community.add_reply(prefix, post.id, %{"author_id" => user.id, "body" => "Reply 1"})
    {:ok, _} = Community.add_reply(prefix, post.id, %{"author_id" => user.id, "body" => "Reply 2"})
    replies = Community.list_replies(prefix, post.id)
    assert length(replies) == 2
    assert hd(replies).body == "Reply 1"
  end

  test "delete_reply/2 removes reply", %{prefix: prefix, user: user} do
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "T", "body" => "B"})
    {:ok, reply} = Community.add_reply(prefix, post.id, %{"author_id" => user.id, "body" => "Bye"})
    assert :ok = Community.delete_reply(prefix, reply.id)
    assert Community.list_replies(prefix, post.id) == []
  end

  test "delete_reply/2 returns error for missing reply", %{prefix: prefix} do
    assert {:error, :not_found} = Community.delete_reply(prefix, Ecto.UUID.generate())
  end

  test "count_replies/2 counts correctly", %{prefix: prefix, user: user} do
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "T", "body" => "B"})
    {:ok, _} = Community.add_reply(prefix, post.id, %{"author_id" => user.id, "body" => "R"})
    assert Community.count_replies(prefix, post.id) == 1
  end

  test "pin_post/2 sets pinned true", %{prefix: prefix, user: user} do
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "T", "body" => "B"})
    {:ok, pinned} = Community.pin_post(prefix, post.id)
    assert pinned.pinned == true
  end

  test "unpin_post/2 sets pinned false", %{prefix: prefix, user: user} do
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "T", "body" => "B"})
    {:ok, _} = Community.pin_post(prefix, post.id)
    {:ok, unpinned} = Community.unpin_post(prefix, post.id)
    assert unpinned.pinned == false
  end
end
```

**Note on TenantCase:** Check how `TenantCase` provides `%{prefix: prefix, user: user}` in `test/support/tenant_case.ex`. If it only provides `prefix`, create the user in a local `setup` block using the same pattern as `projects_test.exs` did before it was converted. Use whatever pattern actually works for the existing TenantCase.

### Steps

- [ ] **Step 1: Create migration** at `priv/repo/tenant_migrations/20260502000005_create_community.exs` as above.

- [ ] **Step 2: Create schemas** `lib/atrium/community/post.ex` and `lib/atrium/community/reply.ex` as above.

- [ ] **Step 3: Create context** `lib/atrium/community.ex` as above.

- [ ] **Step 4: Create test file** `test/atrium/community_test.exs` as above. First check `test/support/tenant_case.ex` to understand what it provides so you can write the setup correctly.

- [ ] **Step 5: Run migration**

```bash
mix triplex.migrate
```

- [ ] **Step 6: Run tests**

```bash
mix test test/atrium/community_test.exs
```

Expected: 9 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add priv/repo/tenant_migrations/20260502000005_create_community.exs \
        lib/atrium/community/post.ex \
        lib/atrium/community/reply.ex \
        lib/atrium/community.ex \
        test/atrium/community_test.exs
git commit -m "feat: add Community context with posts, replies, and pin/unpin"
```

---

## Task 2: CommunityController + templates + routes + nav

**Files:**
- Create: `lib/atrium_web/controllers/community_controller.ex`
- Create: `lib/atrium_web/controllers/community_html.ex`
- Create: `lib/atrium_web/controllers/community_html/index.html.heex`
- Create: `lib/atrium_web/controllers/community_html/show.html.heex`
- Create: `lib/atrium_web/controllers/community_html/new.html.heex`
- Modify: `lib/atrium_web/router.ex`
- Modify: `lib/atrium_web/components/layouts/app.html.heex`
- Create: `test/atrium_web/controllers/community_controller_test.exs`

### Controller

```elixir
# lib/atrium_web/controllers/community_controller.ex
defmodule AtriumWeb.CommunityController do
  use AtriumWeb, :controller
  alias Atrium.Community

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "community"}]
       when action in [:index, :show, :new, :create, :add_reply, :delete_reply, :delete_post, :pin_post, :unpin_post]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "community"}]
       when action in [:pin_post, :unpin_post]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "community"})
    posts = Community.list_posts(prefix)
    reply_counts = Map.new(posts, fn p -> {p.id, Community.count_replies(prefix, p.id)} end)
    all_users = Atrium.Accounts.list_users(prefix)
    render(conn, :index, posts: posts, reply_counts: reply_counts, can_edit: can_edit, all_users: all_users)
  end

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"post" => %{"title" => title, "body" => body}}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Community.create_post(prefix, %{"author_id" => user.id, "title" => title, "body" => body}) do
      {:ok, post} ->
        conn
        |> put_flash(:info, "Post created.")
        |> redirect(to: ~p"/community/#{post.id}")
      {:error, _} ->
        conn
        |> put_flash(:error, "Could not create post.")
        |> redirect(to: ~p"/community/new")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Title and body are required.")
    |> redirect(to: ~p"/community/new")
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    post = Community.get_post!(prefix, id)
    replies = Community.list_replies(prefix, id)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "community"})
    all_users = Atrium.Accounts.list_users(prefix)
    render(conn, :show,
      post: post,
      replies: replies,
      can_edit: can_edit,
      all_users: all_users,
      current_user: user
    )
  end

  def add_reply(conn, %{"id" => id, "reply" => %{"body" => body}}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Community.add_reply(prefix, id, %{"author_id" => user.id, "body" => body}) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Reply posted.")
        |> redirect(to: ~p"/community/#{id}" <> "#replies")
      {:error, _} ->
        conn
        |> put_flash(:error, "Reply cannot be blank.")
        |> redirect(to: ~p"/community/#{id}" <> "#replies")
    end
  end

  def add_reply(conn, %{"id" => id}) do
    conn
    |> put_flash(:error, "Reply cannot be blank.")
    |> redirect(to: ~p"/community/#{id}" <> "#replies")
  end

  def delete_reply(conn, %{"id" => id, "rid" => rid}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "community"})
    reply = Community.get_reply(prefix, rid)

    cond do
      is_nil(reply) ->
        redirect(conn, to: ~p"/community/#{id}" <> "#replies")
      can_edit || reply.author_id == user.id ->
        Community.delete_reply(prefix, rid)
        conn
        |> put_flash(:info, "Reply deleted.")
        |> redirect(to: ~p"/community/#{id}" <> "#replies")
      true ->
        conn
        |> put_flash(:error, "Not authorised.")
        |> redirect(to: ~p"/community/#{id}" <> "#replies")
    end
  end

  def delete_post(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "community"})
    post = Community.get_post!(prefix, id)

    if can_edit || post.author_id == user.id do
      Community.delete_post(prefix, id)
      conn
      |> put_flash(:info, "Post deleted.")
      |> redirect(to: ~p"/community")
    else
      conn
      |> put_flash(:error, "Not authorised.")
      |> redirect(to: ~p"/community/#{id}")
    end
  end

  def pin_post(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    Community.pin_post(prefix, id)
    redirect(conn, to: ~p"/community")
  end

  def unpin_post(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    Community.unpin_post(prefix, id)
    redirect(conn, to: ~p"/community")
  end
end
```

### HTML module

```elixir
# lib/atrium_web/controllers/community_html.ex
defmodule AtriumWeb.CommunityHTML do
  use AtriumWeb, :html
  embed_templates "community_html/*"
end
```

### Template: index

```heex
<%# lib/atrium_web/controllers/community_html/index.html.heex %>
<div class="atrium-anim">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:28px">
    <div>
      <div class="atrium-page-eyebrow">Community</div>
      <h1 class="atrium-page-title">Discussion Board</h1>
    </div>
    <a href={~p"/community/new"} class="atrium-btn atrium-btn-primary">New post</a>
  </div>

  <div class="atrium-card">
    <table class="atrium-table">
      <thead>
        <tr>
          <th>Topic</th>
          <th>Author</th>
          <th>Replies</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <%= for post <- @posts do %>
          <% author = Enum.find(@all_users, fn u -> u.id == post.author_id end) %>
          <tr>
            <td style="font-weight:500">
              <%= if post.pinned do %><span style="font-size:.75rem;color:var(--blue-600);margin-right:6px">📌</span><% end %>
              <a href={~p"/community/#{post.id}"} style="color:var(--text-primary);text-decoration:none"><%= post.title %></a>
            </td>
            <td style="font-size:.875rem;color:var(--text-secondary)">
              <%= if author, do: author.name, else: "Unknown" %>
            </td>
            <td style="font-size:.875rem;color:var(--text-secondary)">
              <%= Map.get(@reply_counts, post.id, 0) %>
            </td>
            <td style="text-align:right;display:flex;gap:6px;justify-content:flex-end">
              <%= if @can_edit do %>
                <%= if post.pinned do %>
                  <form action={~p"/community/#{post.id}/unpin"} method="post" style="display:inline">
                    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                    <button type="submit" class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.75rem">Unpin</button>
                  </form>
                <% else %>
                  <form action={~p"/community/#{post.id}/pin"} method="post" style="display:inline">
                    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                    <button type="submit" class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.75rem">Pin</button>
                  </form>
                <% end %>
              <% end %>
              <a href={~p"/community/#{post.id}"} class="atrium-btn atrium-btn-ghost" style="height:28px;font-size:.8125rem">View</a>
            </td>
          </tr>
        <% end %>
        <%= if @posts == [] do %>
          <tr>
            <td colspan="4" style="padding:32px;text-align:center;color:var(--text-tertiary)">
              No posts yet. <a href={~p"/community/new"} style="color:var(--blue-600)">Start a discussion</a>.
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
<%# lib/atrium_web/controllers/community_html/show.html.heex %>
<% author = Enum.find(@all_users, fn u -> u.id == @post.author_id end) %>
<div class="atrium-anim">
  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow"><a href={~p"/community"} style="color:inherit;text-decoration:none">Community</a></div>
    <div style="display:flex;align-items:flex-start;justify-content:space-between">
      <h1 class="atrium-page-title"><%= @post.title %></h1>
      <%= if @can_edit || @post.author_id == @current_user.id do %>
        <form action={~p"/community/#{@post.id}/delete"} method="post" style="display:inline">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button type="submit" class="atrium-btn atrium-btn-ghost" onclick="return confirm('Delete this post?')">Delete post</button>
        </form>
      <% end %>
    </div>
    <div style="font-size:.8125rem;color:var(--text-tertiary)">
      Posted by <%= if author, do: author.name, else: "Unknown" %> · <%= Calendar.strftime(@post.inserted_at, "%b %-d, %Y") %>
    </div>
  </div>

  <div class="atrium-card" style="margin-bottom:24px">
    <div style="padding:20px;white-space:pre-wrap"><%= @post.body %></div>
  </div>

  <div class="atrium-card" id="replies">
    <div class="atrium-card-header">
      <div class="atrium-card-title">Replies (<%= length(@replies) %>)</div>
    </div>
    <div style="padding:0 20px">
      <%= for reply <- @replies do %>
        <% reply_author = Enum.find(@all_users, fn u -> u.id == reply.author_id end) %>
        <div style="border-bottom:1px solid var(--border);padding:12px 0;display:flex;gap:12px;align-items:flex-start">
          <div style="flex:1">
            <div style="font-size:.8125rem;color:var(--text-tertiary);margin-bottom:4px">
              <%= if reply_author, do: reply_author.name, else: "Unknown" %> · <%= Calendar.strftime(reply.inserted_at, "%b %-d, %Y") %>
            </div>
            <div style="white-space:pre-wrap"><%= reply.body %></div>
          </div>
          <%= if @can_edit || reply.author_id == @current_user.id do %>
            <form action={~p"/community/#{@post.id}/replies/#{reply.id}/delete"} method="post" style="display:inline">
              <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
              <button type="submit" class="atrium-btn atrium-btn-ghost" style="height:24px;font-size:.75rem;padding:0 8px">Delete</button>
            </form>
          <% end %>
        </div>
      <% end %>
      <%= if @replies == [] do %>
        <div style="padding:32px 0;text-align:center;color:var(--text-tertiary)">No replies yet. Be the first to reply.</div>
      <% end %>
    </div>
    <div style="padding:16px 20px;border-top:1px solid var(--border)">
      <form action={~p"/community/#{@post.id}/replies"} method="post">
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <textarea name="reply[body]" placeholder="Write a reply…" rows="3" style="width:100%;padding:8px 10px;border:1px solid var(--border);border-radius:6px;font-size:.875rem;resize:vertical;background:var(--surface);color:var(--text-primary)"></textarea>
        <div style="margin-top:8px;text-align:right">
          <button type="submit" class="atrium-btn atrium-btn-primary" style="height:28px;font-size:.8125rem">Post reply</button>
        </div>
      </form>
    </div>
  </div>
</div>
```

### Template: new

```heex
<%# lib/atrium_web/controllers/community_html/new.html.heex %>
<div class="atrium-anim">
  <div style="margin-bottom:28px">
    <div class="atrium-page-eyebrow"><a href={~p"/community"} style="color:inherit;text-decoration:none">Community</a></div>
    <h1 class="atrium-page-title">New Post</h1>
  </div>

  <div class="atrium-card" style="max-width:700px">
    <div style="padding:24px">
      <form action={~p"/community"} method="post">
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <div style="margin-bottom:16px">
          <label style="display:block;font-size:.875rem;font-weight:500;margin-bottom:4px">Title</label>
          <input type="text" name="post[title]" style="width:100%;padding:8px 10px;border:1px solid var(--border);border-radius:6px;font-size:.875rem;background:var(--surface);color:var(--text-primary)" />
        </div>
        <div style="margin-bottom:16px">
          <label style="display:block;font-size:.875rem;font-weight:500;margin-bottom:4px">Body</label>
          <textarea name="post[body]" rows="8" style="width:100%;padding:8px 10px;border:1px solid var(--border);border-radius:6px;font-size:.875rem;resize:vertical;background:var(--surface);color:var(--text-primary)"></textarea>
        </div>
        <div style="display:flex;gap:8px;justify-content:flex-end">
          <a href={~p"/community"} class="atrium-btn atrium-btn-ghost">Cancel</a>
          <button type="submit" class="atrium-btn atrium-btn-primary">Post</button>
        </div>
      </form>
    </div>
  </div>
</div>
```

### Router change

In `lib/atrium_web/router.ex`, add after the projects routes (after line 129, before `/helpdesk`):

```elixir
get    "/community",                                      CommunityController, :index
get    "/community/new",                                  CommunityController, :new
post   "/community",                                      CommunityController, :create
get    "/community/:id",                                  CommunityController, :show
post   "/community/:id/delete",                           CommunityController, :delete_post
post   "/community/:id/pin",                              CommunityController, :pin_post
post   "/community/:id/unpin",                            CommunityController, :unpin_post
post   "/community/:id/replies",                          CommunityController, :add_reply
post   "/community/:id/replies/:rid/delete",              CommunityController, :delete_reply
```

### Nav change

In `lib/atrium_web/components/layouts/app.html.heex`, change:

```elixir
<% dedicated = ~w(home news directory tools compliance helpdesk events learning feedback projects) %>
```

to:

```elixir
<% dedicated = ~w(home news directory tools compliance helpdesk events learning feedback projects community) %>
```

### Tests

```elixir
# test/atrium_web/controllers/community_controller_test.exs
defmodule AtriumWeb.CommunityControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Accounts, Authorization, Tenants, Community}
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "comm_#{:erlang.unique_integer([:positive])}"
    host = "#{slug}.atrium.example"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Community Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: member}} = Accounts.invite_user(prefix, %{
      email: "member_#{System.unique_integer([:positive])}@example.com",
      name: "Member"
    })
    {:ok, member} = Accounts.activate_user_with_password(prefix, member, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "community", {:user, member.id}, :view)

    {:ok, %{user: editor}} = Accounts.invite_user(prefix, %{
      email: "editor_#{System.unique_integer([:positive])}@example.com",
      name: "Editor"
    })
    {:ok, editor} = Accounts.activate_user_with_password(prefix, editor, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "community", {:user, editor.id}, :view)
    Authorization.grant_section(prefix, "community", {:user, editor.id}, :edit)

    member_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: member.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    editor_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: editor.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    {:ok, member_conn: member_conn, editor_conn: editor_conn, prefix: prefix, member: member, editor: editor}
  end

  test "GET /community shows index", %{member_conn: member_conn} do
    conn = get(member_conn, "/community")
    assert html_response(conn, 200) =~ "Discussion Board"
  end

  test "POST /community creates post and redirects to show", %{member_conn: member_conn} do
    conn = post(member_conn, "/community", %{"post" => %{"title" => "Hello world", "body" => "My first post"}})
    assert redirected_to(conn) =~ "/community/"
  end

  test "GET /community/:id shows post and replies form", %{member_conn: member_conn, prefix: prefix, member: member} do
    {:ok, post} = Community.create_post(prefix, %{"author_id" => member.id, "title" => "My topic", "body" => "Details"})
    conn = get(member_conn, "/community/#{post.id}")
    assert html_response(conn, 200) =~ "My topic"
  end

  test "POST /community/:id/replies adds a reply", %{member_conn: member_conn, prefix: prefix, member: member} do
    {:ok, post} = Community.create_post(prefix, %{"author_id" => member.id, "title" => "T", "body" => "B"})
    conn = post(member_conn, "/community/#{post.id}/replies", %{"reply" => %{"body" => "Hello reply"}})
    assert redirected_to(conn) =~ "/community/#{post.id}"
    assert length(Community.list_replies(prefix, post.id)) == 1
  end

  test "POST /community/:id/delete deletes own post", %{member_conn: member_conn, prefix: prefix, member: member} do
    {:ok, community_post} = Community.create_post(prefix, %{"author_id" => member.id, "title" => "T", "body" => "B"})
    conn = post(member_conn, "/community/#{community_post.id}/delete")
    assert redirected_to(conn) == "/community"
  end

  test "POST /community/:id/pin pins post (editor only)", %{editor_conn: editor_conn, prefix: prefix, editor: editor} do
    {:ok, community_post} = Community.create_post(prefix, %{"author_id" => editor.id, "title" => "T", "body" => "B"})
    conn = post(editor_conn, "/community/#{community_post.id}/pin")
    assert redirected_to(conn) == "/community"
    assert Community.get_post!(prefix, community_post.id).pinned == true
  end

  test "POST /community/:id/pin is forbidden for non-editors", %{member_conn: member_conn, prefix: prefix, editor: editor} do
    {:ok, community_post} = Community.create_post(prefix, %{"author_id" => editor.id, "title" => "T", "body" => "B"})
    conn = post(member_conn, "/community/#{community_post.id}/pin")
    assert conn.status in [302, 403]
    assert Community.get_post!(prefix, community_post.id).pinned == false
  end
end
```

### Steps

- [ ] **Step 1: Write failing tests**

```bash
mix test test/atrium_web/controllers/community_controller_test.exs
```

Expected: compile error or route not found.

- [ ] **Step 2: Create HTML module and controller** as specified above.

- [ ] **Step 3: Create templates** — create `lib/atrium_web/controllers/community_html/` directory and all three templates.

- [ ] **Step 4: Add routes to `lib/atrium_web/router.ex`** as specified.

- [ ] **Step 5: Add "community" to nav in `lib/atrium_web/components/layouts/app.html.heex`** as specified.

- [ ] **Step 6: Run tests**

```bash
mix test test/atrium_web/controllers/community_controller_test.exs
```

Expected: 7 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add lib/atrium_web/controllers/community_controller.ex \
        lib/atrium_web/controllers/community_html.ex \
        lib/atrium_web/controllers/community_html/index.html.heex \
        lib/atrium_web/controllers/community_html/show.html.heex \
        lib/atrium_web/controllers/community_html/new.html.heex \
        lib/atrium_web/router.ex \
        lib/atrium_web/components/layouts/app.html.heex \
        test/atrium_web/controllers/community_controller_test.exs
git commit -m "feat: add Community discussion board with posts, replies, and pin/unpin"
```
