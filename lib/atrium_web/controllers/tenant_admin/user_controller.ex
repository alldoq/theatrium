defmodule AtriumWeb.TenantAdmin.UserController do
  use AtriumWeb, :controller

  alias Atrium.{Accounts, Authorization, Audit}
  alias Atrium.Authorization.SectionRegistry

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    users = Accounts.list_users(prefix)
    render(conn, :index, users: users)
  end

  def new(conn, _params) do
    sections = enabled_sections(conn)
    render(conn, :new, sections: sections)
  end

  def create(conn, %{"user" => params}) do
    prefix = conn.assigns.tenant_prefix
    actor = conn.assigns.current_user

    case Accounts.invite_user(prefix, %{name: params["name"], email: params["email"]}) do
      {:ok, %{user: user}} ->
        if params["is_admin"] == "true" do
          {:ok, _} = Accounts.set_admin(prefix, user, true)
        end

        desired = decode_section_params(params["sections"] || %{})
        sync_permissions(prefix, user, desired, actor)

        conn
        |> put_flash(:info, "Invitation sent to #{user.email}")
        |> redirect(to: ~p"/admin/users/#{user.id}")

      {:error, changeset} ->
        sections = enabled_sections(conn)
        render(conn, :new, sections: sections, changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = Accounts.get_user!(prefix, id)
    sections = enabled_sections(conn)
    current_grants = load_user_grants(prefix, user.id)
    render(conn, :show, user: user, sections: sections, current_grants: current_grants)
  end

  def update_permissions(conn, %{"id" => id, "sections" => section_params}) do
    prefix = conn.assigns.tenant_prefix
    actor = conn.assigns.current_user
    user = Accounts.get_user!(prefix, id)
    desired = decode_section_params(section_params)
    sync_permissions(prefix, user, desired, actor)

    conn
    |> put_flash(:info, "Permissions updated")
    |> redirect(to: ~p"/admin/users/#{user.id}")
  end

  def update_permissions(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    actor = conn.assigns.current_user
    user = Accounts.get_user!(prefix, id)
    sync_permissions(prefix, user, MapSet.new(), actor)

    conn
    |> put_flash(:info, "Permissions updated")
    |> redirect(to: ~p"/admin/users/#{user.id}")
  end

  def toggle_admin(conn, %{"id" => id}) do
    actor = conn.assigns.current_user
    if to_string(actor.id) == id do
      conn
      |> put_flash(:error, "You cannot change your own admin status")
      |> redirect(to: ~p"/admin/users/#{id}")
    else
      prefix = conn.assigns.tenant_prefix
      user = Accounts.get_user!(prefix, id)
      case Accounts.set_admin(prefix, user, !user.is_admin) do
        {:ok, _} ->
          conn |> put_flash(:info, "Admin status updated") |> redirect(to: ~p"/admin/users/#{user.id}")
        {:error, _} ->
          conn |> put_flash(:error, "Could not update admin status") |> redirect(to: ~p"/admin/users/#{user.id}")
      end
    end
  end

  def suspend(conn, %{"id" => id}) do
    actor = conn.assigns.current_user
    if to_string(actor.id) == id do
      conn
      |> put_flash(:error, "You cannot suspend yourself")
      |> redirect(to: ~p"/admin/users/#{id}")
    else
      prefix = conn.assigns.tenant_prefix
      user = Accounts.get_user!(prefix, id)
      case Accounts.suspend_user(prefix, user) do
        {:ok, _} ->
          conn |> put_flash(:info, "User suspended") |> redirect(to: ~p"/admin/users/#{user.id}")
        {:error, _} ->
          conn |> put_flash(:error, "Could not suspend user") |> redirect(to: ~p"/admin/users/#{user.id}")
      end
    end
  end

  def edit_profile(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = Accounts.get_user!(prefix, id)
    render(conn, :edit_profile, profile_user: user)
  end

  def update_profile(conn, %{"id" => id, "user" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = Accounts.get_user!(prefix, id)

    case Accounts.update_profile(prefix, user, params) do
      {:ok, _} ->
        conn |> put_flash(:info, "Profile updated.") |> redirect(to: ~p"/directory/#{id}")
      {:error, _cs} ->
        conn |> put_flash(:error, "Could not update profile.") |> render(:edit_profile, profile_user: user)
    end
  end

  def restore(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = Accounts.get_user!(prefix, id)
    case Accounts.restore_user(prefix, user) do
      {:ok, _} ->
        conn |> put_flash(:info, "User restored") |> redirect(to: ~p"/admin/users/#{user.id}")
      {:error, _} ->
        conn |> put_flash(:error, "Could not restore user") |> redirect(to: ~p"/admin/users/#{user.id}")
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp enabled_sections(conn) do
    tenant = conn.assigns.tenant
    enabled = MapSet.new(tenant.enabled_sections || [])

    SectionRegistry.all()
    |> Enum.filter(&MapSet.member?(enabled, to_string(&1.key)))
  end

  defp decode_section_params(section_params) do
    for {section_key, caps} <- section_params,
        {cap, "true"} <- caps,
        into: MapSet.new() do
      {section_key, cap}
    end
  end

  defp load_user_grants(prefix, user_id) do
    SectionRegistry.all()
    |> Enum.flat_map(fn s ->
      Authorization.list_section_acls(prefix, to_string(s.key))
    end)
    |> Enum.filter(&(&1.principal_type == "user" and &1.principal_id == user_id))
    |> MapSet.new(&{&1.section_key, &1.capability})
  end

  defp sync_permissions(prefix, user, desired, actor) do
    current = load_user_grants(prefix, user.id)

    to_grant = MapSet.difference(desired, current)
    to_revoke = MapSet.difference(current, desired)

    Enum.each(to_grant, fn {section_key, cap} ->
      Authorization.grant_section(prefix, section_key, {:user, user.id}, cap, actor.id)
    end)

    Enum.each(to_revoke, fn {section_key, cap} ->
      Authorization.revoke_section(prefix, section_key, {:user, user.id}, cap)
    end)

    unless MapSet.equal?(desired, current) do
      Audit.log(prefix, "user.permissions_updated", %{
        actor: {:user, actor.id},
        resource: {"User", user.id},
        changes: %{
          "granted" => Enum.map(to_grant, fn {s, c} -> "#{s}:#{c}" end),
          "revoked" => Enum.map(to_revoke, fn {s, c} -> "#{s}:#{c}" end)
        }
      })
    end
  end
end
