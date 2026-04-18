defmodule AtriumWeb.AuditViewerControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.Accounts
  alias Atrium.Audit
  alias Atrium.Authorization
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup %{conn: conn} do
    {:ok, t} = Tenants.create_tenant_record(%{slug: "av_test", name: "AV"})
    {:ok, t} = Provisioner.provision(t)
    prefix = Triplex.to_prefix(t.slug)

    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")

    # Add user to compliance_officers group (seeded by provisioning)
    g = Authorization.get_group_by_slug(prefix, "compliance_officers")
    {:ok, _} = Authorization.add_member(prefix, user, g)

    # Grant compliance:view to compliance_officers (seed may already have done this — use on_conflict :nothing behavior)
    {:ok, _} = Authorization.grant_section(prefix, "compliance", {:group, g.id}, :view)

    {:ok, %{token: session_token}} = Accounts.create_session(prefix, user, %{})
    {:ok, _} = Audit.log(prefix, "test.event", %{actor: :system})

    conn =
      conn
      |> Map.put(:host, "av_test.atrium.example")
      |> Plug.Test.put_req_cookie("_atrium_session", session_token)
      |> fetch_cookies()

    on_exit(fn -> _ = Triplex.drop("av_test") end)

    {:ok, conn: conn}
  end

  test "compliance officers can view the audit log", %{conn: conn} do
    conn = get(conn, "/audit")
    assert html_response(conn, 200) =~ "test.event"
  end
end
