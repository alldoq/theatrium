defmodule Atrium.Documents.CommentTest do
  use Atrium.TenantCase, async: false

  alias Atrium.Documents
  alias Atrium.Accounts

  defp build_user(prefix) do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "comment_user_#{System.unique_integer([:positive])}@example.com",
      name: "Comment User"
    })
    user
  end

  test "add_comment/3 creates a comment", %{tenant_prefix: prefix} do
    user = build_user(prefix)

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

  test "list_comments/2 returns comments ordered oldest first", %{tenant_prefix: prefix} do
    user = build_user(prefix)

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

  test "delete_comment/2 removes a comment", %{tenant_prefix: prefix} do
    user = build_user(prefix)

    {:ok, doc} = Documents.create_document(prefix, %{
      "title" => "Test Doc",
      "section_key" => "docs",
      "body_html" => ""
    }, user)

    {:ok, comment} = Documents.add_comment(prefix, doc.id, %{body: "Delete me", author_id: user.id})
    assert :ok = Documents.delete_comment(prefix, comment.id)
    assert Documents.list_comments(prefix, doc.id) == []
    assert {:error, :not_found} = Documents.delete_comment(prefix, comment.id)
  end

  test "add_comment/3 rejects body over 4000 chars", %{tenant_prefix: prefix} do
    user = build_user(prefix)
    {:ok, doc} = Documents.create_document(prefix, %{
      "title" => "Test Doc",
      "section_key" => "docs",
      "body_html" => ""
    }, user)
    long_body = String.duplicate("a", 4001)
    assert {:error, changeset} = Documents.add_comment(prefix, doc.id, %{body: long_body, author_id: user.id})
    assert changeset.errors[:body]
  end

  test "add_comment/3 requires body", %{tenant_prefix: prefix} do
    user = build_user(prefix)

    {:ok, doc} = Documents.create_document(prefix, %{
      "title" => "Test Doc",
      "section_key" => "docs",
      "body_html" => ""
    }, user)

    assert {:error, changeset} = Documents.add_comment(prefix, doc.id, %{body: "", author_id: user.id})
    assert changeset.errors[:body]
  end
end
