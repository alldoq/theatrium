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

  test "GET /community/:id shows post", %{member_conn: member_conn, prefix: prefix, member: member} do
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
