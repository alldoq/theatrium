defmodule AtriumWeb.DocumentControllerFileTest do
  use AtriumWeb.ConnCase, async: false
  alias Atrium.{Tenants, Accounts, Authorization, Documents}
  alias Atrium.Tenants.Provisioner

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "doc_file_ctrl", name: "Doc File Ctrl"})
    {:ok, tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop("doc_file_ctrl") end)

    prefix = Triplex.to_prefix("doc_file_ctrl")
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{email: "ctrl@example.com", name: "Ctrl"})
    {:ok, user} = Accounts.activate_user_with_password(prefix, user, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })

    Authorization.grant_section(prefix, "docs", {:user, user.id}, :edit)

    conn =
      build_conn()
      |> Map.put(:host, "doc_file_ctrl.atrium.example")
      |> post("/login", %{email: "ctrl@example.com", password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, "doc_file_ctrl.atrium.example")

    {:ok, conn: conn, prefix: prefix, user: user, tenant: tenant}
  end

  defp make_upload(filename, content, content_type \\ "application/pdf") do
    tmp = Path.join(System.tmp_dir!(), "upl_#{System.unique_integer([:positive])}_#{filename}")
    File.write!(tmp, content)
    on_exit(fn -> File.rm(tmp) end)
    %Plug.Upload{path: tmp, filename: filename, content_type: content_type}
  end

  describe "POST /sections/:section_key/documents (file kind)" do
    test "creates file document and redirects to show", %{conn: conn, prefix: prefix} do
      content = :crypto.strong_rand_bytes(256)
      upload = make_upload("doc.pdf", content)

      conn =
        post(conn, "/sections/docs/documents", %{
          "document" => %{
            "kind" => "file",
            "title" => "My File Doc",
            "file" => upload
          }
        })

      assert redirected_to(conn) =~ "/sections/docs/documents/"

      [doc | _] = Documents.list_documents(prefix, "docs")
      assert doc.kind == "file"
      assert doc.title == "My File Doc"

      df = Documents.get_current_file(prefix, doc)
      assert df.file_name == "doc.pdf"
      assert df.version == 1
    end
  end

  describe "GET /sections/:section_key/documents/:id/download" do
    test "returns 200 with plaintext body and attachment disposition", %{conn: conn, prefix: prefix, user: user} do
      content = :crypto.strong_rand_bytes(512)
      upload = make_upload("report.pdf", content)

      {:ok, doc} =
        Documents.create_file_document(prefix, user, "docs", %{title: "R"}, upload)

      conn = get(conn, "/sections/docs/documents/#{doc.id}/download")

      assert conn.status == 200
      assert response(conn, 200) == content
      [disp] = get_resp_header(conn, "content-disposition")
      assert disp =~ ~s(attachment; filename="report.pdf")
    end
  end

  describe "POST /sections/:section_key/documents/:id/replace" do
    test "advances current_version and keeps old file row", %{conn: conn, prefix: prefix, user: user} do
      u1 = make_upload("v1.pdf", :crypto.strong_rand_bytes(128))
      {:ok, doc} = Documents.create_file_document(prefix, user, "docs", %{title: "V"}, u1)
      assert doc.current_version == 1

      u2 = make_upload("v2.pdf", :crypto.strong_rand_bytes(128))

      conn =
        post(conn, "/sections/docs/documents/#{doc.id}/replace", %{"file" => u2})

      assert redirected_to(conn) =~ "/sections/docs/documents/#{doc.id}"

      reloaded = Documents.get_document!(prefix, doc.id)
      assert reloaded.current_version == 2

      df = Documents.get_current_file(prefix, reloaded)
      assert df.version == 2
      assert df.file_name == "v2.pdf"

      all =
        Atrium.Repo.all(
          Atrium.Documents.DocumentFile,
          prefix: prefix
        )

      assert Enum.count(all, &(&1.document_id == doc.id)) == 2
    end
  end
end
