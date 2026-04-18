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
    announcements = Home.list_announcements(prefix)
    quick_links = Home.list_quick_links(prefix)
    render(conn, :show, announcements: announcements, quick_links: quick_links)
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
    {:ok, _} = Home.delete_announcement(prefix, ann, user)
    conn |> put_flash(:info, "Announcement removed.") |> redirect(to: ~p"/home")
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
    {:ok, _} = Home.delete_quick_link(prefix, link, user)
    conn |> put_flash(:info, "Link removed.") |> redirect(to: ~p"/home")
  end
end
