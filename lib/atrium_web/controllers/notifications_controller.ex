defmodule AtriumWeb.NotificationsController do
  use AtriumWeb, :controller
  alias Atrium.Notifications

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user   = conn.assigns.current_user

    notifications = Notifications.list_recent(prefix, user.id, 50)
    :ok = Notifications.mark_all_read(prefix, user.id)

    render(conn, :index, notifications: notifications)
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
end
