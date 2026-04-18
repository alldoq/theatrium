defmodule AtriumWeb.Plugs.RequireTenantAdmin do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %{is_admin: true, status: "active"} ->
        conn

      _ ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(403, "Forbidden")
        |> halt()
    end
  end
end
