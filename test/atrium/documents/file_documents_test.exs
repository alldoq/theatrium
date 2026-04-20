defmodule Atrium.Documents.FileDocumentsTest do
  use Atrium.TenantCase, async: false

  alias Atrium.Documents
  alias Atrium.Accounts.User
  alias Atrium.Repo

  @tmp Path.join(System.tmp_dir!(), "atrium_file_doc_test")

  setup do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  defp make_user(prefix) do
    Repo.insert!(
      %User{
        email: "u#{System.unique_integer([:positive])}@example.com",
        name: "Test User",
        status: "active",
        hashed_password: "bogus"
      },
      prefix: prefix
    )
  end

  defp make_upload(content, filename \\ "doc.pdf", ct \\ "application/pdf") do
    path = Path.join(@tmp, "upload_#{System.unique_integer([:positive])}.bin")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: ct}
  end

  test "create_file_document inserts doc + document_files and encrypts on disk",
       %{tenant_prefix: prefix} do
    user = make_user(prefix)
    content = String.duplicate("a", 10_000)
    upload = make_upload(content)

    attrs = %{title: "Policy.pdf", section_key: "hr"}

    {:ok, doc} = Documents.create_file_document(prefix, user, "hr", attrs, upload)

    assert doc.kind == "file"
    assert doc.status == "draft"
    assert doc.current_version == 1

    df = Documents.get_current_file(prefix, doc)
    assert df.version == 1
    assert df.file_name == "doc.pdf"
    assert df.mime_type == "application/pdf"
    assert df.byte_size == byte_size(content)

    abs = Atrium.Documents.Storage.absolute_from_relative(df.storage_path)
    assert File.exists?(abs)
    assert File.read!(abs) != content
  end

  test "rejects MIME outside the whitelist", %{tenant_prefix: prefix} do
    user = make_user(prefix)
    upload = make_upload("MZ binary", "virus.exe", "application/octet-stream")
    attrs = %{title: "x", section_key: "hr"}

    assert {:error, :invalid_mime} =
             Documents.create_file_document(prefix, user, "hr", attrs, upload)
  end

  test "rejects files over the size limit", %{tenant_prefix: prefix} do
    user = make_user(prefix)

    # Don't actually allocate 101 MB — write a tiny file then lie about its size via a stub approach?
    # Simpler: temporarily override the config for this one test.
    original = Application.get_env(:atrium, :document_file_max_bytes)
    Application.put_env(:atrium, :document_file_max_bytes, 100)

    try do
      upload = make_upload(String.duplicate("x", 200))
      attrs = %{title: "big", section_key: "hr"}

      assert {:error, :too_large} =
               Documents.create_file_document(prefix, user, "hr", attrs, upload)
    after
      Application.put_env(:atrium, :document_file_max_bytes, original)
    end
  end

  test "replace_file_document bumps version and keeps old blob",
       %{tenant_prefix: prefix} do
    user = make_user(prefix)
    {:ok, doc} =
      Documents.create_file_document(prefix, user, "hr", %{title: "t", section_key: "hr"}, make_upload("v1-content"))

    old_df = Documents.get_current_file(prefix, doc)
    old_abs = Atrium.Documents.Storage.absolute_from_relative(old_df.storage_path)
    assert File.exists?(old_abs)

    {:ok, updated} = Documents.replace_file_document(prefix, doc, user, make_upload("v2-content", "new.pdf"))
    assert updated.current_version == 2

    new_df = Documents.get_current_file(prefix, updated)
    assert new_df.version == 2
    assert new_df.file_name == "new.pdf"

    # Old blob retained
    assert File.exists?(old_abs)
  end

  test "decrypt_for_download round-trips plaintext", %{tenant_prefix: prefix} do
    user = make_user(prefix)
    content = :crypto.strong_rand_bytes(8_192)
    upload = make_upload(content)

    {:ok, doc} = Documents.create_file_document(prefix, user, "hr", %{title: "t", section_key: "hr"}, upload)

    {:ok, tmp_path, file_name, mime} = Documents.decrypt_for_download(prefix, doc)

    assert File.read!(tmp_path) == content
    assert file_name == "doc.pdf"
    assert mime == "application/pdf"

    File.rm!(tmp_path)
  end
end
