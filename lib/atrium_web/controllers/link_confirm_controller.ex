defmodule AtriumWeb.LinkConfirmController do
  use AtriumWeb, :controller
  alias Atrium.Accounts.Provisioning

  def new(conn, _params) do
    ticket = get_session(conn, :link_ticket)
    if is_nil(ticket) do
      conn |> put_flash(:error, "Session expired.") |> redirect(to: "/login")
    else
      render(conn, :new, tenant: conn.assigns.tenant, error: nil)
    end
  end

  def create(conn, %{"password" => password}) do
    prefix = conn.assigns.tenant_prefix
    ticket = get_session(conn, :link_ticket)

    case ticket && Provisioning.confirm_link(prefix, ticket, password) do
      nil ->
        conn |> put_flash(:error, "Session expired.") |> redirect(to: "/login")

      {:ok, user} ->
        {:ok, %{token: token}} = Atrium.Accounts.create_session(prefix, user, %{
          ip: conn.remote_ip |> :inet.ntoa() |> to_string()
        })
        conn
        |> delete_session(:link_ticket)
        |> put_resp_cookie("_atrium_session", token,
             http_only: true, secure: true, same_site: "Lax",
             max_age: conn.assigns.tenant.session_idle_timeout_minutes * 60)
        |> redirect(to: "/")

      {:error, :invalid_credentials} ->
        render(conn, :new, tenant: conn.assigns.tenant, error: "Invalid password.")

      {:error, _} ->
        conn |> put_flash(:error, "Link expired. Please sign in again.") |> redirect(to: "/login")
    end
  end
end
