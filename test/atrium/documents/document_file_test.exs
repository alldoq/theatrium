defmodule Atrium.Documents.DocumentFileTest do
  use Atrium.DataCase, async: true
  alias Atrium.Documents.DocumentFile

  test "changeset requires all encryption fields" do
    cs = DocumentFile.changeset(%DocumentFile{}, %{})
    refute cs.valid?

    for field <- [
          :document_id,
          :version,
          :file_name,
          :mime_type,
          :byte_size,
          :storage_path,
          :wrapped_key,
          :iv,
          :auth_tag,
          :checksum_sha256,
          :uploaded_by_id
        ] do
      assert errors_on(cs)[field], "expected #{field} to be required"
    end
  end

  test "changeset is valid with all fields" do
    attrs = %{
      document_id: Ecto.UUID.generate(),
      version: 1,
      file_name: "policy.pdf",
      mime_type: "application/pdf",
      byte_size: 1234,
      storage_path: "documents/tenant_x/files/abc/v1.enc",
      wrapped_key: :crypto.strong_rand_bytes(60),
      iv: :crypto.strong_rand_bytes(12),
      auth_tag: :crypto.strong_rand_bytes(16),
      checksum_sha256: String.duplicate("a", 64),
      uploaded_by_id: Ecto.UUID.generate()
    }

    cs = DocumentFile.changeset(%DocumentFile{}, attrs)
    assert cs.valid?
  end

  test "byte_size must be non-negative" do
    attrs = %{
      document_id: Ecto.UUID.generate(),
      version: 1,
      file_name: "a",
      mime_type: "text/plain",
      byte_size: -1,
      storage_path: "p",
      wrapped_key: <<>>,
      iv: <<>>,
      auth_tag: <<>>,
      checksum_sha256: "x",
      uploaded_by_id: Ecto.UUID.generate()
    }

    cs = DocumentFile.changeset(%DocumentFile{}, attrs)
    refute cs.valid?
    assert errors_on(cs)[:byte_size]
  end
end
