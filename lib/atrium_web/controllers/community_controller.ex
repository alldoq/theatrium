defmodule AtriumWeb.CommunityController do
  use AtriumWeb, :controller
  alias Atrium.Community

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "community"}]
       when action in [:index, :show, :new, :create, :add_reply, :delete_reply, :delete_post]

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
    post = Community.get_post(prefix, id)

    cond do
      is_nil(post) ->
        redirect(conn, to: ~p"/community")
      can_edit || post.author_id == user.id ->
        Community.delete_post(prefix, id)
        conn
        |> put_flash(:info, "Post deleted.")
        |> redirect(to: ~p"/community")
      true ->
        conn
        |> put_flash(:error, "Not authorised.")
        |> redirect(to: ~p"/community/#{id}")
    end
  end

  def pin_post(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    Community.pin_post(prefix, id)
    conn
    |> put_flash(:info, "Post pinned.")
    |> redirect(to: ~p"/community")
  end

  def unpin_post(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    Community.unpin_post(prefix, id)
    conn
    |> put_flash(:info, "Post unpinned.")
    |> redirect(to: ~p"/community")
  end
end
