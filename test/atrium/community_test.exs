defmodule Atrium.CommunityTest do
  use Atrium.TenantCase, async: false

  alias Atrium.{Community, Accounts}

  defp build_user(prefix) do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "community_#{System.unique_integer([:positive])}@example.com",
      name: "Test User"
    })
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    user
  end

  test "create_post/2 creates a post", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Hello", "body" => "World"})
    assert post.title == "Hello"
    assert post.author_id == user.id
    assert post.pinned == false
  end

  test "list_posts/1 returns pinned first", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, _normal} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Normal", "body" => "body"})
    {:ok, pinned} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Pinned", "body" => "body"})
    {:ok, _} = Community.pin_post(prefix, pinned.id)
    posts = Community.list_posts(prefix)
    assert hd(posts).id == pinned.id
  end

  test "delete_post/2 removes post", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "To Delete", "body" => "body"})
    assert :ok = Community.delete_post(prefix, post.id)
    assert_raise Ecto.NoResultsError, fn -> Community.get_post!(prefix, post.id) end
  end

  test "delete_post/2 returns error for missing post", %{tenant_prefix: prefix} do
    assert {:error, :not_found} = Community.delete_post(prefix, Ecto.UUID.generate())
  end

  test "add_reply/3 and list_replies/2", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Post", "body" => "body"})
    {:ok, _} = Community.add_reply(prefix, post.id, %{"author_id" => user.id, "body" => "First reply"})
    {:ok, _} = Community.add_reply(prefix, post.id, %{"author_id" => user.id, "body" => "Second reply"})
    replies = Community.list_replies(prefix, post.id)
    assert length(replies) == 2
    assert hd(replies).body == "First reply"
  end

  test "delete_reply/2 removes reply", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Post", "body" => "body"})
    {:ok, reply} = Community.add_reply(prefix, post.id, %{"author_id" => user.id, "body" => "Reply"})
    assert :ok = Community.delete_reply(prefix, reply.id)
    assert Community.list_replies(prefix, post.id) == []
  end

  test "delete_reply/2 returns error for missing reply", %{tenant_prefix: prefix} do
    assert {:error, :not_found} = Community.delete_reply(prefix, Ecto.UUID.generate())
  end

  test "count_replies/2 counts correctly", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Post", "body" => "body"})
    {:ok, _} = Community.add_reply(prefix, post.id, %{"author_id" => user.id, "body" => "A reply"})
    assert Community.count_replies(prefix, post.id) == 1
  end

  test "pin_post/2 sets pinned true", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Post", "body" => "body"})
    {:ok, updated} = Community.pin_post(prefix, post.id)
    assert updated.pinned == true
  end

  test "unpin_post/2 sets pinned false", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, post} = Community.create_post(prefix, %{"author_id" => user.id, "title" => "Post", "body" => "body"})
    {:ok, pinned} = Community.pin_post(prefix, post.id)
    assert pinned.pinned == true
    {:ok, unpinned} = Community.unpin_post(prefix, post.id)
    assert unpinned.pinned == false
  end
end
