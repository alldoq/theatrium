defmodule Atrium.Documents.StorageTest do
  use ExUnit.Case, async: true
  alias Atrium.Documents.Storage

  test "uploads_root/0 returns the configured path" do
    assert Storage.uploads_root() == Application.fetch_env!(:atrium, :uploads_root)
  end

  test "tenant_files_dir/2 joins uploads_root, documents, tenant, files, doc_id" do
    root = Storage.uploads_root()
    doc_id = "abc-123"
    expected = Path.join([root, "documents", "tenant_x", "files", doc_id])
    assert Storage.tenant_files_dir("tenant_x", doc_id) == expected
  end

  test "version_file_path/3 produces v<N>.enc inside the document dir" do
    expected =
      Path.join([
        Storage.uploads_root(),
        "documents",
        "tenant_y",
        "files",
        "doc-1",
        "v2.enc"
      ])

    assert Storage.version_file_path("tenant_y", "doc-1", 2) == expected
  end

  test "relative_storage_path/3 omits the uploads root" do
    assert Storage.relative_storage_path("tenant_z", "doc-9", 3) ==
             Path.join(["documents", "tenant_z", "files", "doc-9", "v3.enc"])
  end

  test "absolute_from_relative/1 prepends uploads_root" do
    rel = "documents/tenant_z/files/doc-9/v3.enc"
    assert Storage.absolute_from_relative(rel) == Path.join(Storage.uploads_root(), rel)
  end
end
