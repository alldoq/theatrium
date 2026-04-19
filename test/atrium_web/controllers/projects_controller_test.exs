defmodule AtriumWeb.ProjectsControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Accounts, Authorization, Tenants, Projects}
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "pr_#{:erlang.unique_integer([:positive])}"
    host = "#{slug}.atrium.example"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Projects Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: viewer}} = Accounts.invite_user(prefix, %{
      email: "viewer_#{System.unique_integer([:positive])}@example.com",
      name: "Viewer"
    })
    {:ok, viewer} = Accounts.activate_user_with_password(prefix, viewer, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "projects", {:user, viewer.id}, :view)

    {:ok, %{user: editor}} = Accounts.invite_user(prefix, %{
      email: "editor_#{System.unique_integer([:positive])}@example.com",
      name: "Editor"
    })
    {:ok, editor} = Accounts.activate_user_with_password(prefix, editor, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "projects", {:user, editor.id}, :view)
    Authorization.grant_section(prefix, "projects", {:user, editor.id}, :edit)

    viewer_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: viewer.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    editor_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: editor.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    {:ok, viewer_conn: viewer_conn, editor_conn: editor_conn, prefix: prefix, viewer: viewer, editor: editor}
  end

  test "GET /projects shows index to viewer", %{viewer_conn: viewer_conn} do
    conn = get(viewer_conn, "/projects")
    assert html_response(conn, 200) =~ "Projects"
  end

  test "GET /projects shows New project button to editor only", %{viewer_conn: viewer_conn, editor_conn: editor_conn} do
    assert get(editor_conn, "/projects") |> html_response(200) =~ "New project"
    refute get(viewer_conn, "/projects") |> html_response(200) =~ "New project"
  end

  test "POST /projects creates project and redirects", %{editor_conn: editor_conn} do
    conn = post(editor_conn, "/projects", %{"project" => %{"title" => "Alpha Project", "description" => "Test"}})
    assert redirected_to(conn) =~ "/projects/"
  end

  test "GET /projects/:id shows project to viewer", %{viewer_conn: viewer_conn, prefix: prefix, editor: editor} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Visible"}, editor)
    conn = get(viewer_conn, "/projects/#{project.id}")
    assert html_response(conn, 200) =~ "Visible"
  end

  test "GET /projects/:id shows edit controls to editor only", %{viewer_conn: viewer_conn, editor_conn: editor_conn, prefix: prefix, editor: editor} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Controls"}, editor)
    assert get(editor_conn, "/projects/#{project.id}") |> html_response(200) =~ "Edit"
    refute get(viewer_conn, "/projects/#{project.id}") |> html_response(200) =~ ~s(href="/projects/#{project.id}/edit")
  end

  test "POST /projects/:id/updates adds an update", %{viewer_conn: viewer_conn, prefix: prefix, editor: editor} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "Updates"}, editor)
    conn = post(viewer_conn, "/projects/#{project.id}/updates", %{"update" => %{"body" => "Hello world"}})
    assert redirected_to(conn) =~ "/projects/#{project.id}"
    assert length(Projects.list_updates(prefix, project.id)) == 1
  end

  test "POST /projects/:id/archive archives project", %{editor_conn: editor_conn, prefix: prefix, editor: editor} do
    {:ok, project} = Projects.create_project(prefix, %{"title" => "To archive"}, editor)
    conn = post(editor_conn, "/projects/#{project.id}/archive")
    assert redirected_to(conn) == "/projects"
    assert Projects.get_project!(prefix, project.id).status == "archived"
  end
end
