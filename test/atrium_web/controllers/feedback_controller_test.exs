defmodule AtriumWeb.FeedbackControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Accounts, Authorization, Tenants, Forms}
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "fb_#{:erlang.unique_integer([:positive])}"
    host = "#{slug}.atrium.example"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Feedback Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: staff}} = Accounts.invite_user(prefix, %{
      email: "fb_staff_#{System.unique_integer([:positive])}@example.com",
      name: "Staff"
    })
    {:ok, staff} = Accounts.activate_user_with_password(prefix, staff, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "feedback", {:user, staff.id}, :view)

    {:ok, %{user: editor}} = Accounts.invite_user(prefix, %{
      email: "fb_editor_#{System.unique_integer([:positive])}@example.com",
      name: "Editor"
    })
    {:ok, editor} = Accounts.activate_user_with_password(prefix, editor, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "feedback", {:user, editor.id}, :view)
    Authorization.grant_section(prefix, "feedback", {:user, editor.id}, :edit)

    staff_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: staff.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    editor_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: editor.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    {:ok, staff_conn: staff_conn, editor_conn: editor_conn, prefix: prefix, staff: staff, editor: editor}
  end

  defp create_published_form(prefix, user) do
    {:ok, form} = Forms.create_form(prefix, %{
      "title" => "Q1 Pulse Survey",
      "section_key" => "feedback"
    }, user)
    {:ok, form} = Forms.publish_form(prefix, form, [
      %{"id" => "q1", "type" => "text", "label" => "How are you?", "required" => false}
    ], user)
    form
  end

  test "GET /feedback shows open surveys to staff", %{staff_conn: staff_conn, prefix: prefix, editor: editor} do
    create_published_form(prefix, editor)
    conn = get(staff_conn, "/feedback")
    assert html_response(conn, 200) =~ "Q1 Pulse Survey"
  end

  test "GET /feedback does not show draft surveys to staff", %{staff_conn: staff_conn, prefix: prefix, editor: editor} do
    {:ok, _} = Forms.create_form(prefix, %{"title" => "Draft Survey", "section_key" => "feedback"}, editor)
    conn = get(staff_conn, "/feedback")
    html = html_response(conn, 200)
    refute html =~ "Draft Survey"
  end

  test "GET /feedback shows all surveys to editors", %{editor_conn: editor_conn, prefix: prefix, editor: editor} do
    create_published_form(prefix, editor)
    conn = get(editor_conn, "/feedback")
    html = html_response(conn, 200)
    assert html =~ "Q1 Pulse Survey"
    assert html =~ "published"
    assert html =~ "Responses"
  end

  test "GET /feedback shows New survey button to editors", %{editor_conn: editor_conn} do
    conn = get(editor_conn, "/feedback")
    assert html_response(conn, 200) =~ "New survey"
  end

  test "GET /feedback does not show New survey button to staff", %{staff_conn: staff_conn} do
    conn = get(staff_conn, "/feedback")
    html = html_response(conn, 200)
    refute html =~ "New survey"
  end
end
