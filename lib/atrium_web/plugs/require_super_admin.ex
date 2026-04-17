defmodule AtriumWeb.Plugs.RequireSuperAdmin do
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :super_admin_id) do
      nil ->
        conn |> redirect(to: "/super/login") |> halt()

      id ->
        case Atrium.SuperAdmins.get_super_admin!(id) do
          %{status: "active"} = sa -> assign(conn, :super_admin, sa)
          _ -> conn |> clear_session() |> redirect(to: "/super/login") |> halt()
        end
    end
  end
end
