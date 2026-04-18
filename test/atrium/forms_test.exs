defmodule Atrium.FormsTest do
  use Atrium.TenantCase
  alias Atrium.Forms
  alias Atrium.Accounts

  defp build_user(prefix) do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "form_user_#{System.unique_integer([:positive])}@example.com",
      name: "Form User"
    })
    user
  end

  describe "create_form/3" do
    test "creates a form in draft status", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "Leave Request", section_key: "hr"}, user)
      assert form.title == "Leave Request"
      assert form.status == "draft"
      assert form.current_version == 1
      assert form.author_id == user.id
    end

    test "returns error for missing required fields", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:error, cs} = Forms.create_form(prefix, %{}, user)
      assert errors_on(cs)[:title]
    end
  end

  describe "get_form!/2" do
    test "returns the form", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      assert Forms.get_form!(prefix, form.id).id == form.id
    end

    test "raises on missing id", %{tenant_prefix: prefix} do
      assert_raise Ecto.NoResultsError, fn ->
        Forms.get_form!(prefix, Ecto.UUID.generate())
      end
    end
  end

  describe "list_forms/3" do
    test "lists forms in a section", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, _} = Forms.create_form(prefix, %{title: "A", section_key: "compliance"}, user)
      {:ok, _} = Forms.create_form(prefix, %{title: "B", section_key: "compliance"}, user)
      {:ok, _} = Forms.create_form(prefix, %{title: "C", section_key: "docs"}, user)
      forms = Forms.list_forms(prefix, "compliance")
      titles = Enum.map(forms, & &1.title)
      assert "A" in titles
      assert "B" in titles
      refute "C" in titles
    end
  end

  describe "update_form/4" do
    test "updates title on draft form", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "Old", section_key: "hr"}, user)
      {:ok, updated} = Forms.update_form(prefix, form, %{title: "New"}, user)
      assert updated.title == "New"
    end

    test "cannot update a non-draft form", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      assert {:error, :not_draft} = Forms.update_form(prefix, form, %{title: "X"}, user)
    end
  end

  describe "publish_form/4" do
    test "draft → published, creates FormVersion snapshot", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      fields = [%{"id" => Ecto.UUID.generate(), "type" => "text", "label" => "Name", "required" => true, "order" => 1, "options" => [], "conditions" => []}]
      {:ok, published} = Forms.publish_form(prefix, form, fields, user)
      assert published.status == "published"
      versions = Forms.list_versions(prefix, form.id)
      assert length(versions) == 1
      assert hd(versions).version == 1
      assert hd(versions).fields == fields
    end

    test "only draft forms can be published", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      assert {:error, :invalid_transition} = Forms.publish_form(prefix, form, [], user)
    end
  end

  describe "archive_form/3" do
    test "published → archived", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      {:ok, archived} = Forms.archive_form(prefix, form, user)
      assert archived.status == "archived"
    end

    test "draft cannot be archived", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      assert {:error, :invalid_transition} = Forms.archive_form(prefix, form, user)
    end
  end

  describe "reopen_form/3" do
    test "published → draft, bumps current_version", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      {:ok, reopened} = Forms.reopen_form(prefix, form, user)
      assert reopened.status == "draft"
      assert reopened.current_version == 2
    end
  end

  describe "list_versions/2" do
    test "returns versions ordered by version desc", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, form} = Forms.create_form(prefix, %{title: "T", section_key: "hr"}, user)
      {:ok, form} = Forms.publish_form(prefix, form, [], user)
      {:ok, form} = Forms.reopen_form(prefix, form, user)
      {:ok, _} = Forms.publish_form(prefix, form, [], user)
      versions = Forms.list_versions(prefix, form.id)
      assert length(versions) == 2
      assert hd(versions).version == 2
    end
  end
end

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
