defmodule AtriumWeb.PageController do
  use AtriumWeb, :controller

  def home(conn, _params) do
    render(conn, :home, tenant: conn.assigns.tenant, nav: conn.assigns[:nav] || [])
  end
end
