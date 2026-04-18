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
