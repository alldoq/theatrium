defmodule AtriumWeb.LearningControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.Learning
  alias Atrium.Accounts
  alias Atrium.Authorization
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "lc_#{:erlang.unique_integer([:positive])}"
    host = "#{slug}.atrium.example"

    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Learning Ctrl Test"})
    {:ok, _tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)

    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: user}} =
      Accounts.invite_user(prefix, %{
        email: "lc_actor_#{System.unique_integer([:positive])}@example.com",
        name: "LC Actor"
      })

    {:ok, user} =
      Accounts.activate_user_with_password(prefix, user, %{
        password: "Correct-horse-battery1",
        password_confirmation: "Correct-horse-battery1"
      })

    Authorization.grant_section(prefix, "learning", {:user, user.id}, :view)
    Authorization.grant_section(prefix, "learning", {:user, user.id}, :edit)

    conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: user.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    {:ok, conn: conn, user: user, prefix: prefix}
  end

  defp build_published_course(prefix, user) do
    {:ok, course} = Learning.create_course(prefix, %{title: "Safety 101", category: "Compliance"}, user)
    {:ok, course} = Learning.publish_course(prefix, course)
    course
  end

  describe "GET /learning" do
    test "renders published courses", %{conn: conn, user: user, prefix: prefix} do
      build_published_course(prefix, user)
      conn = get(conn, "/learning")
      assert html_response(conn, 200) =~ "Safety 101"
    end

    test "does not show draft courses to regular staff", %{conn: conn, user: user, prefix: prefix} do
      Authorization.revoke_section(prefix, "learning", {:user, user.id}, :edit)
      Learning.create_course(prefix, %{title: "Draft Course", category: "HR"}, user)
      conn = get(conn, "/learning")
      html = html_response(conn, 200)
      refute html =~ "Draft Course"
    end
  end

  describe "GET /learning/:id" do
    test "renders course show page", %{conn: conn, user: user, prefix: prefix} do
      course = build_published_course(prefix, user)
      conn = get(conn, "/learning/#{course.id}")
      assert html_response(conn, 200) =~ "Safety 101"
    end

    test "returns 404 for draft course accessed by non-editor", %{conn: conn, user: user, prefix: prefix} do
      # Revoke edit permission so user can only view
      Authorization.revoke_section(prefix, "learning", {:user, user.id}, :edit)
      {:ok, draft} = Learning.create_course(prefix, %{title: "Draft", category: "HR"}, user)
      conn = get(conn, "/learning/#{draft.id}")
      assert html_response(conn, 404)
    end
  end

  describe "POST /learning/:id/complete" do
    test "marks course as complete and redirects", %{conn: conn, user: user, prefix: prefix} do
      course = build_published_course(prefix, user)
      conn = post(conn, "/learning/#{course.id}/complete")
      assert redirected_to(conn) == "/learning/#{course.id}"
      assert Learning.completed?(prefix, course.id, user.id)
    end
  end

  describe "DELETE /learning/:id/complete" do
    test "removes completion and redirects", %{conn: conn, user: user, prefix: prefix} do
      course = build_published_course(prefix, user)
      Learning.complete_course(prefix, course.id, user.id)
      conn = delete(conn, "/learning/#{course.id}/complete")
      assert redirected_to(conn) == "/learning/#{course.id}"
      refute Learning.completed?(prefix, course.id, user.id)
    end
  end
end
