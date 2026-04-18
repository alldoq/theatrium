defmodule AtriumWeb.FormControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.{Tenants, Accounts, Authorization}
  alias Atrium.Tenants.Provisioner
  alias Atrium.Forms

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "form_ctrl_test", name: "Form Ctrl Test"})
    {:ok, tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop("form_ctrl_test") end)

    prefix = Triplex.to_prefix("form_ctrl_test")
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{email: "fctrl@example.com", name: "Form Ctrl"})
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "hr", {:user, user.id}, :edit)
    Authorization.grant_section(prefix, "hr", {:user, user.id}, :approve)

    conn =
      build_conn()
      |> Map.put(:host, "form_ctrl_test.atrium.example")
      |> post("/login", %{email: "fctrl@example.com", password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, "form_ctrl_test.atrium.example")

    {:ok, conn: conn, prefix: prefix, user: user, tenant: tenant}
  end

  describe "GET /sections/hr/forms" do
    test "returns 200", %{conn: conn} do
      conn = get(conn, "/sections/hr/forms")
      assert html_response(conn, 200) =~ "Forms"
    end
  end

  describe "GET /sections/hr/forms/new" do
    test "renders new form", %{conn: conn} do
      conn = get(conn, "/sections/hr/forms/new")
      assert html_response(conn, 200) =~ "New form"
    end
  end

  describe "POST /sections/hr/forms" do
    test "creates form and redirects to edit", %{conn: conn} do
      conn = post(conn, "/sections/hr/forms", %{form: %{title: "Leave Request"}})
      assert redirected_to(conn) =~ "/sections/hr/forms/"
      assert redirected_to(conn) =~ "/edit"
    end

    test "re-renders new on invalid attrs", %{conn: conn} do
      conn = post(conn, "/sections/hr/forms", %{form: %{title: ""}})
      assert html_response(conn, 422) =~ "New form"
    end
  end

  describe "GET /sections/hr/forms/:id" do
    test "shows form", %{conn: conn, prefix: prefix, user: user} do
      {:ok, form} = Forms.create_form(prefix, %{title: "ShowMe", section_key: "hr"}, user)
      conn = get(conn, "/sections/hr/forms/#{form.id}")
      assert html_response(conn, 200) =~ "ShowMe"
    end
  end

  describe "GET /sections/hr/forms/:id/edit" do
    test "renders builder for draft form", %{conn: conn, prefix: prefix, user: user} do
      {:ok, form} = Forms.create_form(prefix, %{title: "EditMe", section_key: "hr"}, user)
      conn = get(conn, "/sections/hr/forms/#{form.id}/edit")
      assert html_response(conn, 200) =~ "FormBuilderIsland"
    end
  end

  describe "POST /sections/hr/forms/:id/publish" do
    test "publishes form", %{conn: conn, prefix: prefix, user: user} do
      {:ok, form} = Forms.create_form(prefix, %{title: "Pub", section_key: "hr"}, user)
      conn = post(conn, "/sections/hr/forms/#{form.id}/publish", %{form: %{fields: "[]"}})
      assert redirected_to(conn) =~ "/sections/hr/forms/#{form.id}"
      assert Forms.get_form!(prefix, form.id).status == "published"
    end
  end

  describe "GET /sections/hr/forms/:id/submit" do
    test "renders submit form for published form", %{conn: conn, prefix: prefix, user: user} do
      {:ok, form} = Forms.create_form(prefix, %{title: "Fill Me", section_key: "hr"}, user)
      {:ok, _} = Forms.publish_form(prefix, form, [], user)
      conn = get(conn, "/sections/hr/forms/#{form.id}/submit")
      assert html_response(conn, 200) =~ "Fill Me"
    end
  end

  describe "POST /sections/hr/forms/:id/submit" do
    test "creates submission and redirects to show", %{conn: conn, prefix: prefix, user: user} do
      {:ok, form} = Forms.create_form(prefix, %{title: "Sub", section_key: "hr"}, user)
      {:ok, _} = Forms.publish_form(prefix, form, [], user)
      conn = post(conn, "/sections/hr/forms/#{form.id}/submit", %{submission: %{}})
      assert redirected_to(conn) =~ "/sections/hr/forms/#{form.id}/submissions/"
    end
  end

  describe "authorization" do
    test "POST /sections/hr/forms returns 403 for user without :edit", %{prefix: prefix} do
      {:ok, %{user: viewer}} = Accounts.invite_user(prefix, %{email: "fviewer@example.com", name: "Viewer"})
      {:ok, _viewer} = Accounts.activate_user_with_password(prefix, viewer, %{
        password: "Correct-horse-battery1",
        password_confirmation: "Correct-horse-battery1"
      })
      viewer_conn =
        build_conn()
        |> Map.put(:host, "form_ctrl_test.atrium.example")
        |> post("/login", %{email: "fviewer@example.com", password: "Correct-horse-battery1"})
        |> recycle()
        |> Map.put(:host, "form_ctrl_test.atrium.example")
      viewer_conn = post(viewer_conn, "/sections/hr/forms", %{form: %{title: "X"}})
      assert viewer_conn.status == 403
    end
  end
end
