defmodule Atrium.Documents do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Documents.{Document, DocumentVersion}

  # ---------------------------------------------------------------------------
  # CRUD
  # ---------------------------------------------------------------------------

  def create_document(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(attrs, :author_id, actor_user.id)

    Repo.transaction(fn ->
      with {:ok, doc} <- insert_document(prefix, attrs_with_author),
           {:ok, _ver} <- insert_version(prefix, doc, actor_user),
           {:ok, _} <- Audit.log(prefix, "document.created", %{
             actor: {:user, actor_user.id},
             resource: {"Document", doc.id},
             changes: %{"title" => [nil, doc.title], "section_key" => [nil, doc.section_key]}
           }) do
        doc
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_document!(prefix, id) do
    Repo.get!(Document, id, prefix: prefix)
  end

  def list_documents(prefix, section_key, opts \\ []) do
    query =
      from d in Document,
        where: d.section_key == ^section_key,
        order_by: [desc: d.inserted_at]

    query =
      case Keyword.get(opts, :subsection_slug) do
        nil -> query
        slug -> where(query, [d], d.subsection_slug == ^slug)
      end

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [d], d.status == ^status)
      end

    Repo.all(query, prefix: prefix)
  end

  def update_document(prefix, doc, attrs, actor_user) do
    if doc.status != "draft" do
      {:error, :not_draft}
    else
      Repo.transaction(fn ->
        with {:ok, updated} <- apply_update(prefix, doc, attrs),
             {:ok, _ver} <- insert_version(prefix, updated, actor_user),
             {:ok, _} <- Audit.log(prefix, "document.updated", %{
               actor: {:user, actor_user.id},
               resource: {"Document", updated.id},
               changes: Audit.changeset_diff(doc, updated)
             }) do
          updated
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Versions
  # ---------------------------------------------------------------------------

  def list_versions(prefix, document_id) do
    from(v in DocumentVersion,
      where: v.document_id == ^document_id,
      order_by: [desc: v.version]
    )
    |> Repo.all(prefix: prefix)
  end

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  def submit_for_review(prefix, %Document{status: "draft"} = doc, actor_user) do
    transition(prefix, doc, "in_review", actor_user, "document.submitted")
  end

  def submit_for_review(_prefix, _doc, _actor_user), do: {:error, :invalid_transition}

  def reject_document(prefix, %Document{status: "in_review"} = doc, actor_user) do
    transition(prefix, doc, "draft", actor_user, "document.rejected")
  end

  def reject_document(_prefix, _doc, _actor_user), do: {:error, :invalid_transition}

  def approve_document(prefix, %Document{status: "in_review"} = doc, actor_user) do
    extra = %{approved_by_id: actor_user.id, approved_at: DateTime.utc_now()}

    Repo.transaction(fn ->
      with {:ok, updated} <- apply_status(prefix, doc, "approved", extra),
           {:ok, _} <- Audit.log(prefix, "document.approved", %{
             actor: {:user, actor_user.id},
             resource: {"Document", updated.id},
             changes: %{"status" => [doc.status, "approved"]}
           }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def approve_document(_prefix, _doc, _actor_user), do: {:error, :invalid_transition}

  def archive_document(prefix, %Document{status: "approved"} = doc, actor_user) do
    transition(prefix, doc, "archived", actor_user, "document.archived")
  end

  def archive_document(_prefix, _doc, _actor_user), do: {:error, :invalid_transition}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp insert_document(prefix, attrs) do
    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  defp apply_update(prefix, doc, attrs) do
    doc
    |> Document.update_changeset(attrs)
    |> Document.version_bump_changeset()
    |> Repo.update(prefix: prefix)
  end

  defp insert_version(prefix, doc, actor_user) do
    %DocumentVersion{}
    |> DocumentVersion.changeset(%{
      document_id: doc.id,
      version: doc.current_version,
      title: doc.title,
      body_html: doc.body_html,
      saved_by_id: actor_user.id,
      saved_at: DateTime.utc_now()
    })
    |> Repo.insert(prefix: prefix)
  end

  defp transition(prefix, doc, new_status, actor_user, audit_action) do
    Repo.transaction(fn ->
      with {:ok, updated} <- apply_status(prefix, doc, new_status, %{}),
           {:ok, _} <- Audit.log(prefix, audit_action, %{
             actor: {:user, actor_user.id},
             resource: {"Document", updated.id},
             changes: %{"status" => [doc.status, new_status]}
           }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp apply_status(prefix, doc, status, extra_attrs) do
    doc
    |> Document.status_changeset(status, extra_attrs)
    |> Repo.update(prefix: prefix)
  end
end
