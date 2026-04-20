# Deployment Scripts + Encrypted File Documents — Design

Date: 2026-04-20
Status: Approved for implementation

## Goals

Two independent but co-delivered deliverables:

1. **Encrypted file documents** — extend the Documents feature so a document can be either a TipTap-authored rich-text doc (existing) *or* an uploaded binary file (PDF, DOCX, XLSX, PPTX, ODT, TXT, common images). Uploaded files are encrypted at rest with AES-256-GCM; per-file data keys are wrapped with a master key supplied via env var. Both kinds appear side-by-side in the same documents list and share ACLs, comments, versioning, and the approval workflow.

2. **Minimal production deployment scripts** — a `bin/deploy` shell script that builds an Elixir release on a target VPS using `asdf`, a `bin/deploy_remote` SSH wrapper, an `Atrium.Release` module for migrations, and an nginx config template. Modeled on alldoqexchange but stripped of its app-specific baggage.

## Non-goals

- LiveView-based uploads with chunking / progress (possible later polish).
- Separate `DocumentFileController`; we keep one controller.
- Encrypting existing uploaded images (inline document images remain unencrypted — they are served directly to browsers by `Plug.Static`).
- Containerized deployment (Docker).
- Multi-environment deploy wrapper scripts (`deploy_remote_staging`, etc.) — users copy the single example.
- Server-side virus scanning (out of scope; MIME whitelist is the safety net).
- Key rotation tooling.

## Threat model

Protects against: stolen DB dump alone, stolen encrypted-files directory alone, stolen DB + files but not env (master key lives in env only).

Does **not** protect against: a fully compromised app host (attacker has DB + files + env). Same threat model as the existing `Atrium.Vault` (Cloak) configuration — we reuse the key-handling pattern for consistency.

---

## Part 1 — Encrypted file documents

### 1.1 Schema

Two tenant migrations.

**Migration A — `add_kind_to_documents`:**

```
alter table :documents
  add :kind, :string, null: false, default: "rich_text"
create index(:documents, [:kind])
```

Backfill: existing rows all get `kind = "rich_text"` via the default.

**Migration B — `create_document_files`:**

```
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
```

### 1.2 Schema modules

`Atrium.Documents.Document`
- Add `field :kind, :string, default: "rich_text"` to the schema.
- `@kinds ~w(rich_text file)`
- Validate `:kind` inclusion in `@kinds`.
- Rich-text changesets require `body_html` to be accepted but optional at DB level.
- `file_changeset/2` sets `kind = "file"` and does not sanitize HTML.

`Atrium.Documents.DocumentFile` (new)
- All fields listed in the migration, binary_id primary key, `belongs_to :document`.
- `changeset/2` validates required fields and positive `byte_size`.

### 1.3 Encryption modules

Namespace: `Atrium.Documents.Encryption`.

**`MasterKey`** — reads `Application.fetch_env!(:atrium, :file_encryption_key)`, caches via `:persistent_term.put/2` with key `{__MODULE__, :key}` on first read. Returns 32-byte binary.

**`DataKey`** — two functions:
- `generate/0 → {key_32b, iv_12b}` via `:crypto.strong_rand_bytes/1`
- `wrap(key_32b) → ciphertext` — AES-256-GCM encrypts the data key under the master key. Generates a fresh 12-byte IV, returns `iv <> auth_tag <> ciphertext` as one binary stored in `wrapped_key`.
- `unwrap(wrapped_binary) → key_32b` — splits and decrypts; raises on auth failure.

**`FileEncryptor`**
- `call(source_path, dest_path, key, iv)` — opens both files, uses `:crypto.crypto_init(:aes_256_gcm, key, iv, true)` + `:crypto.crypto_update/2` + `:crypto.crypto_final/1` to stream in 64 KB chunks. Simultaneously feeds a `:crypto.hash_init(:sha256)` accumulator with plaintext chunks. Writes only ciphertext chunks to dest. Returns `{:ok, %{auth_tag: <<16 bytes>>, byte_size: plaintext_bytes, sha256: hex_string}}`.
- On any failure, deletes partial dest file before returning `{:error, reason}`.

**`FileDecryptor`**
- `call(source_path, dest_path, key, iv, auth_tag)` — mirror. Uses `:crypto.crypto_init/4` with decrypt flag, feeds final `auth_tag` via `:crypto.crypto_final/1` (raises `{:error, :decrypt_failed}` on tag mismatch). Returns `{:ok, plaintext_size}`.
- On auth failure, deletes partial dest and returns `{:error, :auth_failed}`.

**`Processor`**
- `encrypt_upload(%Plug.Upload{} = upload, dest_path)` — orchestrates: generate key+iv, run `FileEncryptor.call(upload.path, dest_path, key, iv)`, wrap key. Returns `{:ok, %{storage_path, wrapped_key, iv, auth_tag, byte_size, sha256}}`. Caller is responsible for `dest_path` being under the tenant's encrypted-files directory.
- `decrypt_to_temp(%DocumentFile{} = df)` — generates a temp path in `System.tmp_dir!()`, unwraps key, calls `FileDecryptor.call/5`. Returns `{:ok, temp_path}` — caller must `File.rm/1` after send.

### 1.4 Storage paths

Encrypted blobs live at:
```
<uploads_root>/documents/<tenant_prefix>/files/<document_id>/v<version>.enc
```

`<uploads_root>` is `priv/uploads` in dev/test, `/var/www/atrium/shared/uploads` in prod (via env var `ATRIUM_UPLOADS_ROOT`).

The `storage_path` stored in the DB is relative to the uploads root, e.g. `documents/tenant_mcl/files/<uuid>/v1.enc`. Absolute path is computed on demand.

Helper `Atrium.Documents.Storage.uploads_root/0` reads config; `tenant_files_dir(prefix, doc_id) → absolute path`.

### 1.5 Context functions (`Atrium.Documents`)

New public functions, all called from controller:

- `create_file_document(prefix, user, section_key, attrs, %Plug.Upload{})` — transactional:
  1. Validate MIME (whitelist + byte sniff via `MIME.from_path/1`) and size.
  2. Insert `%Document{}` with `kind: "file"`, title from attrs.
  3. Encrypt upload to `<tenant>/files/<doc_id>/v1.enc`.
  4. Insert `%DocumentFile{}` with version=1 and encryption metadata.
  5. Emit audit event `document.file_uploaded`.

  If any step fails, rollback + cleanup any partial `.enc` file.

- `replace_file_document(prefix, doc, user, %Plug.Upload{})` — validates kind=file, bumps `documents.current_version`, inserts new `document_files` row for new version, encrypts to `v<N>.enc`. Old blob retained. Transactional with cleanup.

- `get_current_file(prefix, doc) → %DocumentFile{} | nil` — joins on `(document_id, version == current_version)`.

- `decrypt_for_download(prefix, doc) → {:ok, temp_path, file_name, mime_type} | {:error, term}` — fetches current file, delegates to `Encryption.Processor.decrypt_to_temp/1`.

MIME sniffing: for the uploaded tempfile, use `MIME.from_path/1` on filename first, then confirm against file-magic bytes for PDF (`%PDF-`), ZIP-based Office (`PK\x03\x04`), and plain-text (UTF-8 valid). Reject mismatch.

### 1.6 Controller changes (`AtriumWeb.DocumentController`)

Existing authorization plugs (view/edit/approve) already cover the new actions through section ACLs — no new capabilities needed.

- `new/2` — accepts `?kind=file`; assigns `kind` to template.
- `create/2` — branches on `params["document"]["kind"]` (or `params["kind"]`):
  - `"file"` path pulls `%Plug.Upload{} = params["document"]["file"]`; calls `Documents.create_file_document/5`.
  - `"rich_text"` path unchanged.
- `show.html.heex` — conditional renders a "file card" for `kind=file`: MIME icon, original file name, size, uploader, version, download button. Comments UI unchanged.
- `edit/2` — for `kind=file`, renders a "replace file" form (file input + title field). Submits to `POST /sections/:section_key/documents/:id/replace`.
- `update/2` — for `kind=file` continues to handle title-only updates.
- `replace/2` (new) — capability `:edit`; calls `Documents.replace_file_document/4`; redirects to show.
- `download/2` (new) — capability `:view`; fetches current `DocumentFile`, decrypts to temp, `send_file/3` with `content-disposition: attachment; filename="<file_name>"`, schedules `File.rm/1` via `Plug.Conn.register_before_send/2` (actually this fires before the body; use `Plug.Conn.on_sent/1`-style callback — in practice we use a `Task.start/1` after `send_file/3` returns since `send_file` is synchronous for small files and Bandit streams larger ones; the cleanest approach is `Plug.Conn.register_before_send/2` capturing the tmp path and spawning a cleanup task).

Router additions (inside the existing `scope "/sections/:section_key"`):
```
get  "/documents/:id/download", DocumentController, :download
post "/documents/:id/replace",  DocumentController, :replace
```

### 1.7 Views & UI

`index.html.heex`:
- Add a small icon column: PDF/Word/Excel/PPT/image/text icon for `kind=file`, existing doc icon for `rich_text`.
- Each list row is a link to the existing show page regardless of kind.

`show.html.heex`:
- Conditional on `@document.kind`:
  - `rich_text` → existing body rendering.
  - `file` → file card with icon, filename, size-pretty, MIME, uploaded-by user name, version, and a primary "Download" button. Below the card, an "upload new version" form (visible only to users with `:edit`).
- Comments and approval UI shared.

`new.html.heex`:
- Two-tab selector at top: "Write document" / "Upload file". Defaults to rich_text; `?kind=file` pre-selects file. Each tab swaps the body of the form (TipTap editor vs file input). Single `<form>` per page; the tab is just CSS + a hidden `kind` field.

TipTap editor is untouched.

### 1.8 Config

`config/config.exs`:
```elixir
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
  "image/png", "image/jpeg", "image/gif", "image/webp"
]
```

`config/dev.exs` and `config/test.exs`:
```elixir
# 32-byte dev-only key (not for prod)
config :atrium, :file_encryption_key,
  <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32>>
```

`config/runtime.exs` (prod block):
```elixir
file_key =
  System.get_env("ATRIUM_FILE_ENCRYPTION_KEY") ||
    raise "ATRIUM_FILE_ENCRYPTION_KEY must be set in production (32 bytes, base64-encoded)"

config :atrium, :file_encryption_key, Base.decode64!(file_key)
config :atrium, :uploads_root, System.get_env("ATRIUM_UPLOADS_ROOT") || "/var/www/atrium/shared/uploads"
```

### 1.9 Endpoint changes

`lib/atrium_web/endpoint.ex`:
- Narrow `Plug.Static` `only: ~w(...)` to exclude `files` under `/uploads`. Current config serves the entire `priv/static` + `/uploads`; we need `/uploads` to serve `documents/*/images` but NOT `documents/*/files`. Implementation: a custom plug `AtriumWeb.Plugs.StaticUploads` that only serves paths matching `~r|^/uploads/documents/[^/]+/images/|` and 404s everything else under `/uploads`.
- `Plug.Parsers` — increase `:length` for multipart to 100 MB (`length: 100 * 1024 * 1024`).

### 1.10 Audit events

- `document.file_uploaded` — on `create_file_document` success.
- `document.file_replaced` — on `replace_file_document` success.
- `document.file_downloaded` — on `download/2` action success, after `send_file/3` completes.

Each carries `actor: {:user, user.id}` and `resource: {"Document", doc.id}` with `file_version` in meta.

### 1.11 Testing strategy

Unit tests (no DB):
- `MasterKey` returns 32-byte binary; raises if missing.
- `DataKey.wrap |> DataKey.unwrap` round-trips; tampered wrapped binary raises.
- `FileEncryptor` + `FileDecryptor` round-trip a 1 MB random file; tampered ciphertext fails with `:auth_failed`; tampered auth_tag fails.

Integration tests (with tenant DB prefix):
- `create_file_document` inserts both `documents` and `document_files` rows; encrypted blob exists on disk; plaintext does not.
- `replace_file_document` bumps version; old blob retained; new row's version is current.
- `decrypt_for_download` produces a tmp file with matching SHA-256.
- MIME whitelist rejects `.exe`; byte-sniff rejects a `.exe` renamed to `.pdf`.
- Size limit rejects >100 MB.
- Download action: ACL denial returns 403; success sends the file bytes.

---

## Part 2 — Deployment scripts

### 2.1 Files to create

```
bin/
├── deploy              # runs on target server — asdf + release build + symlink + restart
├── deploy_remote       # runs on developer machine — SSH wrapper
└── deploy_remote_example  # commented template for per-environment config

lib/atrium/release.ex   # migrate/rollback callables for release eval

rel/env.sh.eex          # generated by mix phx.gen.release
rel/env.bat.eex         # generated by mix phx.gen.release

nginx/atrium.conf       # nginx site template

.tool-versions          # pin asdf versions (if not already present)
```

### 2.2 `Atrium.Release` module

```elixir
defmodule Atrium.Release do
  @app :atrium

  def migrate do
    load_app()
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
    # tenant migrations: iterate all tenants and run Triplex.migrate/2
    Atrium.Tenants.list_tenants()
    |> Enum.each(&Triplex.migrate/1)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.load(@app)
end
```

(Exact Triplex iteration API to be confirmed during implementation; fallback is to iterate schemas from `information_schema.schemata` directly.)

### 2.3 `bin/deploy` (simplified from alldoqexchange)

- Configurable via env vars: `DEPLOY_PATH`, `REPO_URL`, `BRANCH`, `APP_NAME=atrium`, `PORT`, `KEEP_RELEASES`.
- Commands: `deploy`, `rollback`, `setup`, `cleanup`, `help`.
- Dropped from the alldoq version: DoqBuilder frontend clone/embed, PDF.js viewer setup, tula port 4006 special case, environment-specific stop scripts.
- Kept: asdf install + plugin management, `.tool-versions`-driven version install, release builds, shared dir symlinks (`uploads`, `logs`, `.env`), current-symlink rotation, daemon restart via `bin/atrium daemon`, old-release cleanup.
- Shared dirs: `uploads`, `logs`. Shared file: `.env`.

### 2.4 `bin/deploy_remote`

Thin SSH wrapper. Copies `bin/deploy` to `/tmp/deploy` on the target, then SSHes in with env vars set and executes. Supports `deploy | rollback | setup | cleanup`.

Configurable via env: `REMOTE_HOST`, `REMOTE_USER`, `REMOTE_PORT`, plus the same set forwarded to `bin/deploy`.

### 2.5 nginx config template

Adapted from alldoqexchange's — single upstream, reverse proxy, WebSocket upgrade headers for LiveView, 200 MB `client_max_body_size` (double the file limit to leave headroom), health check path, static `/uploads/documents/*/images/` location served directly, static `/assets/` served from the release's `priv/static`. Commented HTTPS server block for later.

### 2.6 Shared `.env` contents (example, documented in README addendum)

```
DATABASE_URL=ecto://atrium:***@localhost/atrium_prod
SECRET_KEY_BASE=<mix phx.gen.secret output>
PHX_HOST=atrium.example.com
PORT=4000
ATRIUM_CLOAK_KEY=<base64 32 bytes>
ATRIUM_FILE_ENCRYPTION_KEY=<base64 32 bytes>
ATRIUM_UPLOADS_ROOT=/var/www/atrium/shared/uploads
```

### 2.7 Testing strategy

Not unit-testable in the normal sense. Verification plan:
- `shellcheck bin/deploy bin/deploy_remote` — no errors.
- Run `bin/deploy setup` on a clean Ubuntu 22.04 VM; expect asdf + erlang + elixir + node installed.
- Run `bin/deploy deploy`; expect `/var/www/atrium/current` symlink, release binary under `_build/prod/rel/atrium/bin/atrium`, app reachable on configured port.
- Run `bin/deploy rollback`; expect symlink flipped to previous release, app restarts.
- Nginx config passes `nginx -t` after symlink into `sites-enabled`.

---

## Open implementation questions (not blocking design)

These are fine to decide during implementation:

- `Plug.Conn.on_sent`-style cleanup for downloaded temp files — exact API. If Bandit doesn't expose one, use `Plug.Conn.register_before_send/2` to spawn a `Task` that waits a few seconds then removes the temp file (best-effort); also have a periodic cleaner for `System.tmp_dir!()` files older than 1 hour.
- Triplex tenant enumeration for release migrations — verify the public API.
- Whether to pre-create `<tenant>/files/<document_id>/` directory at document-insert time or at first-file-save time (cleaner: at first file save, mkdir_p inside the transaction).

## Summary of files touched/created

**New:**
- `lib/atrium/documents/document_file.ex`
- `lib/atrium/documents/encryption/master_key.ex`
- `lib/atrium/documents/encryption/data_key.ex`
- `lib/atrium/documents/encryption/file_encryptor.ex`
- `lib/atrium/documents/encryption/file_decryptor.ex`
- `lib/atrium/documents/encryption/processor.ex`
- `lib/atrium/documents/storage.ex`
- `lib/atrium_web/plugs/static_uploads.ex`
- `priv/repo/tenant_migrations/<ts>_add_kind_to_documents.exs`
- `priv/repo/tenant_migrations/<ts>_create_document_files.exs`
- `bin/deploy`
- `bin/deploy_remote`
- `bin/deploy_remote_example`
- `lib/atrium/release.ex`
- `rel/env.sh.eex`, `rel/env.bat.eex`
- `nginx/atrium.conf`
- Test files for encryption modules + document file context functions.

**Modified:**
- `lib/atrium/documents/document.ex` — add `:kind`.
- `lib/atrium/documents.ex` — new context functions.
- `lib/atrium_web/controllers/document_controller.ex` — branch on kind, add download/replace actions.
- `lib/atrium_web/controllers/document_html/new.html.heex` — tabbed form.
- `lib/atrium_web/controllers/document_html/show.html.heex` — kind-conditional rendering.
- `lib/atrium_web/controllers/document_html/edit.html.heex` — replace-file form for kind=file.
- `lib/atrium_web/controllers/document_html/index.html.heex` — MIME icon per row.
- `lib/atrium_web/router.ex` — new routes.
- `lib/atrium_web/endpoint.ex` — narrower static uploads, bigger parser limit.
- `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/runtime.exs` — keys, limits, uploads root.
- `mix.exs` — no new deps expected (uses stdlib `:crypto`).
