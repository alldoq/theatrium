defmodule AtriumWeb.DirectoryController do
  use AtriumWeb, :controller
  alias Atrium.Accounts

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "directory"}]
       when action in [:index, :show]

  def index(conn, params) do
    prefix = conn.assigns.tenant_prefix
    users = Accounts.list_active_users(prefix)

    users =
      if q = params["q"] do
        q = String.downcase(q)
        Enum.filter(users, fn u ->
          String.contains?(String.downcase(u.name), q) or
          String.contains?(String.downcase(u.email), q) or
          (u.department && String.contains?(String.downcase(u.department), q)) or
          (u.role && String.contains?(String.downcase(u.role), q))
        end)
      else
        users
      end

    render(conn, :index, users: users, query: params["q"] || "")
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = Accounts.get_user!(prefix, id)
    render(conn, :show, profile: user)
  end
end
