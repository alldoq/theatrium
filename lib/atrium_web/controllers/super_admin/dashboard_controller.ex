defmodule AtriumWeb.SuperAdmin.DashboardController do
  use AtriumWeb, :controller

  def index(conn, _params) do
    render(conn, :index, super_admin: conn.assigns.super_admin, tenants: Atrium.Tenants.list_tenants())
  end
end
