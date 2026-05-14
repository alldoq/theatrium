defmodule AtriumWeb.PageController do
  use AtriumWeb, :controller
  alias Atrium.Home

  def home(conn, _params) do
    tenant = conn.assigns.tenant
    prefix = conn.assigns[:tenant_prefix]
    user = conn.assigns[:current_user]

    {announcements, quick_links, upcoming_events, staff_count, can_edit_home} =
      if prefix && user do
        {
          Home.list_announcements(prefix) |> Enum.take(3),
          Home.list_quick_links(prefix),
          Atrium.Events.list_upcoming_events(prefix, nil, 4),
          Atrium.Accounts.list_active_users(prefix) |> length(),
          Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "home"})
        }
      else
        {[], [], [], 0, false}
      end

    render(conn, :home,
      tenant: tenant,
      nav: conn.assigns[:nav] || [],
      announcements: announcements,
      quick_links: quick_links,
      upcoming_events: upcoming_events,
      staff_count: staff_count,
      can_edit_home: can_edit_home,
      current_user: user
    )
  end
end
