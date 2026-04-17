defmodule AtriumWeb.InvitationController do
  use AtriumWeb, :controller
  alias Atrium.Accounts

  @cookie_name "_atrium_session"
  @cookie_opts [http_only: true, secure: true, same_site: "Lax"]

  def edit(conn, %{"token" => token}) do
    render(conn, :edit, token: token, error: nil, tenant: conn.assigns.tenant)
  end

  def update(conn, %{"token" => token, "password" => password}) do
    prefix = conn.assigns.tenant_prefix

    case Accounts.activate_user(prefix, token, password) do
      {:ok, user} ->
        {:ok, %{token: session_token}} =
          Accounts.create_session(prefix, user, %{
            ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
            user_agent: get_req_header(conn, "user-agent") |> List.first() || ""
          }, ttl_minutes: conn.assigns.tenant.session_idle_timeout_minutes)

        conn
        |> put_resp_cookie(@cookie_name, session_token,
             Keyword.put(@cookie_opts, :max_age, conn.assigns.tenant.session_idle_timeout_minutes * 60))
        |> redirect(to: "/")

      {:error, :invalid_or_expired_token} ->
        conn
        |> put_status(:not_found)
        |> render(:edit, token: token, error: "This invitation is invalid or expired.", tenant: conn.assigns.tenant)

      {:error, %Ecto.Changeset{} = cs} ->
        error =
          case Keyword.get_values(cs.errors, :password) do
            [{msg, _} | _] -> msg
            _ -> "Invalid password"
          end

        conn
        |> put_status(:ok)
        |> render(:edit, token: token, error: error, tenant: conn.assigns.tenant)
    end
  end
end
