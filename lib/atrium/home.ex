defmodule Atrium.Home do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Home.{Announcement, QuickLink}

  def list_announcements(prefix) do
    Repo.all(
      from(a in Announcement, order_by: [desc: a.pinned, desc: a.inserted_at]),
      prefix: prefix
    )
  end

  def get_announcement!(prefix, id), do: Repo.get!(Announcement, id, prefix: prefix)

  def create_announcement(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(stringify(attrs), "author_id", actor_user.id)
    Repo.transaction(fn ->
      with {:ok, ann} <- %Announcement{} |> Announcement.changeset(attrs_with_author) |> Repo.insert(prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "announcement.created", %{actor: {:user, actor_user.id}, resource: {"Announcement", ann.id}}) do
        ann
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_announcement(prefix, %Announcement{} = ann, attrs, actor_user) do
    Repo.transaction(fn ->
      with {:ok, updated} <- ann |> Announcement.update_changeset(attrs) |> Repo.update(prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "announcement.updated", %{actor: {:user, actor_user.id}, resource: {"Announcement", updated.id}}) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_announcement(prefix, %Announcement{} = ann, actor_user) do
    Repo.transaction(fn ->
      with {:ok, deleted} <- Repo.delete(ann, prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "announcement.deleted", %{actor: {:user, actor_user.id}, resource: {"Announcement", deleted.id}}) do
        deleted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def list_quick_links(prefix) do
    Repo.all(from(q in QuickLink, order_by: [asc: q.position, asc: q.inserted_at]), prefix: prefix)
  end

  def get_quick_link!(prefix, id), do: Repo.get!(QuickLink, id, prefix: prefix)

  def create_quick_link(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(stringify(attrs), "author_id", actor_user.id)
    Repo.transaction(fn ->
      with {:ok, link} <- %QuickLink{} |> QuickLink.changeset(attrs_with_author) |> Repo.insert(prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "quick_link.created", %{actor: {:user, actor_user.id}, resource: {"QuickLink", link.id}}) do
        link
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_quick_link(prefix, %QuickLink{} = link, actor_user) do
    Repo.transaction(fn ->
      with {:ok, deleted} <- Repo.delete(link, prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "quick_link.deleted", %{actor: {:user, actor_user.id}, resource: {"QuickLink", deleted.id}}) do
        deleted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
