defmodule AtriumWeb.Plugs.RequireUser do
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias Atrium.Accounts

  @cookie_name "_atrium_session"

  def init(opts), do: opts

  def call(conn, _opts) do
    prefix = conn.assigns[:tenant_prefix] || raise "RequireUser mounted without TenantResolver"

    with token when is_binary(token) <- Map.get(conn.req_cookies, @cookie_name),
         {:ok, %{user: user, session: session}} <- Accounts.get_session_by_token(prefix, token) do
      conn
      |> assign(:current_user, user)
      |> assign(:current_session, session)
    else
      _ ->
        conn
        |> delete_resp_cookie(@cookie_name)
        |> redirect(to: "/login")
        |> halt()
    end
  end
end
