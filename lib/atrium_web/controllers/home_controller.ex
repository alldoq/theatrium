defmodule AtriumWeb.HomeController do
  use AtriumWeb, :controller
  alias Atrium.Home

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "home"}]
       when action in [:show]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "home"}]
       when action in [:create_announcement, :delete_announcement, :create_quick_link, :delete_quick_link]

  def show(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    announcements = Home.list_announcements(prefix)
    quick_links = Home.list_quick_links(prefix)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "home"})
    upcoming_events = Atrium.Events.list_upcoming_events(prefix)
    recent_activity = Atrium.Audit.list(prefix, limit: 10)
    all_users = Atrium.Accounts.list_users(prefix)
    render(conn, :show,
      announcements: announcements,
      quick_links: quick_links,
      can_edit: can_edit,
      upcoming_events: upcoming_events,
      recent_activity: recent_activity,
      all_users: all_users
    )
  end

  def create_announcement(conn, %{"announcement" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    case Home.create_announcement(prefix, params, user) do
      {:ok, _} -> conn |> put_flash(:info, "Announcement added.") |> redirect(to: ~p"/home")
      {:error, _cs} -> conn |> put_flash(:error, "Could not save announcement.") |> redirect(to: ~p"/home")
    end
  end

  def delete_announcement(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    ann = Home.get_announcement!(prefix, id)
    case Home.delete_announcement(prefix, ann, user) do
      {:ok, _} -> conn |> put_flash(:info, "Announcement removed.") |> redirect(to: ~p"/home")
      {:error, _} -> conn |> put_flash(:error, "Could not remove announcement.") |> redirect(to: ~p"/home")
    end
  end

  def create_quick_link(conn, %{"quick_link" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    case Home.create_quick_link(prefix, params, user) do
      {:ok, _} -> conn |> put_flash(:info, "Link added.") |> redirect(to: ~p"/home")
      {:error, _cs} -> conn |> put_flash(:error, "Could not save link.") |> redirect(to: ~p"/home")
    end
  end

  def delete_quick_link(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    link = Home.get_quick_link!(prefix, id)
    case Home.delete_quick_link(prefix, link, user) do
      {:ok, _} -> conn |> put_flash(:info, "Link removed.") |> redirect(to: ~p"/home")
      {:error, _} -> conn |> put_flash(:error, "Could not remove link.") |> redirect(to: ~p"/home")
    end
  end
end
