defmodule AtriumWeb.HealthController do
  use AtriumWeb, :controller

  def index(conn, _params) do
    tenants = length(Atrium.Tenants.list_active_tenants())
    json(conn, %{status: "ok", active_tenants: tenants})
  end
end
