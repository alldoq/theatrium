defmodule AtriumWeb.OidcControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.Accounts
  alias Atrium.Accounts.Idp
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup %{conn: conn} do
    {:ok, t} = Tenants.create_tenant_record(%{slug: "oidc_test", name: "OIDC Test"})
    on_exit(fn -> _ = Triplex.drop("oidc_test") end)
    {:ok, t} = Provisioner.provision(t)
    prefix = Triplex.to_prefix(t.slug)

    {:ok, idp} =
      Idp.create_idp(prefix, %{
        kind: "oidc",
        name: "MockIdP",
        discovery_url: "http://localhost:4100/.well-known/openid-configuration",
        client_id: "atrium-test",
        client_secret: "doesnt-matter",
        provisioning_mode: "auto_create"
      })

    conn = Map.put(conn, :host, "oidc_test.atrium.example")
    {:ok, conn: conn, idp: idp, prefix: prefix}
  end

  test "GET /auth/oidc/:id/start redirects to IdP authorize URL", %{conn: conn, idp: idp} do
    conn = get(conn, "/auth/oidc/#{idp.id}/start")
    assert conn.status == 302
    loc = get_resp_header(conn, "location") |> List.first()
    assert loc =~ "localhost:4100"
    assert loc =~ "/authorize"
    assert get_session(conn, :oidc_state) != nil
  end

  test "full OIDC flow: start → callback creates user and logs in", %{conn: conn, idp: idp, prefix: prefix} do
    Atrium.Test.OidcMock.set_next_claims(email: "oidc-new@e.co", name: "OIDC New")

    # Step 1: Start — get the authorize URL + session state
    conn1 = get(conn, "/auth/oidc/#{idp.id}/start")
    assert conn1.status == 302
    authorize_url = get_resp_header(conn1, "location") |> List.first()
    state = get_session(conn1, :oidc_state)

    # Step 2: Hit mock /authorize to get the code (mock redirects back with code)
    {:ok, {{_, 302, _}, resp_headers, _}} =
      :httpc.request(:get, {String.to_charlist(authorize_url), []}, [{:autoredirect, false}], [])

    location_header = Enum.find(resp_headers, fn {k, _} -> to_string(k) == "location" end)
    {_, cb_url_str} = location_header
    cb_url = URI.parse(to_string(cb_url_str))
    cb_params = URI.decode_query(cb_url.query)
    code = cb_params["code"]

    # Step 3: Hit our callback with the code + state, carrying the session from step 1
    %URI{query: query} = URI.parse(authorize_url)
    authorize_params = URI.decode_query(query)
    redirect_uri = authorize_params["redirect_uri"]
    callback_path = URI.parse(redirect_uri).path

    conn2 =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:oidc_state, state)
      |> Plug.Conn.put_session(:oidc_nonce, get_session(conn1, :oidc_nonce))
      |> Plug.Conn.put_session(:oidc_idp_id, get_session(conn1, :oidc_idp_id))
      |> Plug.Conn.put_session(:oidc_session_params, get_session(conn1, :oidc_session_params))
      |> Map.put(:host, "oidc_test.atrium.example")
      |> get("#{callback_path}?code=#{code}&state=#{state}")

    assert redirected_to(conn2) == "/"
    assert conn2.resp_cookies["_atrium_session"]
    assert Accounts.list_users(prefix) |> Enum.any?(&(&1.email == "oidc-new@e.co"))
  end
end
