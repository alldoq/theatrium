defmodule AtriumWeb.DocumentCommentsTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Accounts, Authorization, Tenants, Documents}
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

  test "POST /sections/docs/documents/:id/comments creates a comment", %{conn: conn, doc: doc, prefix: prefix} do
    conn = post(conn, "/sections/docs/documents/#{doc.id}/comments", %{"comment" => %{"body" => "Great doc!"}})
    assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
    assert length(Documents.list_comments(prefix, doc.id)) == 1
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

  test "DELETE comment by non-author non-editor is rejected", %{conn: conn, doc: doc, prefix: prefix, user: user} do
    # Create a second user who is NOT the comment author
    {:ok, %{user: user2}} = Accounts.invite_user(prefix, %{
      email: "dc2_#{System.unique_integer([:positive])}@example.com",
      name: "DC User2"
    })
    {:ok, user2} = Accounts.activate_user_with_password(prefix, user2, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "docs", {:user, user2.id}, :view)

    # Comment by user (the original user from setup)
    {:ok, comment} = Documents.add_comment(prefix, doc.id, %{body: "Owner comment", author_id: user.id})

    # Log in as user2
    host = conn.host
    conn2 =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: user2.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    # user2 tries to delete user's comment — should be rejected
    conn2 = post(conn2, "/sections/docs/documents/#{doc.id}/comments/#{comment.id}/delete")
    assert redirected_to(conn2) =~ "/sections/docs/documents/#{doc.id}"
    # Comment should still exist
    assert length(Documents.list_comments(prefix, doc.id)) == 1
  end
end
