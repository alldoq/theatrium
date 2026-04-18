defmodule AtriumWeb.TenantAdmin.UserControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.Accounts

  @tenant_slug "adminctrltest"
  @host "#{@tenant_slug}.atrium.example"

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)
    {:ok, tenant} = Atrium.Tenants.create_tenant_record(%{slug: @tenant_slug, name: "AdminCtrlTest"})
    {:ok, tenant} = Atrium.Tenants.Provisioner.provision(tenant)
    prefix = Triplex.to_prefix(@tenant_slug)

    {:ok, %{user: admin}} = Accounts.invite_user(prefix, %{email: "admin@t.com", name: "Admin"})
    {:ok, admin} = Accounts.activate_user_with_password(prefix, admin, %{
      password: "Password123456",
      password_confirmation: "Password123456"
    })
    {:ok, admin} = Accounts.set_admin(prefix, admin, true)

    admin_conn =
      build_conn()
      |> Map.put(:host, @host)
      |> post("/login", %{email: "admin@t.com", password: "Password123456"})
      |> recycle()
      |> Map.put(:host, @host)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, :auto)
      Triplex.drop(@tenant_slug)
      case Atrium.Tenants.get_tenant_by_slug(@tenant_slug) do
        nil -> :ok
        t -> Atrium.Repo.delete(t)
      end
    end)

    {:ok, prefix: prefix, admin: admin, tenant: tenant, admin_conn: admin_conn}
  end

  describe "GET /admin/users" do
    test "renders user list for admin", %{admin_conn: admin_conn} do
      conn = get(admin_conn, "/admin/users")
      assert html_response(conn, 200) =~ "Users"
    end

    test "returns 403 for non-admin", %{prefix: prefix} do
      {:ok, %{user: user}} = Accounts.invite_user(prefix, %{email: "plain@t.com", name: "Plain"})
      {:ok, _user} = Accounts.activate_user_with_password(prefix, user, %{
        password: "Password123456",
        password_confirmation: "Password123456"
      })

      plain_conn =
        build_conn()
        |> Map.put(:host, @host)
        |> post("/login", %{email: "plain@t.com", password: "Password123456"})
        |> recycle()
        |> Map.put(:host, @host)

      conn = get(plain_conn, "/admin/users")
      assert response(conn, 403)
    end
  end

  describe "POST /admin/users" do
    test "creates user and redirects to show", %{admin_conn: admin_conn} do
      conn = post(admin_conn, "/admin/users", %{
        "user" => %{"name" => "New User", "email" => "new@t.com", "is_admin" => "false"}
      })
      assert redirected_to(conn) =~ "/admin/users/"
    end
  end
end
