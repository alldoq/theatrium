defmodule Atrium.Forms.FormSchemaTest do
  use Atrium.DataCase, async: true
  alias Atrium.Forms.Form

  describe "Form.changeset/2" do
    test "valid attrs produce a valid changeset" do
      cs = Form.changeset(%Form{}, %{
        title: "Leave Request",
        section_key: "hr",
        author_id: Ecto.UUID.generate()
      })
      assert cs.valid?
    end

    test "title is required" do
      cs = Form.changeset(%Form{}, %{section_key: "hr", author_id: Ecto.UUID.generate()})
      assert errors_on(cs)[:title]
    end

    test "section_key is required" do
      cs = Form.changeset(%Form{}, %{title: "T", author_id: Ecto.UUID.generate()})
      assert errors_on(cs)[:section_key]
    end

    test "author_id is required" do
      cs = Form.changeset(%Form{}, %{title: "T", section_key: "hr"})
      assert errors_on(cs)[:author_id]
    end

    test "status defaults to draft" do
      cs = Form.changeset(%Form{}, %{title: "T", section_key: "hr", author_id: Ecto.UUID.generate()})
      assert %Form{status: "draft"} = Ecto.Changeset.apply_changes(cs)
    end

    test "status_changeset rejects invalid status" do
      cs = Form.status_changeset(%Form{status: "draft"}, "nonsense")
      assert errors_on(cs)[:status]
    end
  end
end
