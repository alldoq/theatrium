defmodule AtriumWeb.SessionController do
  use AtriumWeb, :controller
  alias Atrium.Accounts

  @cookie_name "_atrium_session"
  @cookie_opts [http_only: true, secure: true, same_site: "Lax"]

  def new(conn, _params) do
    idps = Atrium.Accounts.Idp.list_enabled(conn.assigns.tenant_prefix)
    render(conn, :new, email: "", error: nil, tenant: conn.assigns.tenant, idps: idps)
  end

  def create(conn, %{"email" => email, "password" => password}) do
    prefix = conn.assigns.tenant_prefix

    case Accounts.authenticate_by_password(prefix, email, password) do
      {:ok, user} ->
        {:ok, %{token: token}} =
          Accounts.create_session(prefix, user, %{
            ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
            user_agent: get_req_header(conn, "user-agent") |> List.first() || ""
          }, ttl_minutes: conn.assigns.tenant.session_idle_timeout_minutes)

        conn
        |> put_resp_cookie(@cookie_name, token,
             Keyword.put(@cookie_opts, :max_age, conn.assigns.tenant.session_idle_timeout_minutes * 60))
        |> redirect(to: "/")

      {:error, _reason} ->
        idps = Atrium.Accounts.Idp.list_enabled(prefix)
        conn |> put_status(:ok) |> render(:new, email: email, error: "Invalid credentials", tenant: conn.assigns.tenant, idps: idps)
    end
  end

  def delete(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    case conn.req_cookies[@cookie_name] do
      nil -> :ok
      token -> _ = Accounts.revoke_session(prefix, token)
    end

    conn
    |> delete_resp_cookie(@cookie_name)
    |> redirect(to: "/login")
  end
end
