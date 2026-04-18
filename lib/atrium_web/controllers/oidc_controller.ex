defmodule AtriumWeb.OidcController do
  use AtriumWeb, :controller

  alias Atrium.Accounts
  alias Atrium.Accounts.{Idp, Provisioning}

  def start(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    idp = Idp.get_idp!(prefix, id)
    config = assent_config(idp, conn)

    case Assent.Strategy.OIDC.authorize_url(config) do
      {:ok, %{session_params: sp, url: url}} ->
        conn
        |> put_session(:oidc_state, sp[:state])
        |> put_session(:oidc_nonce, sp[:nonce])
        |> put_session(:oidc_idp_id, idp.id)
        |> put_session(:oidc_session_params, sp)
        |> redirect(external: url)

      {:error, reason} ->
        conn |> put_flash(:error, "IdP error: #{inspect(reason)}") |> redirect(to: "/login")
    end
  end

  def callback(conn, params) do
    case get_session(conn, :oidc_idp_id) do
      nil ->
        conn |> put_flash(:error, "Session expired. Please try signing in again.") |> redirect(to: "/login")

      idp_id ->
        prefix = conn.assigns.tenant_prefix
        idp = Idp.get_idp!(prefix, idp_id)
        config =
          assent_config(idp, conn)
          |> Keyword.put(:session_params, get_session(conn, :oidc_session_params))

        case Assent.Strategy.OIDC.callback(config, params) do
          {:ok, %{user: claims}} ->
            case Provisioning.upsert_from_idp(prefix, idp, claims) do
              {:ok, user} ->
                finalise_login(conn, user, prefix)

              {:error, :user_not_found} ->
                conn
                |> clear_oidc_session()
                |> put_flash(:error, "Your account is not provisioned in this tenant.")
                |> redirect(to: "/login")

              {:needs_password_confirmation, ticket} ->
                conn
                |> clear_oidc_session()
                |> put_session(:link_ticket, ticket)
                |> redirect(to: "/auth/link/confirm")
            end

          {:error, reason} ->
            conn
            |> clear_oidc_session()
            |> put_flash(:error, "Sign-in failed: #{inspect(reason)}")
            |> redirect(to: "/login")
        end
    end
  end

  defp finalise_login(conn, user, prefix) do
    with {:ok, %{token: token}} <-
           Accounts.create_session(prefix, user, %{
             ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
             user_agent: get_req_header(conn, "user-agent") |> List.first() || ""
           }) do
      conn
      |> clear_oidc_session()
      |> put_resp_cookie("_atrium_session", token,
           http_only: true, secure: true, same_site: "Lax",
           max_age: conn.assigns.tenant.session_idle_timeout_minutes * 60)
      |> redirect(to: "/")
    else
      _ ->
        conn
        |> clear_oidc_session()
        |> put_flash(:error, "Login failed. Please try again.")
        |> redirect(to: "/login")
    end
  end

  defp clear_oidc_session(conn) do
    conn
    |> delete_session(:oidc_state)
    |> delete_session(:oidc_nonce)
    |> delete_session(:oidc_idp_id)
    |> delete_session(:oidc_session_params)
  end

  defp assent_config(idp, conn) do
    # Assent 0.3.x requires :base_url (the OIDC issuer origin).
    # :openid_configuration_uri can be the full discovery URL when it doesn't
    # start with "/" — Assent uses it verbatim in that case.
    %URI{scheme: scheme, host: host, port: port} = URI.parse(idp.discovery_url)
    base_url = "#{scheme}://#{host}:#{port}"

    [
      client_id: idp.client_id,
      client_secret: idp.client_secret,
      redirect_uri: url(conn, ~p"/auth/oidc/callback"),
      base_url: base_url,
      openid_configuration_uri: idp.discovery_url
    ]
  end
end
