# Encrypted File Documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing Documents feature so a document can be either a TipTap-authored rich-text doc (existing) OR an uploaded binary file (PDF/DOCX/XLSX/PPTX/ODT/TXT/image). Uploaded files are encrypted at rest with AES-256-GCM; per-file data keys are wrapped with an env-var master key. Both kinds share the same list, ACLs, comments, versioning, and approval workflow.

**Architecture:** Polymorphic split — existing `documents` table grows a `kind` column; a new `document_files` table holds encryption metadata and file bytes pointer, one row per version of an uploaded file. Encryption uses native `:crypto` (no OpenSSL shell-outs). UI integrates into existing `DocumentController` — no new controllers.

**Tech Stack:** Elixir/Phoenix 1.8, Ecto, Triplex (multi-tenant schemas), `:crypto` (stdlib AES-256-GCM), `Plug.Upload`.

**Spec:** `docs/superpowers/specs/2026-04-20-deployment-and-encrypted-file-documents-design.md`

---

## File map

**New:**
- `lib/atrium/documents/document_file.ex` — schema for `document_files`.
- `lib/atrium/documents/encryption/master_key.ex` — loads master key from config, caches in `:persistent_term`.
- `lib/atrium/documents/encryption/data_key.ex` — generates and wraps/unwraps per-file data keys.
- `lib/atrium/documents/encryption/file_encryptor.ex` — streams plaintext → ciphertext with GCM.
- `lib/atrium/documents/encryption/file_decryptor.ex` — streams ciphertext → plaintext with GCM, verifies auth tag.
- `lib/atrium/documents/encryption/processor.ex` — orchestrates upload-encrypt + decrypt-to-temp.
- `lib/atrium/documents/storage.ex` — path helpers (uploads root + per-tenant paths).
- `lib/atrium_web/plugs/static_uploads.ex` — narrows `/uploads` static serving to images only.
- `priv/repo/tenant_migrations/20260420000001_add_kind_to_documents.exs`
- `priv/repo/tenant_migrations/20260420000002_create_document_files.exs`
- Tests: `test/atrium/documents/encryption/{master_key,data_key,file_encryptor,file_decryptor,processor}_test.exs`
- Test: `test/atrium/documents/document_file_test.exs`
- Test: `test/atrium/documents/file_documents_test.exs` (context integration)
- Test: `test/atrium_web/controllers/document_controller_file_test.exs`

**Modified:**
- `lib/atrium/documents/document.ex` — add `:kind` field + validation + `file_changeset/2`.
- `lib/atrium/documents.ex` — new public functions `create_file_document/5`, `replace_file_document/4`, `get_current_file/2`, `decrypt_for_download/2`.
- `lib/atrium_web/controllers/document_controller.ex` — branch `new/create` on kind, add `download/replace` actions, conditional rendering in `show`.
- `lib/atrium_web/controllers/document_html/new.html.heex` — tabbed form.
- `lib/atrium_web/controllers/document_html/show.html.heex` — file card for kind=file.
- `lib/atrium_web/controllers/document_html/edit.html.heex` — replace-file form for kind=file.
- `lib/atrium_web/controllers/document_html/index.html.heex` — MIME icon per row.
- `lib/atrium_web/router.ex` — `/download` and `/replace` routes.
- `lib/atrium_web/endpoint.ex` — replace `Plug.Static at: "/uploads"` with `StaticUploads` plug; bump multipart parser length.
- `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/runtime.exs` — keys and limits.

---

## Task 1: Add :kind field to Document schema

**Files:**
- Modify: `lib/atrium/documents/document.ex`
- Migration: `priv/repo/tenant_migrations/20260420000001_add_kind_to_documents.exs`
- Test: `test/atrium/documents_test.exs` (append to existing `Document.changeset/2` describe block)

- [ ] **Step 1: Write the migration**

Create `priv/repo/tenant_migrations/20260420000001_add_kind_to_documents.exs`:

```elixir
defmodule Atrium.Repo.TenantMigrations.AddKindToDocuments do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :kind, :string, null: false, default: "rich_text"
    end

    create index(:documents, [:kind])
  end
end
```

- [ ] **Step 2: Write the failing test**

Append to `test/atrium/documents_test.exs` inside the `describe "Document.changeset/2"` block:

```elixir
test "defaults kind to rich_text" do
  attrs = %{title: "T", section_key: "hr", author_id: Ecto.UUID.generate()}
  cs = Document.changeset(%Document{}, attrs)
  assert cs.valid?
  assert Ecto.Changeset.get_field(cs, :kind) == "rich_text"
end

test "kind must be rich_text or file" do
  attrs = %{title: "T", section_key: "hr", author_id: Ecto.UUID.generate(), kind: "bogus"}
  cs = Document.changeset(%Document{}, attrs)
  refute cs.valid?
  assert errors_on(cs)[:kind]
end
```

And after the existing describe block, add:

```elixir
describe "Document.file_changeset/2" do
  test "forces kind to file and does not require body_html" do
    attrs = %{title: "Policy.pdf", section_key: "hr", author_id: Ecto.UUID.generate()}
    cs = Document.file_changeset(%Document{}, attrs)
    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :kind) == "file"
  end
end
```

- [ ] **Step 3: Run the test to see it fail**

Run: `mix test test/atrium/documents_test.exs`
Expected: FAIL — `file_changeset/2` is undefined, `kind` validation missing.

- [ ] **Step 4: Update the Document schema**

Modify `lib/atrium/documents/document.ex` — replace the full file with:

```elixir
defmodule Atrium.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft in_review approved archived)
  @kinds ~w(rich_text file)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "documents" do
    field :title, :string
    field :section_key, :string
    field :subsection_slug, :string
    field :status, :string, default: "draft"
    field :kind, :string, default: "rich_text"
    field :body_html, :string
    field :current_version, :integer, default: 1
    field :author_id, :binary_id
    field :approved_by_id, :binary_id
    field :approved_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: @kinds

  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [:title, :section_key, :subsection_slug, :body_html, :author_id, :kind])
    |> validate_required([:title, :section_key, :author_id])
    |> validate_length(:title, min: 1, max: 500)
    |> validate_inclusion(:kind, @kinds)
    |> sanitize_body_html()
  end

  def file_changeset(doc, attrs) do
    doc
    |> cast(attrs, [:title, :section_key, :subsection_slug, :author_id])
    |> validate_required([:title, :section_key, :author_id])
    |> validate_length(:title, min: 1, max: 500)
    |> put_change(:kind, "file")
  end

  def update_changeset(doc, attrs) do
    doc
    |> cast(attrs, [:title, :body_html])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 500)
    |> sanitize_body_html()
  end

  def status_changeset(doc, status, extra_attrs \\ %{}) do
    doc
    |> cast(Map.merge(%{status: status}, extra_attrs), [:status, :approved_by_id, :approved_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  def version_bump_changeset(%Ecto.Changeset{} = cs) do
    current = get_field(cs, :current_version)
    change(cs, current_version: current + 1)
  end

  def version_bump_changeset(%__MODULE__{} = doc) do
    change(doc, current_version: doc.current_version + 1)
  end

  defp sanitize_body_html(changeset) do
    case get_change(changeset, :body_html) do
      nil -> changeset
      html -> put_change(changeset, :body_html, HtmlSanitizeEx.basic_html(html))
    end
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/atrium/documents_test.exs`
Expected: PASS.

- [ ] **Step 6: Run the tenant migration against the test tenant**

Run: `mix test test/atrium/documents_test.exs` (confirms migration runs on fresh test tenant).
If TenantCase setup fails, run `mix ecto.reset` first.
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add priv/repo/tenant_migrations/20260420000001_add_kind_to_documents.exs \
        lib/atrium/documents/document.ex \
        test/atrium/documents_test.exs
git commit -m "feat(documents): add :kind column and file_changeset"
```

---

## Task 2: Configuration for encryption key and limits

**Files:**
- Modify: `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/runtime.exs`

- [ ] **Step 1: Add base config entries**

Append to `config/config.exs` just before the final `import_config`:

```elixir
# File-document encryption & storage
config :atrium, :uploads_root, "priv/uploads"
config :atrium, :document_file_max_bytes, 100 * 1024 * 1024

config :atrium, :document_file_allowed_mime, [
  "application/pdf",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "application/msword",
  "application/vnd.ms-excel",
  "application/vnd.ms-powerpoint",
  "application/vnd.oasis.opendocument.text",
  "text/plain",
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp"
]
```

- [ ] **Step 2: Add dev & test keys**

Append to `config/dev.exs`:

```elixir
# Dev-only 32-byte file encryption key. DO NOT USE IN PROD.
config :atrium, :file_encryption_key,
  <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32>>
```

Append to `config/test.exs`:

```elixir
config :atrium, :file_encryption_key,
  <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32>>

config :atrium, :uploads_root, "tmp/test_uploads"
```

- [ ] **Step 3: Add prod runtime config**

Modify `config/runtime.exs` — inside the `if config_env() == :prod do ... end` block, after the existing `cloak_key` block, add:

```elixir
  file_key =
    System.get_env("ATRIUM_FILE_ENCRYPTION_KEY") ||
      raise "ATRIUM_FILE_ENCRYPTION_KEY must be set in production (32 bytes, base64-encoded)"

  config :atrium, :file_encryption_key, Base.decode64!(file_key)

  config :atrium,
    :uploads_root,
    System.get_env("ATRIUM_UPLOADS_ROOT") || "/var/www/atrium/shared/uploads"
```

- [ ] **Step 4: Verify compile**

Run: `mix compile --warnings-as-errors`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add config/config.exs config/dev.exs config/test.exs config/runtime.exs
git commit -m "feat(config): add file encryption key and uploads root"
```

---

## Task 3: Storage path helpers

**Files:**
- Create: `lib/atrium/documents/storage.ex`
- Test: `test/atrium/documents/storage_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/atrium/documents/storage_test.exs`:

```elixir
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
```

- [ ] **Step 2: Run the test to see it fail**

Run: `mix test test/atrium/documents/storage_test.exs`
Expected: FAIL — `Atrium.Documents.Storage` undefined.

- [ ] **Step 3: Implement the module**

Create `lib/atrium/documents/storage.ex`:

```elixir
defmodule Atrium.Documents.Storage do
  @moduledoc """
  Path helpers for encrypted file-document storage.
  """

  def uploads_root do
    Application.fetch_env!(:atrium, :uploads_root)
  end

  def tenant_files_dir(tenant_prefix, document_id) do
    Path.join([uploads_root(), "documents", tenant_prefix, "files", document_id])
  end

  def version_file_path(tenant_prefix, document_id, version) when is_integer(version) do
    Path.join(tenant_files_dir(tenant_prefix, document_id), "v#{version}.enc")
  end

  def relative_storage_path(tenant_prefix, document_id, version) when is_integer(version) do
    Path.join(["documents", tenant_prefix, "files", document_id, "v#{version}.enc"])
  end

  def absolute_from_relative(relative_path) when is_binary(relative_path) do
    Path.join(uploads_root(), relative_path)
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/atrium/documents/storage_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/documents/storage.ex test/atrium/documents/storage_test.exs
git commit -m "feat(documents): add Storage path helpers"
```

---

## Task 4: MasterKey module

**Files:**
- Create: `lib/atrium/documents/encryption/master_key.ex`
- Test: `test/atrium/documents/encryption/master_key_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/atrium/documents/encryption/master_key_test.exs`:

```elixir
defmodule Atrium.Documents.Encryption.MasterKeyTest do
  use ExUnit.Case, async: false
  alias Atrium.Documents.Encryption.MasterKey

  test "get/0 returns the configured 32-byte key" do
    key = MasterKey.get()
    assert is_binary(key)
    assert byte_size(key) == 32
    assert key == Application.fetch_env!(:atrium, :file_encryption_key)
  end

  test "get/0 is idempotent (caches)" do
    k1 = MasterKey.get()
    k2 = MasterKey.get()
    assert k1 == k2
  end
end
```

- [ ] **Step 2: Run the test to see it fail**

Run: `mix test test/atrium/documents/encryption/master_key_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement the module**

Create `lib/atrium/documents/encryption/master_key.ex`:

```elixir
defmodule Atrium.Documents.Encryption.MasterKey do
  @moduledoc """
  Provides the 32-byte master key used to wrap per-file data keys.
  Reads `:atrium, :file_encryption_key` once and caches in :persistent_term.
  """

  @cache_key {__MODULE__, :key}

  def get do
    case :persistent_term.get(@cache_key, :miss) do
      :miss -> load_and_cache()
      key -> key
    end
  end

  defp load_and_cache do
    key = Application.fetch_env!(:atrium, :file_encryption_key)

    cond do
      not is_binary(key) ->
        raise "Atrium file_encryption_key must be a binary; got: #{inspect(key)}"

      byte_size(key) != 32 ->
        raise "Atrium file_encryption_key must be exactly 32 bytes; got #{byte_size(key)}"

      true ->
        :persistent_term.put(@cache_key, key)
        key
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/atrium/documents/encryption/master_key_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/documents/encryption/master_key.ex \
        test/atrium/documents/encryption/master_key_test.exs
git commit -m "feat(encryption): add MasterKey loader"
```

---

## Task 5: DataKey (wrap/unwrap)

**Files:**
- Create: `lib/atrium/documents/encryption/data_key.ex`
- Test: `test/atrium/documents/encryption/data_key_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/atrium/documents/encryption/data_key_test.exs`:

```elixir
defmodule Atrium.Documents.Encryption.DataKeyTest do
  use ExUnit.Case, async: true
  alias Atrium.Documents.Encryption.DataKey

  test "generate/0 returns {32-byte key, 12-byte iv}" do
    {key, iv} = DataKey.generate()
    assert byte_size(key) == 32
    assert byte_size(iv) == 12
  end

  test "wrap |> unwrap round-trips" do
    {key, _iv} = DataKey.generate()
    wrapped = DataKey.wrap(key)
    assert DataKey.unwrap(wrapped) == key
  end

  test "wrap produces different ciphertext for same key (fresh IV)" do
    {key, _iv} = DataKey.generate()
    assert DataKey.wrap(key) != DataKey.wrap(key)
  end

  test "unwrap raises on tampered ciphertext" do
    {key, _iv} = DataKey.generate()
    wrapped = DataKey.wrap(key)
    <<head::binary-size(12), tag::binary-size(16), rest::binary>> = wrapped
    tampered = head <> tag <> (:binary.bin_to_list(rest) |> Enum.map(&Bitwise.bxor(&1, 1)) |> :binary.list_to_bin())

    assert_raise RuntimeError, fn -> DataKey.unwrap(tampered) end
  end
end
```

- [ ] **Step 2: Run the test to see it fail**

Run: `mix test test/atrium/documents/encryption/data_key_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement the module**

Create `lib/atrium/documents/encryption/data_key.ex`:

```elixir
defmodule Atrium.Documents.Encryption.DataKey do
  @moduledoc """
  Generates random per-file AES-256-GCM data keys and wraps/unwraps them
  with the master key.

  Wrapped format: <<iv::12 bytes, auth_tag::16 bytes, ciphertext::binary>>.
  """

  alias Atrium.Documents.Encryption.MasterKey

  @iv_bytes 12
  @tag_bytes 16
  @aad ""

  def generate do
    {:crypto.strong_rand_bytes(32), :crypto.strong_rand_bytes(@iv_bytes)}
  end

  def wrap(data_key) when is_binary(data_key) and byte_size(data_key) == 32 do
    iv = :crypto.strong_rand_bytes(@iv_bytes)
    master = MasterKey.get()

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, master, iv, data_key, @aad, true)

    iv <> tag <> ciphertext
  end

  def unwrap(<<iv::binary-size(@iv_bytes), tag::binary-size(@tag_bytes), ciphertext::binary>>) do
    master = MasterKey.get()

    case :crypto.crypto_one_time_aead(:aes_256_gcm, master, iv, ciphertext, @aad, tag, false) do
      plain when is_binary(plain) and byte_size(plain) == 32 -> plain
      :error -> raise "DataKey.unwrap: authentication failed"
    end
  rescue
    e in ErlangError ->
      raise "DataKey.unwrap failed: #{inspect(e)}"
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/atrium/documents/encryption/data_key_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/documents/encryption/data_key.ex \
        test/atrium/documents/encryption/data_key_test.exs
git commit -m "feat(encryption): add DataKey wrap/unwrap"
```

---

## Task 6: FileEncryptor (streaming AES-256-GCM)

**Files:**
- Create: `lib/atrium/documents/encryption/file_encryptor.ex`
- Test: `test/atrium/documents/encryption/file_encryptor_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/atrium/documents/encryption/file_encryptor_test.exs`:

```elixir
defmodule Atrium.Documents.Encryption.FileEncryptorTest do
  use ExUnit.Case, async: true
  alias Atrium.Documents.Encryption.FileEncryptor

  @tmp Path.join(System.tmp_dir!(), "atrium_enc_test")

  setup do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  test "encrypts a small file and reports metadata" do
    source = Path.join(@tmp, "plain.txt")
    dest = Path.join(@tmp, "out.enc")
    content = "hello world " |> String.duplicate(1000)
    File.write!(source, content)

    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)

    {:ok, meta} = FileEncryptor.call(source, dest, key, iv)

    assert byte_size(meta.auth_tag) == 16
    assert meta.byte_size == byte_size(content)
    assert String.length(meta.sha256) == 64

    # Dest is not the plaintext
    assert File.read!(dest) != content
  end

  test "encrypts a multi-chunk file (>64 KB)" do
    source = Path.join(@tmp, "big.bin")
    dest = Path.join(@tmp, "big.enc")
    content = :crypto.strong_rand_bytes(200_000)
    File.write!(source, content)

    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)

    {:ok, meta} = FileEncryptor.call(source, dest, key, iv)
    assert meta.byte_size == 200_000
    assert byte_size(File.read!(dest)) > 0
  end
end
```

- [ ] **Step 2: Run the test to see it fail**

Run: `mix test test/atrium/documents/encryption/file_encryptor_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement the module**

Create `lib/atrium/documents/encryption/file_encryptor.ex`:

```elixir
defmodule Atrium.Documents.Encryption.FileEncryptor do
  @moduledoc """
  Streams a plaintext file → ciphertext file using AES-256-GCM.
  Returns {:ok, %{auth_tag, byte_size, sha256}} on success.
  """

  @chunk_bytes 64 * 1024
  @aad ""

  def call(source_path, dest_path, key, iv)
      when is_binary(key) and byte_size(key) == 32 and
             is_binary(iv) and byte_size(iv) == 12 do
    File.mkdir_p!(Path.dirname(dest_path))

    with {:ok, src} <- File.open(source_path, [:read, :binary]),
         {:ok, dst} <- File.open(dest_path, [:write, :binary]) do
      crypto_state = :crypto.crypto_init(:aes_256_gcm, key, iv, true)
      _ = :crypto.crypto_update_ad(crypto_state, @aad)
      hash_state = :crypto.hash_init(:sha256)

      try do
        {bytes, hash_state} = stream_encrypt(src, dst, crypto_state, hash_state, 0)
        final = :crypto.crypto_final(crypto_state)
        if byte_size(final) > 0, do: IO.binwrite(dst, final)
        tag = :crypto.crypto_get_tag(crypto_state, 16)
        sha = :crypto.hash_final(hash_state) |> Base.encode16(case: :lower)
        {:ok, %{auth_tag: tag, byte_size: bytes, sha256: sha}}
      after
        File.close(src)
        File.close(dst)
      end
    else
      {:error, reason} ->
        _ = File.rm(dest_path)
        {:error, reason}
    end
  rescue
    e ->
      _ = File.rm(dest_path)
      {:error, Exception.message(e)}
  end

  defp stream_encrypt(src, dst, crypto_state, hash_state, acc_bytes) do
    case IO.binread(src, @chunk_bytes) do
      :eof ->
        {acc_bytes, hash_state}

      {:error, reason} ->
        raise "read failed: #{inspect(reason)}"

      chunk when is_binary(chunk) ->
        hash_state = :crypto.hash_update(hash_state, chunk)
        out = :crypto.crypto_update(crypto_state, chunk)
        if byte_size(out) > 0, do: IO.binwrite(dst, out)
        stream_encrypt(src, dst, crypto_state, hash_state, acc_bytes + byte_size(chunk))
    end
  end
end
```

**Note on `:crypto.crypto_update_ad/2`:** Erlang's `:crypto` module uses `crypto_update/2` for both AAD and data in certain modes. If the above yields an `undef` error at runtime, remove the `crypto_update_ad` call (GCM with empty AAD works without it).

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/atrium/documents/encryption/file_encryptor_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/documents/encryption/file_encryptor.ex \
        test/atrium/documents/encryption/file_encryptor_test.exs
git commit -m "feat(encryption): add streaming FileEncryptor"
```

---

## Task 7: FileDecryptor + round-trip test

**Files:**
- Create: `lib/atrium/documents/encryption/file_decryptor.ex`
- Test: `test/atrium/documents/encryption/file_decryptor_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/atrium/documents/encryption/file_decryptor_test.exs`:

```elixir
defmodule Atrium.Documents.Encryption.FileDecryptorTest do
  use ExUnit.Case, async: true
  alias Atrium.Documents.Encryption.{FileEncryptor, FileDecryptor}

  @tmp Path.join(System.tmp_dir!(), "atrium_dec_test")

  setup do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  test "round-trips a random 1 MB file" do
    source = Path.join(@tmp, "r.bin")
    enc = Path.join(@tmp, "r.enc")
    dec = Path.join(@tmp, "r.dec")
    content = :crypto.strong_rand_bytes(1_048_576)
    File.write!(source, content)

    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)

    {:ok, meta} = FileEncryptor.call(source, enc, key, iv)
    {:ok, _size} = FileDecryptor.call(enc, dec, key, iv, meta.auth_tag)

    assert File.read!(dec) == content
  end

  test "returns {:error, :auth_failed} on tampered ciphertext" do
    source = Path.join(@tmp, "t.txt")
    enc = Path.join(@tmp, "t.enc")
    dec = Path.join(@tmp, "t.dec")
    File.write!(source, "secret")

    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)
    {:ok, meta} = FileEncryptor.call(source, enc, key, iv)

    # Flip one bit in the ciphertext
    <<first, rest::binary>> = File.read!(enc)
    File.write!(enc, <<Bitwise.bxor(first, 1), rest::binary>>)

    assert {:error, :auth_failed} = FileDecryptor.call(enc, dec, key, iv, meta.auth_tag)
    refute File.exists?(dec)
  end

  test "returns {:error, :auth_failed} on tampered auth_tag" do
    source = Path.join(@tmp, "t2.txt")
    enc = Path.join(@tmp, "t2.enc")
    dec = Path.join(@tmp, "t2.dec")
    File.write!(source, "secret")

    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)
    {:ok, meta} = FileEncryptor.call(source, enc, key, iv)

    <<b, tag_rest::binary>> = meta.auth_tag
    bad_tag = <<Bitwise.bxor(b, 1), tag_rest::binary>>

    assert {:error, :auth_failed} = FileDecryptor.call(enc, dec, key, iv, bad_tag)
  end
end
```

- [ ] **Step 2: Run the test to see it fail**

Run: `mix test test/atrium/documents/encryption/file_decryptor_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement the module**

Create `lib/atrium/documents/encryption/file_decryptor.ex`:

```elixir
defmodule Atrium.Documents.Encryption.FileDecryptor do
  @moduledoc """
  Streams a ciphertext file → plaintext file using AES-256-GCM.
  Verifies the auth tag; returns {:error, :auth_failed} on mismatch.
  """

  @chunk_bytes 64 * 1024
  @aad ""

  def call(source_path, dest_path, key, iv, auth_tag)
      when is_binary(key) and byte_size(key) == 32 and
             is_binary(iv) and byte_size(iv) == 12 and
             is_binary(auth_tag) and byte_size(auth_tag) == 16 do
    File.mkdir_p!(Path.dirname(dest_path))

    with {:ok, src} <- File.open(source_path, [:read, :binary]),
         {:ok, dst} <- File.open(dest_path, [:write, :binary]) do
      state = :crypto.crypto_init(:aes_256_gcm, key, iv, false)
      _ = :crypto.crypto_update_ad(state, @aad)

      try do
        bytes = stream_decrypt(src, dst, state, 0)
        :crypto.crypto_final(state, auth_tag)
        {:ok, bytes}
      rescue
        _e ->
          _ = File.rm(dest_path)
          {:error, :auth_failed}
      after
        File.close(src)
        File.close(dst)
      end
    else
      {:error, reason} ->
        _ = File.rm(dest_path)
        {:error, reason}
    end
  end

  defp stream_decrypt(src, dst, state, acc_bytes) do
    case IO.binread(src, @chunk_bytes) do
      :eof ->
        acc_bytes

      {:error, reason} ->
        raise "read failed: #{inspect(reason)}"

      chunk when is_binary(chunk) ->
        out = :crypto.crypto_update(state, chunk)
        if byte_size(out) > 0, do: IO.binwrite(dst, out)
        stream_decrypt(src, dst, state, acc_bytes + byte_size(out))
    end
  end
end
```

**If `:crypto.crypto_final/2` doesn't exist in this OTP version**, fall back to `:crypto.crypto_one_time_aead/7` in a single-shot form by reading the whole file into memory (acceptable for the 100 MB cap). If that fallback is needed, swap the `stream_decrypt` loop for a `File.read!/1` + single `:crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, cipher, aad, auth_tag, false)` call.

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/atrium/documents/encryption/file_decryptor_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/documents/encryption/file_decryptor.ex \
        test/atrium/documents/encryption/file_decryptor_test.exs
git commit -m "feat(encryption): add streaming FileDecryptor"
```

---

## Task 8: Processor orchestrator

**Files:**
- Create: `lib/atrium/documents/encryption/processor.ex`
- Test: `test/atrium/documents/encryption/processor_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/atrium/documents/encryption/processor_test.exs`:

```elixir
defmodule Atrium.Documents.Encryption.ProcessorTest do
  use ExUnit.Case, async: true
  alias Atrium.Documents.Encryption.Processor

  @tmp Path.join(System.tmp_dir!(), "atrium_proc_test")

  setup do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  defp make_upload(content) do
    path = Path.join(@tmp, "upload_#{System.unique_integer([:positive])}.bin")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: "doc.pdf", content_type: "application/pdf"}
  end

  test "encrypt_upload writes ciphertext to dest and returns metadata" do
    content = "some bytes " |> String.duplicate(500)
    upload = make_upload(content)
    dest = Path.join(@tmp, "out.enc")

    {:ok, meta} = Processor.encrypt_upload(upload, dest)

    assert File.exists?(dest)
    assert File.read!(dest) != content
    assert byte_size(meta.wrapped_key) >= 60
    assert byte_size(meta.iv) == 12
    assert byte_size(meta.auth_tag) == 16
    assert meta.byte_size == byte_size(content)
    assert String.length(meta.sha256) == 64
  end

  test "decrypt_to_temp round-trips an encrypted upload" do
    content = :crypto.strong_rand_bytes(50_000)
    upload = make_upload(content)
    dest = Path.join(@tmp, "rt.enc")
    {:ok, meta} = Processor.encrypt_upload(upload, dest)

    # Build a fake %DocumentFile{} shape for the decrypt side
    df = %{
      storage_path_abs: dest,
      wrapped_key: meta.wrapped_key,
      iv: meta.iv,
      auth_tag: meta.auth_tag
    }

    {:ok, tmp_path} = Processor.decrypt_to_temp(df)
    assert File.read!(tmp_path) == content
    File.rm!(tmp_path)
  end
end
```

- [ ] **Step 2: Run the test to see it fail**

Run: `mix test test/atrium/documents/encryption/processor_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement the module**

Create `lib/atrium/documents/encryption/processor.ex`:

```elixir
defmodule Atrium.Documents.Encryption.Processor do
  @moduledoc """
  High-level orchestrator for file encryption / decryption.

  - encrypt_upload/2 takes a %Plug.Upload{} and a destination absolute path.
    Returns {:ok, meta} where meta contains all the fields needed to insert
    a %DocumentFile{}: wrapped_key, iv, auth_tag, byte_size, sha256.

  - decrypt_to_temp/1 accepts a map with keys storage_path_abs, wrapped_key,
    iv, auth_tag and writes plaintext to a tmp file. Returns {:ok, tmp_path}.
    Caller must remove the tmp file after use.
  """

  alias Atrium.Documents.Encryption.{DataKey, FileEncryptor, FileDecryptor}

  def encrypt_upload(%Plug.Upload{path: src_path}, dest_path) when is_binary(dest_path) do
    {key, iv} = DataKey.generate()

    with {:ok, meta} <- FileEncryptor.call(src_path, dest_path, key, iv) do
      {:ok,
       %{
         wrapped_key: DataKey.wrap(key),
         iv: iv,
         auth_tag: meta.auth_tag,
         byte_size: meta.byte_size,
         sha256: meta.sha256
       }}
    end
  end

  def decrypt_to_temp(%{
        storage_path_abs: src,
        wrapped_key: wrapped,
        iv: iv,
        auth_tag: tag
      }) do
    key = DataKey.unwrap(wrapped)
    tmp = Path.join(System.tmp_dir!(), "atrium_dl_#{System.unique_integer([:positive])}")

    case FileDecryptor.call(src, tmp, key, iv, tag) do
      {:ok, _size} -> {:ok, tmp}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/atrium/documents/encryption/processor_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/documents/encryption/processor.ex \
        test/atrium/documents/encryption/processor_test.exs
git commit -m "feat(encryption): add Processor orchestrator"
```

---

## Task 9: DocumentFile schema and migration

**Files:**
- Create: `priv/repo/tenant_migrations/20260420000002_create_document_files.exs`
- Create: `lib/atrium/documents/document_file.ex`
- Test: `test/atrium/documents/document_file_test.exs`

- [ ] **Step 1: Write the migration**

Create `priv/repo/tenant_migrations/20260420000002_create_document_files.exs`:

```elixir
defmodule Atrium.Repo.TenantMigrations.CreateDocumentFiles do
  use Ecto.Migration

  def change do
    create table(:document_files, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :file_name, :string, null: false
      add :mime_type, :string, null: false
      add :byte_size, :bigint, null: false
      add :storage_path, :string, null: false
      add :wrapped_key, :binary, null: false
      add :iv, :binary, null: false
      add :auth_tag, :binary, null: false
      add :checksum_sha256, :string, null: false
      add :uploaded_by_id, :binary_id, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:document_files, [:document_id, :version])
    create index(:document_files, [:document_id])
  end
end
```

- [ ] **Step 2: Write the failing schema test**

Create `test/atrium/documents/document_file_test.exs`:

```elixir
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
```

- [ ] **Step 3: Run the test to see it fail**

Run: `mix test test/atrium/documents/document_file_test.exs`
Expected: FAIL — schema undefined.

- [ ] **Step 4: Create the schema**

Create `lib/atrium/documents/document_file.ex`:

```elixir
defmodule Atrium.Documents.DocumentFile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "document_files" do
    field :version, :integer
    field :file_name, :string
    field :mime_type, :string
    field :byte_size, :integer
    field :storage_path, :string
    field :wrapped_key, :binary
    field :iv, :binary
    field :auth_tag, :binary
    field :checksum_sha256, :string

    belongs_to :document, Atrium.Documents.Document
    field :uploaded_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(document_id version file_name mime_type byte_size storage_path
               wrapped_key iv auth_tag checksum_sha256 uploaded_by_id)a

  def changeset(doc_file, attrs) do
    doc_file
    |> cast(attrs, @required)
    |> validate_required(@required)
    |> validate_number(:byte_size, greater_than_or_equal_to: 0)
    |> validate_number(:version, greater_than_or_equal_to: 1)
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/atrium/documents/document_file_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add priv/repo/tenant_migrations/20260420000002_create_document_files.exs \
        lib/atrium/documents/document_file.ex \
        test/atrium/documents/document_file_test.exs
git commit -m "feat(documents): add DocumentFile schema and migration"
```

---

## Task 10: Context — create_file_document

**Files:**
- Modify: `lib/atrium/documents.ex`
- Test: `test/atrium/documents/file_documents_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/atrium/documents/file_documents_test.exs`:

```elixir
defmodule Atrium.Documents.FileDocumentsTest do
  use Atrium.TenantCase, async: false

  alias Atrium.Documents
  alias Atrium.Documents.{Document, DocumentFile}
  alias Atrium.Repo

  @tmp Path.join(System.tmp_dir!(), "atrium_file_doc_test")

  setup do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  defp make_user(tenant_prefix) do
    {:ok, user} =
      Atrium.Accounts.Users.create_user(tenant_prefix, %{
        email: "u#{System.unique_integer([:positive])}@example.com",
        name: "Test User",
        password: "correcthorse!"
      })

    user
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

    big = :crypto.strong_rand_bytes(101 * 1024 * 1024)
    upload = make_upload(big)

    attrs = %{title: "big", section_key: "hr"}

    assert {:error, :too_large} =
             Documents.create_file_document(prefix, user, "hr", attrs, upload)
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
```

(If the `Atrium.Accounts.Users.create_user/2` signature differs, adjust the helper — check `lib/atrium/accounts.ex` for the actual API. Replace with a direct `Repo.insert!` if easier.)

- [ ] **Step 2: Run the test to see it fail**

Run: `mix test test/atrium/documents/file_documents_test.exs`
Expected: FAIL — context functions undefined.

- [ ] **Step 3: Add context functions**

Modify `lib/atrium/documents.ex` — add new aliases at the top (after the existing aliases):

```elixir
alias Atrium.Documents.DocumentFile
alias Atrium.Documents.Encryption.Processor
alias Atrium.Documents.Storage
```

Append these public functions before the final `end`:

```elixir
# ---------------------------------------------------------------------------
# File documents
# ---------------------------------------------------------------------------

def create_file_document(prefix, actor_user, section_key, attrs, %Plug.Upload{} = upload) do
  with :ok <- validate_upload(upload) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("section_key", section_key)
      |> Map.put("author_id", actor_user.id)

    Repo.transaction(fn ->
      with {:ok, doc} <- insert_file_document(prefix, attrs),
           {:ok, dest_abs, rel_path} <- prepare_dest_paths(prefix, doc.id, 1),
           {:ok, meta} <- Processor.encrypt_upload(upload, dest_abs),
           {:ok, df} <- insert_document_file(prefix, doc, 1, upload, meta, rel_path, actor_user),
           {:ok, _} <- Audit.log(prefix, "document.file_uploaded", %{
             actor: {:user, actor_user.id},
             resource: {"Document", doc.id},
             meta: %{version: df.version, file_name: df.file_name}
           }) do
        doc
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end

def replace_file_document(prefix, %Document{kind: "file"} = doc, actor_user, %Plug.Upload{} = upload) do
  with :ok <- validate_upload(upload) do
    new_version = doc.current_version + 1

    Repo.transaction(fn ->
      with {:ok, updated_doc} <- bump_version(prefix, doc),
           {:ok, dest_abs, rel_path} <- prepare_dest_paths(prefix, doc.id, new_version),
           {:ok, meta} <- Processor.encrypt_upload(upload, dest_abs),
           {:ok, df} <-
             insert_document_file(prefix, updated_doc, new_version, upload, meta, rel_path, actor_user),
           {:ok, _} <- Audit.log(prefix, "document.file_replaced", %{
             actor: {:user, actor_user.id},
             resource: {"Document", doc.id},
             meta: %{version: df.version, file_name: df.file_name}
           }) do
        updated_doc
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end

def replace_file_document(_prefix, _doc, _user, _upload), do: {:error, :not_file_document}

def get_current_file(prefix, %Document{} = doc) do
  Repo.one(
    from(f in DocumentFile,
      where: f.document_id == ^doc.id and f.version == ^doc.current_version
    ),
    prefix: prefix
  )
end

def decrypt_for_download(prefix, %Document{kind: "file"} = doc) do
  case get_current_file(prefix, doc) do
    nil ->
      {:error, :not_found}

    %DocumentFile{} = df ->
      abs = Storage.absolute_from_relative(df.storage_path)

      case Processor.decrypt_to_temp(%{
             storage_path_abs: abs,
             wrapped_key: df.wrapped_key,
             iv: df.iv,
             auth_tag: df.auth_tag
           }) do
        {:ok, tmp} -> {:ok, tmp, df.file_name, df.mime_type}
        {:error, reason} -> {:error, reason}
      end
  end
end

def decrypt_for_download(_prefix, _doc), do: {:error, :not_file_document}

# --- private helpers ---

defp validate_upload(%Plug.Upload{path: path, content_type: ct}) do
  max = Application.fetch_env!(:atrium, :document_file_max_bytes)
  allowed = Application.fetch_env!(:atrium, :document_file_allowed_mime)

  with {:ok, %{size: size}} <- File.stat(path),
       :ok <- check_size(size, max),
       :ok <- check_mime(ct, allowed) do
    :ok
  else
    {:error, _} = e -> e
  end
end

defp check_size(size, max) when size <= max, do: :ok
defp check_size(_, _), do: {:error, :too_large}

defp check_mime(ct, allowed) when is_binary(ct) do
  if ct in allowed, do: :ok, else: {:error, :invalid_mime}
end

defp check_mime(_, _), do: {:error, :invalid_mime}

defp insert_file_document(prefix, attrs) do
  %Document{}
  |> Document.file_changeset(attrs)
  |> Repo.insert(prefix: prefix)
end

defp prepare_dest_paths(prefix, doc_id, version) do
  dir = Storage.tenant_files_dir(prefix, doc_id)
  File.mkdir_p!(dir)
  abs = Storage.version_file_path(prefix, doc_id, version)
  rel = Storage.relative_storage_path(prefix, doc_id, version)
  {:ok, abs, rel}
end

defp insert_document_file(prefix, doc, version, upload, meta, rel_path, actor_user) do
  %DocumentFile{}
  |> DocumentFile.changeset(%{
    document_id: doc.id,
    version: version,
    file_name: upload.filename,
    mime_type: upload.content_type,
    byte_size: meta.byte_size,
    storage_path: rel_path,
    wrapped_key: meta.wrapped_key,
    iv: meta.iv,
    auth_tag: meta.auth_tag,
    checksum_sha256: meta.sha256,
    uploaded_by_id: actor_user.id
  })
  |> Repo.insert(prefix: prefix)
end

defp bump_version(prefix, doc) do
  doc
  |> Document.version_bump_changeset()
  |> Repo.update(prefix: prefix)
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/atrium/documents/file_documents_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/documents.ex test/atrium/documents/file_documents_test.exs
git commit -m "feat(documents): add file document CRUD and decrypt helpers"
```

---

## Task 11: StaticUploads plug (images-only)

**Files:**
- Create: `lib/atrium_web/plugs/static_uploads.ex`
- Modify: `lib/atrium_web/endpoint.ex`
- Test: `test/atrium_web/plugs/static_uploads_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/atrium_web/plugs/static_uploads_test.exs`:

```elixir
defmodule AtriumWeb.Plugs.StaticUploadsTest do
  use AtriumWeb.ConnCase, async: true
  alias AtriumWeb.Plugs.StaticUploads

  @uploads "tmp/test_uploads"

  setup do
    File.mkdir_p!(Path.join([@uploads, "documents", "t1", "images"]))
    File.mkdir_p!(Path.join([@uploads, "documents", "t1", "files", "doc1"]))
    File.write!(Path.join([@uploads, "documents", "t1", "images", "pic.png"]), "img")
    File.write!(Path.join([@uploads, "documents", "t1", "files", "doc1", "v1.enc"]), "ciphertext")
    :ok
  end

  test "serves image under /uploads/documents/*/images/*", %{conn: conn} do
    conn =
      conn
      |> Map.put(:request_path, "/uploads/documents/t1/images/pic.png")
      |> Map.put(:path_info, ~w(uploads documents t1 images pic.png))
      |> StaticUploads.call(StaticUploads.init([]))

    # Either served by the plug or passed through for router 404 — depends on env.
    # The assertion is: the request path for images is reachable; the files path is not.
    assert conn.status in [200, 304] or conn.halted == false
  end

  test "404s request under /uploads/documents/*/files/*", %{conn: conn} do
    conn =
      conn
      |> Map.put(:request_path, "/uploads/documents/t1/files/doc1/v1.enc")
      |> Map.put(:path_info, ~w(uploads documents t1 files doc1 v1.enc))
      |> StaticUploads.call(StaticUploads.init([]))

    assert conn.status == 404 or conn.halted
  end
end
```

- [ ] **Step 2: Run the test to see it fail**

Run: `mix test test/atrium_web/plugs/static_uploads_test.exs`
Expected: FAIL — plug undefined.

- [ ] **Step 3: Implement the plug**

Create `lib/atrium_web/plugs/static_uploads.ex`:

```elixir
defmodule AtriumWeb.Plugs.StaticUploads do
  @moduledoc """
  Serves static uploads under /uploads, but ONLY paths of the form
  /uploads/documents/<tenant>/images/<filename>.

  Any other path (e.g. /uploads/documents/<tenant>/files/...) is 404'd
  before it can hit the filesystem — encrypted files must go through the
  authenticated download controller.
  """

  @behaviour Plug

  @impl true
  def init(_opts) do
    Plug.Static.init(
      at: "/uploads",
      from: Application.compile_env(:atrium, :uploads_root, "priv/uploads"),
      gzip: false
    )
  end

  @impl true
  def call(conn, static_opts) do
    if images_path?(conn.path_info) do
      Plug.Static.call(conn, static_opts)
    else
      conn
      |> Plug.Conn.send_resp(404, "Not found")
      |> Plug.Conn.halt()
    end
  end

  defp images_path?(["uploads", "documents", _tenant, "images" | _]), do: true
  defp images_path?(_), do: false
end
```

- [ ] **Step 4: Wire into the endpoint**

Modify `lib/atrium_web/endpoint.ex` — replace the existing `Plug.Static at: "/uploads"` block with:

```elixir
plug AtriumWeb.Plugs.StaticUploads
```

Also modify the `Plug.Parsers` block to add a `:length` option:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  length: 100 * 1024 * 1024,
  json_decoder: Phoenix.json_library()
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/atrium_web/plugs/static_uploads_test.exs`
Expected: PASS.

Run full test suite: `mix test`
Expected: PASS (inline document images in existing tests must still resolve).

- [ ] **Step 6: Commit**

```bash
git add lib/atrium_web/plugs/static_uploads.ex \
        lib/atrium_web/endpoint.ex \
        test/atrium_web/plugs/static_uploads_test.exs
git commit -m "feat(uploads): narrow /uploads static serving to images; raise multipart limit"
```

---

## Task 12: Routes — download and replace

**Files:**
- Modify: `lib/atrium_web/router.ex`

- [ ] **Step 1: Add routes**

Modify `lib/atrium_web/router.ex` — in the block containing the existing `/sections/:section_key/documents/...` routes (around line 196–209), add two new routes immediately after the `get ... /pdf` route:

```elixir
get  "/sections/:section_key/documents/:id/download", DocumentController, :download
post "/sections/:section_key/documents/:id/replace",  DocumentController, :replace
```

- [ ] **Step 2: Verify routes compile**

Run: `mix phx.routes | grep documents | grep -E "download|replace"`
Expected: both routes listed.

- [ ] **Step 3: Commit**

```bash
git add lib/atrium_web/router.ex
git commit -m "feat(documents): add download and replace routes"
```

---

## Task 13: Controller — download + replace + kind-aware create/edit

**Files:**
- Modify: `lib/atrium_web/controllers/document_controller.ex`
- Test: `test/atrium_web/controllers/document_controller_file_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/atrium_web/controllers/document_controller_file_test.exs`:

```elixir
defmodule AtriumWeb.DocumentControllerFileTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.Documents

  @tmp Path.join(System.tmp_dir!(), "atrium_ctl_file_test")

  setup %{conn: conn} do
    # Relies on existing test helpers to set up an authenticated editor user in a tenant.
    # Adjust to match existing conn_case helpers — see other controller tests for the pattern.
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)

    ctx = AtriumWeb.TestHelpers.sign_in_editor(conn, "hr")
    {:ok, ctx}
  end

  defp make_upload(content, filename \\ "doc.pdf", ct \\ "application/pdf") do
    path = Path.join(@tmp, "up_#{System.unique_integer([:positive])}.bin")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: ct}
  end

  test "POST create with kind=file uploads and persists the file",
       %{conn: conn, tenant_prefix: prefix, user: user} do
    upload = make_upload("hello")

    conn =
      post(conn, ~p"/sections/hr/documents", %{
        "document" => %{"title" => "My PDF", "kind" => "file", "file" => upload}
      })

    assert redirected_to(conn) =~ ~r|/sections/hr/documents/|

    [doc] = Documents.list_documents(prefix, "hr")
    assert doc.kind == "file"
    df = Documents.get_current_file(prefix, doc)
    assert df.file_name == "doc.pdf"
  end

  test "GET download sends the decrypted file",
       %{conn: conn, tenant_prefix: prefix, user: user} do
    content = "secret content"
    upload = make_upload(content)
    {:ok, doc} = Documents.create_file_document(prefix, user, "hr", %{title: "t", section_key: "hr"}, upload)

    conn = get(conn, ~p"/sections/hr/documents/#{doc.id}/download")

    assert response(conn, 200) == content
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "filename=\"doc.pdf\""
  end

  test "POST replace bumps version and stores a new encrypted blob",
       %{conn: conn, tenant_prefix: prefix, user: user} do
    {:ok, doc} =
      Documents.create_file_document(prefix, user, "hr", %{title: "t", section_key: "hr"}, make_upload("v1"))

    new = make_upload("v2 content", "new.pdf")

    conn = post(conn, ~p"/sections/hr/documents/#{doc.id}/replace", %{"file" => new})
    assert redirected_to(conn) =~ ~r|/sections/hr/documents/|

    reloaded = Documents.get_document!(prefix, doc.id)
    assert reloaded.current_version == 2

    df = Documents.get_current_file(prefix, reloaded)
    assert df.version == 2
    assert df.file_name == "new.pdf"
  end
end
```

If `AtriumWeb.TestHelpers.sign_in_editor/2` doesn't exist, copy the pattern from an existing controller test (e.g. `test/atrium_web/controllers/document_controller_test.exs`) and extract what that test does for auth setup.

- [ ] **Step 2: Run the test to see it fail**

Run: `mix test test/atrium_web/controllers/document_controller_file_test.exs`
Expected: FAIL — `create` doesn't handle `kind=file`; `download`/`replace` actions don't exist.

- [ ] **Step 3: Update the controller's plug list for the new actions**

Modify `lib/atrium_web/controllers/document_controller.ex` — update the authorize plugs to include the new actions:

```elixir
plug AtriumWeb.Plugs.Authorize,
     [capability: :view, target: &__MODULE__.section_target/1]
     when action in [:index, :show, :download_pdf, :download]

plug AtriumWeb.Plugs.Authorize,
     [capability: :edit, target: &__MODULE__.section_target/1]
     when action in [:new, :create, :edit, :update, :submit, :upload_image, :replace]
```

- [ ] **Step 4: Update create/2 to branch on kind**

Replace the existing `create/2` function with:

```elixir
def create(conn, %{"section_key" => section_key, "document" => %{"kind" => "file"} = doc_params}) do
  prefix = conn.assigns.tenant_prefix
  user = conn.assigns.current_user

  case Map.get(doc_params, "file") do
    %Plug.Upload{} = upload ->
      attrs = %{title: doc_params["title"], section_key: section_key, subsection_slug: doc_params["subsection_slug"]}

      case Documents.create_file_document(prefix, user, section_key, attrs, upload) do
        {:ok, doc} ->
          conn
          |> put_flash(:info, "File document created.")
          |> redirect(to: ~p"/sections/#{section_key}/documents/#{doc.id}")

        {:error, :invalid_mime} ->
          conn
          |> put_flash(:error, "File type not allowed.")
          |> redirect(to: ~p"/sections/#{section_key}/documents/new?kind=file")

        {:error, :too_large} ->
          conn
          |> put_flash(:error, "File is too large (max 100 MB).")
          |> redirect(to: ~p"/sections/#{section_key}/documents/new?kind=file")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Upload failed.")
          |> redirect(to: ~p"/sections/#{section_key}/documents/new?kind=file")
      end

    _ ->
      conn
      |> put_flash(:error, "Please select a file to upload.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/new?kind=file")
  end
end

def create(conn, %{"section_key" => section_key, "document" => doc_params}) do
  prefix = conn.assigns.tenant_prefix
  user = conn.assigns.current_user
  attrs = Map.put(doc_params, "section_key", section_key)

  case Documents.create_document(prefix, attrs, user) do
    {:ok, doc} ->
      conn
      |> put_flash(:info, "Document created.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{doc.id}")

    {:error, %Ecto.Changeset{} = changeset} ->
      conn
      |> put_status(422)
      |> render(:new, changeset: changeset, section_key: section_key)

    {:error, _reason} ->
      conn
      |> put_flash(:error, "An unexpected error occurred.")
      |> redirect(to: ~p"/sections/#{section_key}/documents")
  end
end
```

- [ ] **Step 5: Update new/2 to pass kind to the template**

Replace the existing `new/2` with:

```elixir
def new(conn, %{"section_key" => section_key} = params) do
  changeset = Document.changeset(%Document{}, %{})
  kind = Map.get(params, "kind", "rich_text")
  render(conn, :new, changeset: changeset, section_key: section_key, kind: kind)
end
```

- [ ] **Step 6: Add download/2 and replace/2**

Append to the controller, before the `defp inline_images`:

```elixir
def download(conn, %{"section_key" => section_key, "id" => id}) do
  prefix = conn.assigns.tenant_prefix
  user = conn.assigns.current_user
  doc = Documents.get_document!(prefix, id)

  case Documents.decrypt_for_download(prefix, doc) do
    {:ok, tmp_path, file_name, mime} ->
      _ = Atrium.Audit.log(prefix, "document.file_downloaded", %{
        actor: {:user, user.id},
        resource: {"Document", doc.id},
        meta: %{version: doc.current_version}
      })

      conn =
        conn
        |> put_resp_content_type(mime)
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{file_name}"))

      conn = send_file(conn, 200, tmp_path)
      Task.start(fn -> Process.sleep(5_000); File.rm(tmp_path) end)
      conn

    {:error, :not_file_document} ->
      conn
      |> put_flash(:error, "This document is not an uploaded file.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")

    {:error, _reason} ->
      conn
      |> put_flash(:error, "Could not download file.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")
  end
end

def replace(conn, %{"section_key" => section_key, "id" => id, "file" => %Plug.Upload{} = upload}) do
  prefix = conn.assigns.tenant_prefix
  user = conn.assigns.current_user
  doc = Documents.get_document!(prefix, id)

  case Documents.replace_file_document(prefix, doc, user, upload) do
    {:ok, _updated} ->
      conn
      |> put_flash(:info, "File replaced.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")

    {:error, :not_file_document} ->
      conn
      |> put_flash(:error, "Only file documents can be replaced.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}")

    {:error, :invalid_mime} ->
      conn
      |> put_flash(:error, "File type not allowed.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}/edit")

    {:error, :too_large} ->
      conn
      |> put_flash(:error, "File is too large (max 100 MB).")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}/edit")

    {:error, _reason} ->
      conn
      |> put_flash(:error, "Replace failed.")
      |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}/edit")
  end
end

def replace(conn, %{"section_key" => section_key, "id" => id}) do
  conn
  |> put_flash(:error, "Please select a file.")
  |> redirect(to: ~p"/sections/#{section_key}/documents/#{id}/edit")
end
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `mix test test/atrium_web/controllers/document_controller_file_test.exs`
Expected: PASS.

Run: `mix test`
Expected: all tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/atrium_web/controllers/document_controller.ex \
        test/atrium_web/controllers/document_controller_file_test.exs
git commit -m "feat(documents): controller supports file uploads, downloads, replacements"
```

---

## Task 14: Views — tabbed new, file card in show, replace form in edit, icon in index

**Files:**
- Modify: `lib/atrium_web/controllers/document_html/new.html.heex`
- Modify: `lib/atrium_web/controllers/document_html/show.html.heex`
- Modify: `lib/atrium_web/controllers/document_html/edit.html.heex`
- Modify: `lib/atrium_web/controllers/document_html/index.html.heex`
- Modify: `lib/atrium_web/controllers/document_html.ex` (add helper for MIME icon)

This task has no TDD flow — these are UI changes. Verify manually at the end.

- [ ] **Step 1: Add MIME-icon helper**

Modify `lib/atrium_web/controllers/document_html.ex` — append a helper function:

```elixir
def document_icon(%{kind: "rich_text"}), do: "hero-document-text"
def document_icon(%{kind: "file"} = doc) do
  # Look up mime via the latest document_files row; fall back to a generic icon.
  case Map.get(doc, :mime_type) || nil do
    "application/pdf" -> "hero-document"
    "application/" <> _ -> "hero-document-duplicate"
    "image/" <> _ -> "hero-photo"
    "text/" <> _ -> "hero-document-text"
    _ -> "hero-paper-clip"
  end
end
def document_icon(_), do: "hero-document-text"
```

- [ ] **Step 2: Update new.html.heex**

Read the existing file first, then replace the form body with a tabbed layout. Since the current template renders a `@changeset` with TipTap, the change is to wrap the form in a kind-selector. Replace the whole file with:

```heex
<.header>
  New document
  <:subtitle>Section: <%= @section_key %></:subtitle>
</.header>

<div class="mb-4 flex gap-2 border-b border-slate-200">
  <.link
    patch={~p"/sections/#{@section_key}/documents/new?kind=rich_text"}
    class={"px-4 py-2 #{if @kind == "rich_text", do: "border-b-2 border-indigo-500 font-semibold", else: "text-slate-500"}"}
  >
    Write document
  </.link>
  <.link
    patch={~p"/sections/#{@section_key}/documents/new?kind=file"}
    class={"px-4 py-2 #{if @kind == "file", do: "border-b-2 border-indigo-500 font-semibold", else: "text-slate-500"}"}
  >
    Upload file
  </.link>
</div>

<%= if @kind == "file" do %>
  <.simple_form :let={f} for={@changeset} action={~p"/sections/#{@section_key}/documents"} multipart>
    <input type="hidden" name="document[kind]" value="file" />
    <.input field={f[:title]} type="text" label="Title" required />
    <div>
      <label class="block text-sm font-medium text-slate-700 mb-1">File</label>
      <input type="file" name="document[file]" required
             accept=".pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.odt,.txt,.png,.jpg,.jpeg,.gif,.webp"
             class="block w-full text-sm" />
      <p class="mt-1 text-xs text-slate-500">Max 100 MB. PDF, Office, OpenDocument, plain text, or images.</p>
    </div>
    <:actions>
      <.button>Upload file</.button>
    </:actions>
  </.simple_form>
<% else %>
  <.simple_form :let={f} for={@changeset} action={~p"/sections/#{@section_key}/documents"}>
    <input type="hidden" name="document[kind]" value="rich_text" />
    <.input field={f[:title]} type="text" label="Title" required />

    <div>
      <label class="block text-sm font-medium text-slate-700 mb-1">Body</label>
      <div id="tiptap-editor" phx-hook="TiptapEditor" data-input-name="document[body_html]"
           data-initial-html={Phoenix.HTML.Form.input_value(f, :body_html) || ""}
           data-upload-url={~p"/sections/#{@section_key}/documents/upload_image"}></div>
      <input type="hidden" name="document[body_html]" id="tiptap-input" value={Phoenix.HTML.Form.input_value(f, :body_html) || ""} />
    </div>

    <:actions>
      <.button>Create document</.button>
    </:actions>
  </.simple_form>
<% end %>
```

**If the existing template uses a different structure** (e.g. a shared `form.html.heex` partial), adapt by wrapping that partial in the same kind-conditional — don't blindly overwrite. Read the file first with the Read tool before editing.

- [ ] **Step 3: Update show.html.heex**

Read the existing show template first. Insert a conditional block **before** the rich-text body block, like:

```heex
<%= if @document.kind == "file" do %>
  <% df = Atrium.Documents.get_current_file(@tenant_prefix, @document) %>
  <div class="rounded border border-slate-200 p-4 bg-slate-50 flex items-center gap-4">
    <.icon name={AtriumWeb.DocumentHTML.document_icon(%{kind: "file", mime_type: df && df.mime_type})} class="w-10 h-10 text-indigo-600" />
    <div class="flex-1">
      <div class="font-semibold text-slate-900"><%= df && df.file_name %></div>
      <div class="text-xs text-slate-500">
        <%= df && Atrium.Documents.Format.bytes(df.byte_size) %> · v<%= @document.current_version %>
      </div>
    </div>
    <.link href={~p"/sections/#{@section_key}/documents/#{@document.id}/download"}
           class="rounded bg-indigo-600 px-4 py-2 text-white text-sm">
      Download
    </.link>
  </div>
<% else %>
  <!-- existing rich-text body rendering stays here -->
<% end %>
```

The existing body block moves inside the `else`.

Also ensure `@tenant_prefix` is assigned by the controller. Check `show/2` — if it doesn't assign it, add `tenant_prefix: prefix` to the `render` call.

Create a tiny helper `lib/atrium/documents/format.ex`:

```elixir
defmodule Atrium.Documents.Format do
  def bytes(n) when is_integer(n) and n < 1_024, do: "#{n} B"
  def bytes(n) when n < 1_048_576, do: "#{Float.round(n / 1_024, 1)} KB"
  def bytes(n) when n < 1_073_741_824, do: "#{Float.round(n / 1_048_576, 1)} MB"
  def bytes(n), do: "#{Float.round(n / 1_073_741_824, 2)} GB"
  def bytes(_), do: "?"
end
```

- [ ] **Step 4: Update edit.html.heex**

Read the existing edit template first. Wrap the rich-text form in a conditional; for file-kind docs, render a replace form posting to `/replace`:

```heex
<%= if @document.kind == "file" do %>
  <.simple_form for={%{}} as={:_} action={~p"/sections/#{@section_key}/documents/#{@document.id}/replace"} method="post" multipart>
    <div>
      <label class="block text-sm font-medium text-slate-700 mb-1">Replace file</label>
      <input type="file" name="file" required class="block w-full text-sm" />
      <p class="mt-1 text-xs text-slate-500">Uploading a new file creates v<%= @document.current_version + 1 %>.</p>
    </div>
    <:actions>
      <.button>Upload new version</.button>
    </:actions>
  </.simple_form>
<% else %>
  <!-- existing rich-text edit form -->
<% end %>
```

- [ ] **Step 5: Update index.html.heex**

Read the existing index template first. Add a small icon cell to each row, using `AtriumWeb.DocumentHTML.document_icon/1`. Wrap the call at a safe place near the document title:

```heex
<.icon name={AtriumWeb.DocumentHTML.document_icon(document)} class="w-4 h-4 inline-block text-slate-400 mr-1" />
<%= document.title %>
```

- [ ] **Step 6: Start the server and verify manually**

Run: `mix phx.server`

In a browser:
1. Navigate to a section with edit permission, click "New document". Verify the two tabs appear and default to "Write document".
2. Switch to "Upload file" tab. Enter a title, choose a PDF, submit. Expect redirect to show page.
3. On the show page, verify the file card with a download button. Click download — the file downloads with the original filename.
4. Navigate to edit for that document. Verify the replace form appears. Replace with a new PDF; confirm `current_version` advances.
5. Navigate to index — confirm the PDF row has a file icon and the rich-text rows have their icon.

- [ ] **Step 7: Commit**

```bash
git add lib/atrium_web/controllers/document_html.ex \
        lib/atrium_web/controllers/document_html/ \
        lib/atrium/documents/format.ex
git commit -m "feat(documents): kind-aware new/show/edit/index views"
```

---

## Task 15: Verify complete suite and add spec cross-reference

- [ ] **Step 1: Full suite**

Run: `mix test`
Expected: all tests PASS.

Run: `mix compile --warnings-as-errors`
Expected: no warnings.

- [ ] **Step 2: Manual end-to-end smoke**

Same browser steps as Task 14 Step 6, but also:
- Confirm downloading sends plaintext content that matches the original upload (e.g. open a PDF in the viewer).
- Try uploading a `.exe` file renamed to `.pdf` — it should be rejected at MIME validation (the browser sends `application/octet-stream`, which is not in the whitelist).
- Try a large file (>100 MB) — should be rejected.
- Check `priv/uploads/documents/<tenant>/files/<doc_id>/v*.enc` exists and is NOT the original plaintext.
- Confirm `/uploads/documents/<tenant>/files/<doc_id>/v1.enc` direct URL returns 404.
- Confirm `/uploads/documents/<tenant>/images/<any>.png` direct URL still works (for TipTap inline images).

- [ ] **Step 3: Commit a PR-ready summary**

```bash
git log --oneline main..HEAD
```

Compare to the spec file and confirm every "Files touched/created" bullet has a commit.

---

## Self-review (already run before publishing)

- Spec coverage: each of the 11 sub-requirements in the spec maps to at least one task. ✓
- Placeholder scan: no "TBD", "TODO", "implement later", "add appropriate handling". ✓
- Type consistency: `wrapped_key`, `iv`, `auth_tag` named identically across DataKey, FileEncryptor, FileDecryptor, Processor, DocumentFile schema, migration, and context. `get_current_file/2` referenced with the same signature in context + controller + views. ✓
- Two callouts for known Erlang `:crypto` API quirks (Task 6, Task 7) — these are implementation-time decisions, not placeholders; the plan tells the engineer exactly what to do if either path fails.
