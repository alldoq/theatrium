defmodule AtriumWeb.SamlController do
  use AtriumWeb, :controller
  alias Atrium.Accounts
  alias Atrium.Accounts.{Idp, Provisioning}

  def start(conn, %{"id" => id}) do
    idp = Idp.get_idp!(conn.assigns.tenant_prefix, id)
    sp_metadata = build_sp_metadata(conn, idp)
    idp_metadata = parse_idp_metadata(idp.metadata_xml)
    {authn_req_xml, relay_state} = build_authn_request(sp_metadata, idp_metadata)

    conn
    |> put_session(:saml_idp_id, idp.id)
    |> put_session(:saml_relay_state, relay_state)
    |> render_saml_post_redirect(idp_metadata, authn_req_xml, relay_state)
  end

  def consume(conn, %{"SAMLResponse" => response_b64} = params) do
    prefix = conn.assigns.tenant_prefix
    idp_id = get_session(conn, :saml_idp_id)

    case idp_id do
      nil ->
        conn |> put_flash(:error, "Session expired.") |> redirect(to: "/login")

      _ ->
        idp = Idp.get_idp!(prefix, idp_id)
        idp_metadata = parse_idp_metadata(idp.metadata_xml)

        case validate_assertion(response_b64, params["RelayState"], idp_metadata) do
          {:ok, claims} ->
            case Provisioning.upsert_from_idp(prefix, idp, claims) do
              {:ok, user} -> finalise_login(conn, user, prefix)
              {:error, :user_not_found} ->
                conn |> put_flash(:error, "Not provisioned.") |> redirect(to: "/login")
              {:needs_password_confirmation, ticket} ->
                conn |> put_session(:link_ticket, ticket) |> redirect(to: "/auth/link/confirm")
            end

          {:error, reason} ->
            conn |> put_flash(:error, "SAML error: #{inspect(reason)}") |> redirect(to: "/login")
        end
    end
  end

  defp finalise_login(conn, user, prefix) do
    with {:ok, %{token: token}} <- Accounts.create_session(prefix, user, %{}) do
      conn
      |> delete_session(:saml_idp_id)
      |> delete_session(:saml_relay_state)
      |> put_resp_cookie("_atrium_session", token,
           http_only: true, secure: true, same_site: "Lax",
           max_age: conn.assigns.tenant.session_idle_timeout_minutes * 60)
      |> redirect(to: "/")
    else
      _ -> conn |> put_flash(:error, "Login failed. Please try again.") |> redirect(to: "/login")
    end
  end

  # Stubs — full SAML implementation is a future task (requires :esaml NIF work)
  defp build_sp_metadata(_conn, _idp),
    do: raise("SAML SP metadata not implemented — see plan 0c task 8")

  defp parse_idp_metadata(_xml),
    do: raise("SAML IdP metadata parsing not implemented — see plan 0c task 8")

  defp build_authn_request(_sp, _idp),
    do: raise("SAML AuthnRequest not implemented — see plan 0c task 8")

  defp render_saml_post_redirect(_conn, _idp_metadata, _xml, _relay),
    do: raise("SAML POST binding not implemented — see plan 0c task 8")

  defp validate_assertion(_response_b64, _relay, _idp_metadata),
    do: raise("SAML assertion validation not implemented — see plan 0c task 8")
end
