defmodule AtriumWeb.ProjectsController do
  use AtriumWeb, :controller
  alias Atrium.Projects
  alias Atrium.Projects.Project

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "projects"}]
       when action in [:index, :show]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "projects"}]
       when action in [:new, :create, :edit, :update, :archive, :add_member, :remove_member]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "projects"}]
       when action in [:add_update, :delete_update]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "projects"})
    projects = Projects.list_projects(prefix)
    member_counts = Map.new(projects, fn p -> {p.id, Projects.count_members(prefix, p.id)} end)
    render(conn, :index, projects: projects, member_counts: member_counts, can_edit: can_edit)
  end

  def new(conn, _params) do
    render(conn, :new, changeset: Project.changeset(%Project{}, %{}))
  end

  def create(conn, %{"project" => attrs}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Projects.create_project(prefix, attrs, user) do
      {:ok, project} ->
        conn
        |> put_flash(:info, "Project created.")
        |> redirect(to: ~p"/projects/#{project.id}")
      {:error, changeset} ->
        conn
        |> put_status(422)
        |> render(:new, changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    project = Projects.get_project!(prefix, id)
    members = Projects.list_members(prefix, id)
    updates = Projects.list_updates(prefix, id)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "projects"})
    is_member = Projects.member?(prefix, id, user.id)

    all_users = Atrium.Accounts.list_users(prefix)

    render(conn, :show,
      project: project,
      members: members,
      updates: updates,
      can_edit: can_edit,
      is_member: is_member,
      all_users: all_users,
      current_user: user
    )
  end

  def edit(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    project = Projects.get_project!(prefix, id)
    render(conn, :edit, project: project, changeset: Project.changeset(project, %{}))
  end

  def update(conn, %{"id" => id, "project" => attrs}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    project = Projects.get_project!(prefix, id)

    case Projects.update_project(prefix, project, attrs, user) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, "Project updated.")
        |> redirect(to: ~p"/projects/#{updated.id}")
      {:error, changeset} ->
        conn
        |> put_status(422)
        |> render(:edit, project: project, changeset: changeset)
    end
  end

  def archive(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    project = Projects.get_project!(prefix, id)

    case Projects.archive_project(prefix, project, user) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Project archived.")
        |> redirect(to: ~p"/projects")
      {:error, _} ->
        conn
        |> put_flash(:error, "Could not archive project.")
        |> redirect(to: ~p"/projects/#{id}")
    end
  end

  def add_member(conn, %{"id" => id, "user_id" => user_id}) when user_id != "" do
    prefix = conn.assigns.tenant_prefix
    case Projects.add_member(prefix, id, user_id) do
      {:ok, _} -> redirect(conn, to: ~p"/projects/#{id}")
      {:error, _} ->
        conn
        |> put_flash(:error, "Could not add member.")
        |> redirect(to: ~p"/projects/#{id}")
    end
  end

  def add_member(conn, %{"id" => id}) do
    redirect(conn, to: ~p"/projects/#{id}")
  end

  def remove_member(conn, %{"id" => id, "user_id" => user_id}) do
    prefix = conn.assigns.tenant_prefix
    Projects.remove_member(prefix, id, user_id)
    redirect(conn, to: ~p"/projects/#{id}")
  end

  def add_update(conn, %{"id" => id, "update" => %{"body" => body}}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Projects.add_update(prefix, id, %{"author_id" => user.id, "body" => body}) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Update posted.")
        |> redirect(to: ~p"/projects/#{id}" <> "#updates")
      {:error, _} ->
        conn
        |> put_flash(:error, "Update cannot be blank.")
        |> redirect(to: ~p"/projects/#{id}" <> "#updates")
    end
  end

  def add_update(conn, %{"id" => id}) do
    conn
    |> put_flash(:error, "Update cannot be blank.")
    |> redirect(to: ~p"/projects/#{id}" <> "#updates")
  end

  def delete_update(conn, %{"id" => id, "uid" => uid}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "projects"})
    project_update = Projects.get_update(prefix, uid)

    cond do
      is_nil(project_update) ->
        redirect(conn, to: ~p"/projects/#{id}" <> "#updates")
      can_edit || project_update.author_id == user.id ->
        Projects.delete_update(prefix, uid)
        conn
        |> put_flash(:info, "Update deleted.")
        |> redirect(to: ~p"/projects/#{id}" <> "#updates")
      true ->
        conn
        |> put_flash(:error, "Not authorised.")
        |> redirect(to: ~p"/projects/#{id}" <> "#updates")
    end
  end
end
