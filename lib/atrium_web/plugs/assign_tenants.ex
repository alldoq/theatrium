defmodule AtriumWeb.Plugs.AssignTenants do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    assign(conn, :all_tenants, Atrium.Tenants.list_tenants())
  end
end
