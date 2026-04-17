defmodule AtriumWeb.PasswordResetController do
  use AtriumWeb, :controller
  alias Atrium.Accounts
  alias Atrium.Accounts.Emails
  alias Atrium.Mailer

  def new(conn, _params) do
    render(conn, :new, email: "", tenant: conn.assigns.tenant)
  end

  def create(conn, %{"email" => email}) do
    prefix = conn.assigns.tenant_prefix

    case Accounts.request_password_reset(prefix, email) do
      {:ok, %{token: token, user: user}} ->
        url = url(~p"/password-reset/#{token}")
        Mailer.deliver(Emails.password_reset_email(conn.assigns.tenant, user.email, url))

      _ ->
        :ok
    end

    conn
    |> put_flash(:info, "If that email exists, a reset link has been sent.")
    |> redirect(to: "/login")
  end

  def edit(conn, %{"token" => token}) do
    render(conn, :edit, token: token, error: nil, tenant: conn.assigns.tenant)
  end

  def update(conn, %{"token" => token, "password" => password}) do
    prefix = conn.assigns.tenant_prefix

    case Accounts.reset_password(prefix, token, password) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Password updated. Please sign in.")
        |> redirect(to: "/login")

      {:error, :invalid_or_expired_token} ->
        conn
        |> put_status(:not_found)
        |> render(:edit, token: token, error: "This link is invalid or expired.", tenant: conn.assigns.tenant)

      {:error, %Ecto.Changeset{} = cs} ->
        error =
          case Keyword.get_values(cs.errors, :password) do
            [{msg, _} | _] -> msg
            _ -> "Invalid password"
          end

        render(conn, :edit, token: token, error: error, tenant: conn.assigns.tenant)
    end
  end
end
