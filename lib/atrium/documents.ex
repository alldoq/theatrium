defmodule Atrium.Documents do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Documents.{Document, DocumentVersion}
  alias Atrium.Documents.Comment
  alias Atrium.Notifications.Dispatcher

  # ---------------------------------------------------------------------------
  # CRUD
  # ---------------------------------------------------------------------------

  def create_document(prefix, attrs, actor_user) do
    string_attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    attrs_with_author = Map.put(string_attrs, "author_id", actor_user.id)

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

  def update_document(prefix, %Document{status: "draft"} = doc, attrs, actor_user) do
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

  def update_document(_prefix, _doc, _attrs, _actor_user), do: {:error, :not_draft}

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
    case transition(prefix, doc, "in_review", actor_user, "document.submitted") do
      {:ok, updated} = result ->
        Dispatcher.document_submitted(prefix, updated, actor_user)
        result
      err ->
        err
    end
  end

  def submit_for_review(_prefix, _doc, _actor_user), do: {:error, :invalid_transition}

  def reject_document(prefix, %Document{status: "in_review"} = doc, actor_user) do
    case transition(prefix, doc, "draft", actor_user, "document.rejected") do
      {:ok, updated} = result ->
        Dispatcher.document_rejected(prefix, updated, actor_user)
        result
      err ->
        err
    end
  end

  def reject_document(_prefix, _doc, _actor_user), do: {:error, :invalid_transition}

  def approve_document(prefix, %Document{status: "in_review"} = doc, actor_user) do
    extra = %{approved_by_id: actor_user.id, approved_at: DateTime.utc_now()}

    result =
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

    case result do
      {:ok, updated} = ok ->
        Dispatcher.document_approved(prefix, updated, actor_user)
        ok
      err ->
        err
    end
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

  # ---------------------------------------------------------------------------
  # Comments
  # ---------------------------------------------------------------------------

  def list_comments(prefix, document_id) do
    Repo.all(
      from(c in Comment,
        where: c.document_id == ^document_id,
        order_by: [asc: c.inserted_at]
      ),
      prefix: prefix
    )
  end

  def add_comment(prefix, document_id, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    attrs = Map.put(attrs, "document_id", document_id)

    %Comment{}
    |> Comment.changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  def delete_comment(prefix, comment_id) do
    case Repo.get(Comment, comment_id, prefix: prefix) do
      nil -> :ok
      comment ->
        case Repo.delete(comment, prefix: prefix) do
          {:ok, _} -> :ok
          {:error, _} = err -> err
        end
    end
  end
end
