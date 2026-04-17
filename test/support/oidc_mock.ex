defmodule Atrium.Test.OidcMock do
  use Plug.Router

  @priv_key_pem File.read!("test/fixtures/oidc_mock_key.pem")
  @pub_jwk Jason.decode!(File.read!("test/fixtures/oidc_mock_jwk.json"))

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug :match
  plug :dispatch

  get "/.well-known/openid-configuration" do
    issuer = base_url(conn)
    body = %{
      issuer: issuer,
      authorization_endpoint: issuer <> "/authorize",
      token_endpoint: issuer <> "/token",
      jwks_uri: issuer <> "/jwks",
      response_types_supported: ["code"],
      subject_types_supported: ["public"],
      id_token_signing_alg_values_supported: ["RS256"]
    }
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end

  get "/jwks" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{keys: [@pub_jwk]}))
  end

  get "/authorize" do
    conn = fetch_query_params(conn)
    %{"state" => state, "redirect_uri" => redirect_uri} = conn.query_params
    code = "mock_code_" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    Agent.update(agent(), &Map.put(&1, code, conn.query_params))
    conn
    |> put_resp_header("location", "#{redirect_uri}?code=#{code}&state=#{state}")
    |> send_resp(302, "")
  end

  post "/token" do
    params = conn.body_params
    code = params["code"]

    case Agent.get(agent(), &Map.fetch(&1, code)) do
      {:ok, _stash} ->
        Agent.update(agent(), &Map.delete(&1, code))
        sub = "mock-sub-" <> Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
        overrides = Agent.get(agent(), &Map.get(&1, :next_claims, %{}))
        Agent.update(agent(), &Map.delete(&1, :next_claims))

        claims = %{
          "iss" => base_url(conn),
          "sub" => sub,
          "aud" => "atrium-test",
          "exp" => System.system_time(:second) + 600,
          "iat" => System.system_time(:second),
          "email" => Map.get(overrides, :email, "sso@example.com"),
          "name" => Map.get(overrides, :name, "SSO User")
        }

        id_token = sign_id_token(claims)
        body = %{access_token: "access-123", id_token: id_token, token_type: "Bearer", expires_in: 3600}
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(body))

      :error ->
        send_resp(conn, 400, ~s({"error":"invalid_grant"}))
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  def set_next_claims(email: email, name: name) do
    Agent.update(agent(), &Map.put(&1, :next_claims, %{email: email, name: name}))
  end

  defp sign_id_token(claims) do
    jwk = JOSE.JWK.from_pem(@priv_key_pem)
    {_, token} =
      JOSE.JWS.sign(jwk, Jason.encode!(claims), %{"alg" => "RS256", "typ" => "JWT"})
      |> JOSE.JWS.compact()
    token
  end

  defp base_url(_conn), do: "http://localhost:#{port()}"
  defp port, do: Application.get_env(:atrium, :oidc_mock_port, 4100)
  defp agent, do: Atrium.Test.OidcMock.Agent
end
