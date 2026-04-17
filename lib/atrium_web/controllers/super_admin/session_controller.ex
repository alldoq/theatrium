defmodule AtriumWeb.SuperAdmin.SessionController do
  use AtriumWeb, :controller

  alias Atrium.{Audit, SuperAdmins}

  def new(conn, _params) do
    render(conn, :new, error: nil, email: "")
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case SuperAdmins.authenticate(email, password) do
      {:ok, sa} ->
        {:ok, _} =
          Audit.log_global("super_admin.login", %{
            actor: {:super_admin, sa.id},
            resource: {"SuperAdmin", sa.id},
            context: request_context(conn)
          })

        conn
        |> renew_session()
        |> put_session(:super_admin_id, sa.id)
        |> redirect(to: "/super")

      {:error, reason} ->
        {:ok, _} =
          Audit.log_global("super_admin.login_failed", %{
            actor: :system,
            context: Map.merge(request_context(conn), %{"email" => email, "reason" => to_string(reason)})
          })

        conn
        |> put_status(:ok)
        |> render(:new, error: "Invalid credentials", email: email)
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/super/login")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp request_context(conn) do
    %{
      "ip" => conn.remote_ip |> :inet.ntoa() |> to_string(),
      "user_agent" => get_req_header(conn, "user-agent") |> List.first() || ""
    }
  end
end
