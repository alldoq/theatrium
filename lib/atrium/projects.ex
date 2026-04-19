defmodule Atrium.Projects do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Projects.{Project, ProjectMember, ProjectUpdate}

  def list_projects(prefix) do
    Repo.all(from(p in Project, order_by: [desc: p.inserted_at]), prefix: prefix)
  end

  def get_project!(prefix, id) do
    Repo.get!(Project, id, prefix: prefix)
  end

  def create_project(prefix, attrs, user) do
    attrs = Map.put(stringify(attrs), "owner_id", user.id)
    changeset = Project.changeset(%Project{}, attrs)

    Repo.transaction(fn ->
      with {:ok, project} <- Repo.insert(changeset, prefix: prefix),
           {:ok, _} <- Atrium.Audit.log(prefix, "project.created", %{actor: {:user, user.id}, resource: {"Project", project.id}}) do
        project
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_project(prefix, project, attrs, user) do
    changeset = Project.changeset(project, stringify(attrs))

    Repo.transaction(fn ->
      with {:ok, updated} <- Repo.update(changeset, prefix: prefix),
           {:ok, _} <- Atrium.Audit.log(prefix, "project.updated", %{actor: {:user, user.id}, resource: {"Project", updated.id}}) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def archive_project(prefix, project, user) do
    update_project(prefix, project, %{"status" => "archived"}, user)
  end

  def list_members(prefix, project_id) do
    Repo.all(
      from(m in ProjectMember, where: m.project_id == ^project_id, order_by: m.inserted_at),
      prefix: prefix
    )
  end

  def add_member(prefix, project_id, user_id, role \\ "member") do
    changeset = ProjectMember.changeset(%ProjectMember{}, %{
      project_id: project_id,
      user_id: user_id,
      role: role
    })
    Repo.insert(changeset, prefix: prefix)
  end

  def remove_member(prefix, project_id, user_id) do
    case Repo.get_by(ProjectMember, [project_id: project_id, user_id: user_id], prefix: prefix) do
      nil -> {:error, :not_found}
      member ->
        case Repo.delete(member, prefix: prefix) do
          {:ok, _} -> :ok
          {:error, _} = err -> err
        end
    end
  end

  def member?(prefix, project_id, user_id) do
    Repo.exists?(
      from(m in ProjectMember, where: m.project_id == ^project_id and m.user_id == ^user_id),
      prefix: prefix
    )
  end

  def list_updates(prefix, project_id) do
    Repo.all(
      from(u in ProjectUpdate, where: u.project_id == ^project_id, order_by: [asc: u.inserted_at]),
      prefix: prefix
    )
  end

  def add_update(prefix, project_id, attrs) do
    changeset = ProjectUpdate.changeset(%ProjectUpdate{}, Map.put(stringify(attrs), "project_id", project_id))
    Repo.insert(changeset, prefix: prefix)
  end

  def get_update(prefix, update_id) do
    Repo.get(ProjectUpdate, update_id, prefix: prefix)
  end

  def delete_update(prefix, update_id) do
    case Repo.get(ProjectUpdate, update_id, prefix: prefix) do
      nil -> {:error, :not_found}
      update ->
        case Repo.delete(update, prefix: prefix) do
          {:ok, _} -> :ok
          {:error, _} = err -> err
        end
    end
  end

  def count_members(prefix, project_id) do
    Repo.aggregate(
      from(m in ProjectMember, where: m.project_id == ^project_id),
      :count,
      :id,
      prefix: prefix
    )
  end

  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
