defmodule AtriumWeb.SuperAdmin.SectionControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.SuperAdmins
  alias Atrium.Sections

  setup %{conn: conn} do
    {:ok, sa} =
      SuperAdmins.create_super_admin(%{
        email: "sa_section@atrium.example",
        name: "Ops",
        password: "correct-horse-battery-staple"
      })

    conn =
      conn
      |> Map.put(:host, "admin.atrium.example")
      |> init_test_session(%{super_admin_id: sa.id})

    {:ok, conn: conn}
  end

  describe "GET /super/sections" do
    test "lists all 14 sections", %{conn: conn} do
      conn = get(conn, "/super/sections")
      assert html_response(conn, 200)
    end

    test "shows customized display name when override exists", %{conn: conn} do
      {:ok, _} = Sections.upsert_customization("home", %{display_name: "Dashboard", icon_name: nil})
      conn = get(conn, "/super/sections")
      assert html_response(conn, 200)
    end
  end

  describe "GET /super/sections/:key/edit" do
    test "renders edit form for valid section", %{conn: conn} do
      conn = get(conn, "/super/sections/home/edit")
      assert html_response(conn, 200)
    end

    test "returns 404 for unknown section key", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/super/sections/nonexistent/edit")
      end
    end
  end

  describe "PUT /super/sections/:key" do
    test "saves customization and redirects to index", %{conn: conn} do
      conn = put(conn, "/super/sections/home", %{"section" => %{"display_name" => "Dashboard", "icon_name" => "home"}})
      assert redirected_to(conn) == "/super/sections"
      assert %{display_name: "Dashboard"} = Sections.get_customization("home")
    end

    test "normalizes empty display_name to nil", %{conn: conn} do
      conn = put(conn, "/super/sections/home", %{"section" => %{"display_name" => "", "icon_name" => "home"}})
      assert redirected_to(conn) == "/super/sections"
      assert %{display_name: nil} = Sections.get_customization("home")
    end

    test "returns 404 for unknown section key", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        put(conn, "/super/sections/nonexistent", %{"section" => %{"display_name" => "x", "icon_name" => "home"}})
      end
    end
  end
end
