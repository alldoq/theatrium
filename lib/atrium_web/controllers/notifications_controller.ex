defmodule AtriumWeb.NotificationsController do
  use AtriumWeb, :controller
  alias Atrium.Notifications

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user   = conn.assigns.current_user

    notifications = Notifications.list_recent(prefix, user.id, 50)

    items =
      Enum.map(notifications, fn n ->
        %{notification: n, link: Notifications.link_for(prefix, n)}
      end)

    :ok = Notifications.mark_all_read(prefix, user.id)

    render(conn, :index, items: items)
  end

  def mark_read(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user   = conn.assigns.current_user

    case Notifications.mark_read(prefix, user.id, id) do
      {:ok, _}           -> redirect(conn, to: ~p"/notifications")
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Notification not found.")
        |> redirect(to: ~p"/notifications")
    end
  end

  # Marks the notification read, then forwards to the resource it points at.
  def go(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user   = conn.assigns.current_user

    case Notifications.get(prefix, user.id, id) do
      nil ->
        conn |> put_flash(:error, "Notification not found.") |> redirect(to: ~p"/notifications")

      notification ->
        Notifications.mark_read(prefix, user.id, id)

        case Notifications.link_for(prefix, notification) do
          nil  -> redirect(conn, to: ~p"/notifications")
          link -> redirect(conn, to: link)
        end
    end
  end
end
