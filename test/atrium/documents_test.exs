defmodule Atrium.Documents.DocumentSchemaTest do
  use Atrium.DataCase, async: true
  alias Atrium.Documents.Document

  describe "Document.changeset/2" do
    test "valid attrs produce a valid changeset" do
      attrs = %{
        title: "My Policy",
        section_key: "hr",
        body_html: "<p>content</p>",
        author_id: Ecto.UUID.generate()
      }
      cs = Document.changeset(%Document{}, attrs)
      assert cs.valid?
    end

    test "title is required" do
      cs = Document.changeset(%Document{}, %{section_key: "hr", author_id: Ecto.UUID.generate()})
      assert errors_on(cs)[:title]
    end

    test "section_key is required" do
      cs = Document.changeset(%Document{}, %{title: "T", author_id: Ecto.UUID.generate()})
      assert errors_on(cs)[:section_key]
    end

    test "author_id is required" do
      cs = Document.changeset(%Document{}, %{title: "T", section_key: "hr"})
      assert errors_on(cs)[:author_id]
    end

    test "status defaults to draft" do
      cs = Document.changeset(%Document{}, %{title: "T", section_key: "hr", author_id: Ecto.UUID.generate()})
      assert %Document{status: "draft"} = Ecto.Changeset.apply_changes(cs)
    end

    test "status_changeset rejects invalid status" do
      doc = %Document{status: "draft"}
      cs = Document.status_changeset(doc, "nonsense")
      assert errors_on(cs)[:status]
    end
  end
end

defmodule Atrium.DocumentsTest do
  use Atrium.TenantCase
  alias Atrium.Documents
  alias Atrium.Accounts

  defp build_user(prefix) do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "doc_user_#{System.unique_integer([:positive])}@example.com",
      name: "Doc User"
    })
    user
  end

  describe "create_document/3" do
    test "creates a document and snapshots version 1", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      attrs = %{title: "HR Policy", section_key: "hr", body_html: "<p>Hello</p>"}

      {:ok, doc} = Documents.create_document(prefix, attrs, user)

      assert doc.title == "HR Policy"
      assert doc.section_key == "hr"
      assert doc.status == "draft"
      assert doc.current_version == 1
      assert doc.author_id == user.id

      versions = Documents.list_versions(prefix, doc.id)
      assert length(versions) == 1
      assert hd(versions).version == 1
      assert hd(versions).title == "HR Policy"
    end

    test "returns error for missing required fields", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:error, %Ecto.Changeset{}} = Documents.create_document(prefix, %{}, user)
    end
  end

  describe "get_document!/2" do
    test "returns the document", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "T", section_key: "docs", body_html: ""}, user)
      assert Documents.get_document!(prefix, doc.id).id == doc.id
    end

    test "raises on missing id", %{tenant_prefix: prefix} do
      assert_raise Ecto.NoResultsError, fn ->
        Documents.get_document!(prefix, Ecto.UUID.generate())
      end
    end
  end

  describe "list_documents/3" do
    test "lists documents in a section", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, _} = Documents.create_document(prefix, %{title: "A", section_key: "hr", body_html: ""}, user)
      {:ok, _} = Documents.create_document(prefix, %{title: "B", section_key: "hr", body_html: ""}, user)
      {:ok, _} = Documents.create_document(prefix, %{title: "C", section_key: "docs", body_html: ""}, user)

      hr_docs = Documents.list_documents(prefix, "hr")
      assert Enum.all?(hr_docs, &(&1.section_key == "hr"))
      assert length(hr_docs) >= 2
    end
  end

  describe "update_document/4" do
    test "updates title+body and snapshots a new version", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "Old", section_key: "hr", body_html: "<p>old</p>"}, user)

      {:ok, updated} = Documents.update_document(prefix, doc, %{title: "New", body_html: "<p>new</p>"}, user)

      assert updated.title == "New"
      assert updated.current_version == 2

      versions = Documents.list_versions(prefix, doc.id)
      assert length(versions) == 2
    end

    test "cannot update a non-draft document", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "T", section_key: "hr", body_html: ""}, user)
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)

      assert {:error, :not_draft} = Documents.update_document(prefix, doc, %{title: "X"}, user)
    end
  end

  describe "list_versions/2" do
    test "returns versions ordered by version desc", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "V1", section_key: "hr", body_html: ""}, user)
      {:ok, doc} = Documents.update_document(prefix, doc, %{title: "V2", body_html: ""}, user)
      {:ok, _} = Documents.update_document(prefix, doc, %{title: "V3", body_html: ""}, user)

      versions = Documents.list_versions(prefix, doc.id)
      assert length(versions) == 3
      assert hd(versions).version == 3
    end
  end

  describe "lifecycle transitions" do
    setup %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "Policy", section_key: "hr", body_html: "<p>v1</p>"}, user)
      %{doc: doc, user: user}
    end

    test "submit_for_review: draft → in_review", %{tenant_prefix: prefix, doc: doc, user: user} do
      {:ok, updated} = Documents.submit_for_review(prefix, doc, user)
      assert updated.status == "in_review"
    end

    test "submit_for_review: non-draft is rejected", %{tenant_prefix: prefix, doc: doc, user: user} do
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      assert {:error, :invalid_transition} = Documents.submit_for_review(prefix, doc, user)
    end

    test "reject_document: in_review → draft", %{tenant_prefix: prefix, doc: doc, user: user} do
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      {:ok, rejected} = Documents.reject_document(prefix, doc, user)
      assert rejected.status == "draft"
    end

    test "reject_document: must be in_review", %{tenant_prefix: prefix, doc: doc, user: user} do
      assert {:error, :invalid_transition} = Documents.reject_document(prefix, doc, user)
    end

    test "approve_document: in_review → approved, sets approved_by_id and approved_at", %{tenant_prefix: prefix, doc: doc, user: user} do
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      {:ok, approved} = Documents.approve_document(prefix, doc, user)
      assert approved.status == "approved"
      assert approved.approved_by_id == user.id
      assert approved.approved_at
    end

    test "approve_document: must be in_review", %{tenant_prefix: prefix, doc: doc, user: user} do
      assert {:error, :invalid_transition} = Documents.approve_document(prefix, doc, user)
    end

    test "archive_document: approved → archived", %{tenant_prefix: prefix, doc: doc, user: user} do
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      {:ok, doc} = Documents.approve_document(prefix, doc, user)
      {:ok, archived} = Documents.archive_document(prefix, doc, user)
      assert archived.status == "archived"
    end

    test "archive_document: must be approved", %{tenant_prefix: prefix, doc: doc, user: user} do
      assert {:error, :invalid_transition} = Documents.archive_document(prefix, doc, user)
    end
  end

  describe "audit events" do
    test "create_document emits document.created", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "Audit Me", section_key: "hr", body_html: ""}, user)
      history = Atrium.Audit.history_for(prefix, "Document", doc.id)
      assert Enum.any?(history, &(&1.action == "document.created"))
    end

    test "update_document emits document.updated", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "Before", section_key: "hr", body_html: ""}, user)
      {:ok, _} = Documents.update_document(prefix, doc, %{title: "After", body_html: ""}, user)
      history = Atrium.Audit.history_for(prefix, "Document", doc.id)
      assert Enum.any?(history, &(&1.action == "document.updated"))
    end

    test "lifecycle transitions emit correct audit events", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, doc} = Documents.create_document(prefix, %{title: "T", section_key: "hr", body_html: ""}, user)
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      {:ok, doc} = Documents.approve_document(prefix, doc, user)
      {:ok, _} = Documents.archive_document(prefix, doc, user)
      history = Atrium.Audit.history_for(prefix, "Document", doc.id)
      actions = Enum.map(history, & &1.action)
      assert "document.submitted" in actions
      assert "document.approved" in actions
      assert "document.archived" in actions
    end
  end
end
