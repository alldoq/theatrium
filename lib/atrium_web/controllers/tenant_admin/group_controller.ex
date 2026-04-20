defmodule AtriumWeb.TenantAdmin.GroupController do
  use AtriumWeb, :controller

  alias Atrium.{Accounts, Authorization}
  alias Atrium.Authorization.Group

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    groups = Authorization.list_groups(prefix)
    member_counts =
      for g <- groups, into: %{}, do: {g.id, length(Authorization.list_members(prefix, g))}

    render(conn, :index, groups: groups, member_counts: member_counts)
  end

  def new(conn, _params) do
    render(conn, :new, changeset: Group.create_changeset(%Group{}, %{}))
  end

  def create(conn, %{"group" => params}) do
    prefix = conn.assigns.tenant_prefix
    actor = conn.assigns.current_user
    attrs = Map.put(params, "kind", "custom")

    case Authorization.create_group(prefix, attrs, actor.id) do
      {:ok, group} ->
        conn
        |> put_flash(:info, "Group created.")
        |> redirect(to: ~p"/admin/groups/#{group.id}")

      {:error, changeset} ->
        conn |> put_status(422) |> render(:new, changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    group = Authorization.get_group!(prefix, id)
    members = Authorization.list_members(prefix, group)
    member_ids = MapSet.new(members, & &1.id)
    all_users = Accounts.list_users(prefix)
    addable = Enum.reject(all_users, &MapSet.member?(member_ids, &1.id))

    render(conn, :show, group: group, members: members, addable: addable)
  end

  def edit(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    group = Authorization.get_group!(prefix, id)
    render(conn, :edit, group: group, changeset: Group.update_changeset(group, %{}))
  end

  def update(conn, %{"id" => id, "group" => params}) do
    prefix = conn.assigns.tenant_prefix
    actor = conn.assigns.current_user
    group = Authorization.get_group!(prefix, id)

    case Authorization.update_group(prefix, group, params, actor.id) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, "Group updated.")
        |> redirect(to: ~p"/admin/groups/#{updated.id}")

      {:error, changeset} ->
        conn |> put_status(422) |> render(:edit, group: group, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    group = Authorization.get_group!(prefix, id)

    case Authorization.delete_group(prefix, group) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Group deleted.")
        |> redirect(to: ~p"/admin/groups")

      {:error, :cannot_delete_system_group} ->
        conn
        |> put_flash(:error, "System groups cannot be deleted.")
        |> redirect(to: ~p"/admin/groups/#{group.id}")

      {:error, {:cannot_delete_referenced_group, n}} ->
        conn
        |> put_flash(:error, "Group still referenced by #{n} permission(s). Revoke them first.")
        |> redirect(to: ~p"/admin/groups/#{group.id}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not delete group.")
        |> redirect(to: ~p"/admin/groups/#{group.id}")
    end
  end

  def add_member(conn, %{"id" => id, "user_id" => user_id}) do
    prefix = conn.assigns.tenant_prefix
    group = Authorization.get_group!(prefix, id)
    user = Accounts.get_user!(prefix, user_id)
    {:ok, _} = Authorization.add_member(prefix, user, group)

    conn
    |> put_flash(:info, "Added #{user.email} to #{group.name}.")
    |> redirect(to: ~p"/admin/groups/#{group.id}")
  end

  def remove_member(conn, %{"id" => id, "user_id" => user_id}) do
    prefix = conn.assigns.tenant_prefix
    group = Authorization.get_group!(prefix, id)
    user = Accounts.get_user!(prefix, user_id)
    :ok = Authorization.remove_member(prefix, user, group)

    conn
    |> put_flash(:info, "Removed #{user.email} from #{group.name}.")
    |> redirect(to: ~p"/admin/groups/#{group.id}")
  end
end
