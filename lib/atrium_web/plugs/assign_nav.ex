defmodule AtriumWeb.Plugs.AssignNav do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case {conn.assigns[:tenant], conn.assigns[:current_user], conn.assigns[:tenant_prefix]} do
      {nil, _, _} -> conn
      {_, nil, _} -> conn
      {tenant, user, prefix} ->
        nav = Atrium.AppShell.nav_for_user(tenant, user, prefix)
        unread = Atrium.Notifications.count_unread(prefix, user.id)

        conn
        |> assign(:nav, nav)
        |> assign(:unread_notification_count, unread)
    end
  end
end
