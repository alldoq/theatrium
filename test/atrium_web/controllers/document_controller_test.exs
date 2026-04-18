defmodule AtriumWeb.DocumentControllerTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.{Tenants, Accounts}
  alias Atrium.Tenants.Provisioner
  alias Atrium.Documents

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "doc_ctrl_test", name: "Doc Ctrl Test"})
    {:ok, tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop("doc_ctrl_test") end)

    prefix = Triplex.to_prefix("doc_ctrl_test")
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{email: "ctrl@example.com", name: "Ctrl User"})
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })

    conn =
      build_conn()
      |> Map.put(:host, "doc_ctrl_test.atrium.example")
      |> post("/login", %{email: "ctrl@example.com", password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, "doc_ctrl_test.atrium.example")

    {:ok, conn: conn, prefix: prefix, user: user, tenant: tenant}
  end

  describe "GET /sections/:section_key/documents" do
    test "returns 200 for authenticated user with view permission", %{conn: conn} do
      conn = get(conn, "/sections/docs/documents")
      assert html_response(conn, 200) =~ "Documents"
    end
  end

  describe "GET /sections/:section_key/documents/new" do
    test "renders new form", %{conn: conn} do
      conn = get(conn, "/sections/docs/documents/new")
      assert html_response(conn, 200) =~ "trix-editor"
    end
  end

  describe "POST /sections/:section_key/documents" do
    test "creates document and redirects to show", %{conn: conn} do
      conn = post(conn, "/sections/docs/documents", %{
        document: %{title: "Test Doc", body_html: "<p>hello</p>"}
      })
      assert redirected_to(conn) =~ "/sections/docs/documents/"
    end

    test "re-renders new form on invalid attrs", %{conn: conn} do
      conn = post(conn, "/sections/docs/documents", %{document: %{title: ""}})
      assert html_response(conn, 422) =~ "trix-editor"
    end
  end

  describe "GET /sections/:section_key/documents/:id" do
    test "shows document", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "ShowMe", section_key: "docs", body_html: "<p>x</p>"}, user)
      conn = get(conn, "/sections/docs/documents/#{doc.id}")
      assert html_response(conn, 200) =~ "ShowMe"
    end
  end

  describe "GET /sections/:section_key/documents/:id/edit" do
    test "renders edit form for draft document", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "EditMe", section_key: "docs", body_html: "<p>y</p>"}, user)
      conn = get(conn, "/sections/docs/documents/#{doc.id}/edit")
      assert html_response(conn, 200) =~ "trix-editor"
    end
  end

  describe "PUT /sections/:section_key/documents/:id" do
    test "updates draft document and redirects", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "Old", section_key: "docs", body_html: ""}, user)
      conn = put(conn, "/sections/docs/documents/#{doc.id}", %{
        document: %{title: "New", body_html: "<p>new</p>"}
      })
      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
    end
  end

  describe "POST /sections/:section_key/documents/:id/submit" do
    test "transitions to in_review and redirects", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "Sub", section_key: "docs", body_html: ""}, user)
      conn = post(conn, "/sections/docs/documents/#{doc.id}/submit")
      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
      assert Documents.get_document!(prefix, doc.id).status == "in_review"
    end
  end

  describe "POST /sections/:section_key/documents/:id/reject" do
    test "transitions to draft and redirects", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "Rej", section_key: "docs", body_html: ""}, user)
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      conn = post(conn, "/sections/docs/documents/#{doc.id}/reject")
      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
      assert Documents.get_document!(prefix, doc.id).status == "draft"
    end
  end

  describe "POST /sections/:section_key/documents/:id/approve" do
    test "transitions to approved and redirects", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "App", section_key: "docs", body_html: ""}, user)
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      conn = post(conn, "/sections/docs/documents/#{doc.id}/approve")
      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
      assert Documents.get_document!(prefix, doc.id).status == "approved"
    end
  end

  describe "POST /sections/:section_key/documents/:id/archive" do
    test "transitions to archived and redirects", %{conn: conn, prefix: prefix, user: user} do
      {:ok, doc} = Documents.create_document(prefix, %{title: "Arc", section_key: "docs", body_html: ""}, user)
      {:ok, doc} = Documents.submit_for_review(prefix, doc, user)
      {:ok, doc} = Documents.approve_document(prefix, doc, user)
      conn = post(conn, "/sections/docs/documents/#{doc.id}/archive")
      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"
      assert Documents.get_document!(prefix, doc.id).status == "archived"
    end
  end
end
