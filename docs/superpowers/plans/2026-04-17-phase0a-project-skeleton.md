# Atrium Phase 0a — Project Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a Phoenix project with schema-per-tenant multi-tenancy (Triplex), a `Tenants` context that can provision and manage tenant records, a super-admin area with local auth, a subdomain-based tenant resolver plug, and a global audit-events table that later plans will write to.

**Architecture:** Single Phoenix app (non-umbrella) with Ecto and Postgres. The public schema holds tenant catalogue rows, super-admins, and global audit events. Each tenant gets a Postgres schema created by Triplex; Phase 0a creates empty tenant schemas that later plans populate. Tenant resolution is a subdomain plug that sets the Triplex prefix for the request. Super-admin routes live on a separate host behind their own pipeline that never sets a tenant prefix. Vue 3 / Tailwind integration is scaffolded so later plans can drop Vue islands into HEEx templates.

**Tech Stack:** Phoenix 1.7, Elixir 1.17, Postgres 16, Ecto 3, Triplex, Argon2 for super-admin password hashing, Oban for background jobs (installed now, used by later plans), Cloak for field-level encryption (installed now, used by plan 0c), Tailwind via the Phoenix esbuild/tailwind installers, Vue 3 added via esbuild.

---

## File Structure

```
atrium/
├── mix.exs
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
├── lib/
│   ├── atrium/
│   │   ├── application.ex
│   │   ├── repo.ex
│   │   ├── mailer.ex
│   │   ├── tenants.ex                 # public API for tenants
│   │   ├── tenants/
│   │   │   ├── tenant.ex              # Ecto schema
│   │   │   ├── provisioner.ex         # schema provisioning logic
│   │   │   └── theme.ex               # theme struct + defaults
│   │   ├── super_admins.ex            # public API for super-admins
│   │   ├── super_admins/
│   │   │   ├── super_admin.ex
│   │   │   └── super_admin_session.ex
│   │   ├── audit.ex                   # public API for audit logs
│   │   └── audit/
│   │       └── global_event.ex        # audit_events_global schema
│   ├── atrium_web/
│   │   ├── endpoint.ex
│   │   ├── router.ex
│   │   ├── telemetry.ex
│   │   ├── plugs/
│   │   │   ├── tenant_resolver.ex
│   │   │   └── require_super_admin.ex
│   │   ├── controllers/
│   │   │   ├── health_controller.ex
│   │   │   ├── page_controller.ex             # minimal tenant landing
│   │   │   └── super_admin/
│   │   │       ├── session_controller.ex
│   │   │       ├── tenant_controller.ex
│   │   │       └── dashboard_controller.ex
│   │   └── components/
│   │       └── layouts/
│   │           ├── app.html.heex
│   │           ├── super_admin.html.heex
│   │           └── root.html.heex
│   └── mix/
│       └── tasks/
│           └── atrium.provision_tenant.ex
├── priv/
│   └── repo/
│       ├── migrations/              # public-schema migrations
│       └── tenant_migrations/       # per-tenant schema migrations (empty in 0a)
├── assets/
│   ├── package.json
│   ├── vite/esbuild config           # for Vue 3 + Tailwind
│   ├── css/app.css
│   ├── js/app.js
│   └── vendor/
└── test/
    ├── support/
    │   ├── conn_case.ex
    │   ├── data_case.ex
    │   └── tenant_case.ex            # helper to create isolated tenants for tests
    ├── atrium/
    │   ├── tenants_test.exs
    │   ├── tenants/provisioner_test.exs
    │   ├── super_admins_test.exs
    │   └── audit_test.exs
    └── atrium_web/
        ├── plugs/tenant_resolver_test.exs
        ├── controllers/health_controller_test.exs
        └── controllers/super_admin/
            ├── session_controller_test.exs
            └── tenant_controller_test.exs
```

---

## Task 1: Bootstrap Phoenix project

**Files:**
- Create: entire `atrium/` project via `mix phx.new`

- [ ] **Step 1: Generate the Phoenix app**

Run from `/Users/marcinwalczak/Kod`:

```bash
mix phx.new atrium --database postgres --no-mailer --install
```

Expected: new `atrium/` directory with a working Phoenix scaffold and deps installed.

- [ ] **Step 2: Move existing docs into the generated project**

The `docs/superpowers/` directory already exists at `/Users/marcinwalczak/Kod/atrium/docs/superpowers/` (specs + plans). Confirm it's preserved — `mix phx.new` creates the project in the existing directory and should leave `docs/` untouched. If anything was clobbered, restore from memory.

Run:

```bash
ls /Users/marcinwalczak/Kod/atrium/docs/superpowers/specs
ls /Users/marcinwalczak/Kod/atrium/docs/superpowers/plans
```

Expected: both directories contain the spec and plan files created before this task.

- [ ] **Step 3: Initialise git and first commit**

Run from `/Users/marcinwalczak/Kod/atrium`:

```bash
git init
git add -A
git commit -m "chore: bootstrap Phoenix 1.7 project for atrium"
```

Expected: git repo initialised, one commit containing the generated project plus the pre-existing docs directory.

- [ ] **Step 4: Create and migrate the dev database**

Run:

```bash
mix ecto.create
mix ecto.migrate
```

Expected: database `atrium_dev` created.

- [ ] **Step 5: Commit**

Nothing to commit unless config changed — skip if `git status` is clean.

---

## Task 2: Add Triplex, Oban, Cloak, and Argon2 dependencies

**Files:**
- Modify: `mix.exs`
- Modify: `config/config.exs`
- Modify: `config/dev.exs`, `config/test.exs`, `config/runtime.exs`

- [ ] **Step 1: Add deps to `mix.exs`**

Edit `mix.exs`, add to the `deps/0` function:

```elixir
{:triplex, "~> 1.3"},
{:oban, "~> 2.18"},
{:cloak, "~> 1.1"},
{:cloak_ecto, "~> 1.3"},
{:argon2_elixir, "~> 4.0"}
```

- [ ] **Step 2: Fetch dependencies**

Run:

```bash
mix deps.get
```

Expected: deps compile.

- [ ] **Step 3: Configure Triplex**

In `config/config.exs`, after the `Atrium.Repo` config block, add:

```elixir
config :triplex,
  repo: Atrium.Repo,
  tenant_prefix: "tenant_",
  migrations_path: "priv/repo/tenant_migrations"
```

- [ ] **Step 4: Configure Oban**

In `config/config.exs`:

```elixir
config :atrium, Oban,
  repo: Atrium.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 10, maintenance: 2, audit: 5]
```

In `config/test.exs`, override Oban to run inline and disable plugins:

```elixir
config :atrium, Oban, testing: :manual
```

- [ ] **Step 5: Configure Cloak vault**

Create `lib/atrium/vault.ex`:

```elixir
defmodule Atrium.Vault do
  use Cloak.Vault, otp_app: :atrium
end
```

In `config/runtime.exs`, inside the `if config_env() == :prod do` block, add:

```elixir
cloak_key =
  System.get_env("ATRIUM_CLOAK_KEY") ||
    raise "ATRIUM_CLOAK_KEY must be set in production (32 bytes, base64-encoded)"

config :atrium, Atrium.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(cloak_key), iv_length: 12}
  ]
```

In `config/dev.exs` and `config/test.exs` add a fixed dev key (not secret — local only):

```elixir
config :atrium, Atrium.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1",
       key: Base.decode64!("rQh7p5xQy9m+Uy8fN5TkLQJ8q8fM1N6lL6K/nHcRzq4="),
       iv_length: 12}
  ]
```

- [ ] **Step 6: Add the vault to supervision**

In `lib/atrium/application.ex`, add `Atrium.Vault` and `{Oban, Application.fetch_env!(:atrium, Oban)}` to the children list before `AtriumWeb.Endpoint`:

```elixir
children = [
  AtriumWeb.Telemetry,
  Atrium.Repo,
  {DNSCluster, query: Application.get_env(:atrium, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: Atrium.PubSub},
  Atrium.Vault,
  {Oban, Application.fetch_env!(:atrium, Oban)},
  AtriumWeb.Endpoint
]
```

- [ ] **Step 7: Compile and verify**

Run:

```bash
mix compile
```

Expected: clean compile, no warnings about missing modules.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: add triplex, oban, cloak, and argon2 dependencies"
```

---

## Task 3: Create public-schema migration for tenants table

**Files:**
- Create: `priv/repo/migrations/<timestamp>_create_tenants.exs`

- [ ] **Step 1: Generate migration**

Run:

```bash
mix ecto.gen.migration create_tenants
```

- [ ] **Step 2: Write the migration**

In the generated file, replace the `change/0` body:

```elixir
defmodule Atrium.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "provisioning"
      add :theme, :map, null: false, default: %{}
      add :enabled_sections, {:array, :string}, null: false, default: []
      add :allow_local_login, :boolean, null: false, default: true
      add :session_idle_timeout_minutes, :integer, null: false, default: 480
      add :session_absolute_timeout_days, :integer, null: false, default: 30
      add :audit_retention_days, :integer, null: false, default: 2555
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenants, [:slug])
    create index(:tenants, [:status])
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
mix ecto.migrate
```

Expected: migration runs, `tenants` table created.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/
git commit -m "feat(tenants): add tenants table migration"
```

---

## Task 4: Tenant Ecto schema and Theme struct

**Files:**
- Create: `lib/atrium/tenants/theme.ex`
- Create: `lib/atrium/tenants/tenant.ex`
- Test: `test/atrium/tenants/theme_test.exs`
- Test: `test/atrium/tenants/tenant_test.exs`

- [ ] **Step 1: Write failing test for Theme defaults**

Create `test/atrium/tenants/theme_test.exs`:

```elixir
defmodule Atrium.Tenants.ThemeTest do
  use ExUnit.Case, async: true
  alias Atrium.Tenants.Theme

  test "default/0 returns all required keys with string values" do
    theme = Theme.default()
    assert is_binary(theme.primary)
    assert is_binary(theme.secondary)
    assert is_binary(theme.accent)
    assert is_binary(theme.font)
    assert theme.logo_url == nil
  end

  test "from_map/1 casts string-keyed map into struct and fills missing with defaults" do
    input = %{"primary" => "#112233", "logo_url" => "https://example.com/logo.svg"}
    theme = Theme.from_map(input)
    assert theme.primary == "#112233"
    assert theme.logo_url == "https://example.com/logo.svg"
    assert theme.secondary == Theme.default().secondary
  end
end
```

- [ ] **Step 2: Run test to see it fail**

```bash
mix test test/atrium/tenants/theme_test.exs
```

Expected: FAIL — `Atrium.Tenants.Theme` module not loaded.

- [ ] **Step 3: Implement Theme**

Create `lib/atrium/tenants/theme.ex`:

```elixir
defmodule Atrium.Tenants.Theme do
  @moduledoc false
  @type t :: %__MODULE__{
          primary: String.t(),
          secondary: String.t(),
          accent: String.t(),
          font: String.t(),
          logo_url: String.t() | nil
        }

  defstruct primary: "#0F172A",
            secondary: "#64748B",
            accent: "#2563EB",
            font: "Inter, system-ui, sans-serif",
            logo_url: nil

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    keys = ~w(primary secondary accent font logo_url)
    defaults = default()

    attrs =
      Enum.reduce(keys, %{}, fn k, acc ->
        val = Map.get(map, k) || Map.get(map, String.to_atom(k)) || Map.get(defaults, String.to_atom(k))
        Map.put(acc, String.to_atom(k), val)
      end)

    struct(__MODULE__, attrs)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
mix test test/atrium/tenants/theme_test.exs
```

Expected: 2 tests pass.

- [ ] **Step 5: Write failing test for Tenant changeset**

Create `test/atrium/tenants/tenant_test.exs`:

```elixir
defmodule Atrium.Tenants.TenantTest do
  use Atrium.DataCase, async: true
  alias Atrium.Tenants.Tenant

  describe "create_changeset/2" do
    test "requires slug, name" do
      changeset = Tenant.create_changeset(%Tenant{}, %{})
      refute changeset.valid?
      assert %{slug: ["can't be blank"], name: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates slug format (lowercase, dashes, no leading/trailing dash)" do
      for bad <- ["MCL", "mcl!", "-mcl", "mcl-", "m__cl"] do
        changeset = Tenant.create_changeset(%Tenant{}, %{slug: bad, name: "x"})
        refute changeset.valid?, "expected #{inspect(bad)} to be invalid"
      end

      for good <- ["mcl", "alldoq", "brand-one", "b1"] do
        changeset = Tenant.create_changeset(%Tenant{}, %{slug: good, name: "x"})
        assert changeset.valid?, "expected #{inspect(good)} to be valid, got #{inspect(errors_on(changeset))}"
      end
    end

    test "defaults status to provisioning" do
      changeset = Tenant.create_changeset(%Tenant{}, %{slug: "mcl", name: "MCL"})
      assert get_field(changeset, :status) == "provisioning"
    end
  end

  describe "update_changeset/2" do
    test "does not allow changing slug" do
      tenant = %Tenant{slug: "mcl", name: "MCL", status: "active"}
      changeset = Tenant.update_changeset(tenant, %{slug: "new"})
      assert get_field(changeset, :slug) == "mcl"
    end

    test "allows updating theme via map" do
      tenant = %Tenant{slug: "mcl", name: "MCL", status: "active"}
      changeset = Tenant.update_changeset(tenant, %{theme: %{"primary" => "#FF0000"}})
      assert changeset.valid?
    end
  end
end
```

- [ ] **Step 6: Ensure `Atrium.DataCase` exists with `errors_on/1` and `get_field/2` helpers**

Verify `test/support/data_case.ex` was generated by `phx.new` (it is by default). If missing, create it with the standard Phoenix `DataCase` contents. Add `import Ecto.Changeset` to its `using` block if not present, so `get_field/2` is available in tests.

- [ ] **Step 7: Run test to see it fail**

```bash
mix test test/atrium/tenants/tenant_test.exs
```

Expected: FAIL — `Atrium.Tenants.Tenant` module not loaded.

- [ ] **Step 8: Implement Tenant schema**

Create `lib/atrium/tenants/tenant.ex`:

```elixir
defmodule Atrium.Tenants.Tenant do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(provisioning active suspended)
  @slug_regex ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "tenants" do
    field :slug, :string
    field :name, :string
    field :status, :string, default: "provisioning"
    field :theme, :map, default: %{}
    field :enabled_sections, {:array, :string}, default: []
    field :allow_local_login, :boolean, default: true
    field :session_idle_timeout_minutes, :integer, default: 480
    field :session_absolute_timeout_days, :integer, default: 30
    field :audit_retention_days, :integer, default: 2555
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [
      :slug,
      :name,
      :theme,
      :enabled_sections,
      :allow_local_login,
      :session_idle_timeout_minutes,
      :session_absolute_timeout_days,
      :audit_retention_days
    ])
    |> validate_required([:slug, :name])
    |> validate_format(:slug, @slug_regex, message: "must be lowercase alphanumeric with dashes")
    |> validate_length(:slug, min: 2, max: 40)
    |> unique_constraint(:slug)
  end

  def update_changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [
      :name,
      :theme,
      :enabled_sections,
      :allow_local_login,
      :session_idle_timeout_minutes,
      :session_absolute_timeout_days,
      :audit_retention_days
    ])
  end

  def status_changeset(tenant, status) when status in @statuses do
    change(tenant, status: status)
  end

  def statuses, do: @statuses
end
```

- [ ] **Step 9: Run test to verify it passes**

```bash
mix test test/atrium/tenants/tenant_test.exs
```

Expected: tests pass.

- [ ] **Step 10: Commit**

```bash
git add lib/atrium/tenants/ test/atrium/tenants/
git commit -m "feat(tenants): add Tenant schema and Theme struct"
```

---

## Task 5: Tenants context (CRUD without provisioning)

**Files:**
- Create: `lib/atrium/tenants.ex`
- Test: `test/atrium/tenants_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/atrium/tenants_test.exs`:

```elixir
defmodule Atrium.TenantsTest do
  use Atrium.DataCase, async: true
  alias Atrium.Tenants
  alias Atrium.Tenants.Tenant

  describe "create_tenant_record/1" do
    test "inserts a tenant with status provisioning" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      assert tenant.status == "provisioning"
      assert tenant.slug == "mcl"
    end

    test "rejects duplicate slug" do
      {:ok, _} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      {:error, changeset} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL2"})
      assert "has already been taken" in errors_on(changeset).slug
    end
  end

  describe "get_tenant_by_slug/1" do
    test "returns tenant when present" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      assert %Tenant{id: id} = Tenants.get_tenant_by_slug("mcl")
      assert id == tenant.id
    end

    test "returns nil when missing" do
      assert Tenants.get_tenant_by_slug("nope") == nil
    end
  end

  describe "update_status/2" do
    test "transitions tenant through statuses" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      {:ok, tenant} = Tenants.update_status(tenant, "active")
      assert tenant.status == "active"
      {:ok, tenant} = Tenants.update_status(tenant, "suspended")
      assert tenant.status == "suspended"
    end
  end

  describe "update_tenant/2" do
    test "updates allowed fields" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      {:ok, updated} = Tenants.update_tenant(tenant, %{name: "MCL Ltd", theme: %{"primary" => "#FF0000"}})
      assert updated.name == "MCL Ltd"
      assert updated.theme["primary"] == "#FF0000"
    end
  end

  describe "list_active_tenants/0" do
    test "returns only active tenants" do
      {:ok, mcl} = Tenants.create_tenant_record(%{slug: "mcl", name: "MCL"})
      {:ok, _} = Tenants.create_tenant_record(%{slug: "alldoq", name: "ALLDOQ"})
      {:ok, _} = Tenants.update_status(mcl, "active")
      slugs = Tenants.list_active_tenants() |> Enum.map(& &1.slug)
      assert slugs == ["mcl"]
    end
  end
end
```

- [ ] **Step 2: Run tests to see them fail**

```bash
mix test test/atrium/tenants_test.exs
```

Expected: FAIL — `Atrium.Tenants` module not loaded.

- [ ] **Step 3: Implement Tenants context**

Create `lib/atrium/tenants.ex`:

```elixir
defmodule Atrium.Tenants do
  @moduledoc """
  Public API for tenant records in the public schema.

  Provisioning (schema creation + seeding) lives in `Atrium.Tenants.Provisioner`.
  """
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Tenants.Tenant

  @spec create_tenant_record(map()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def create_tenant_record(attrs) do
    %Tenant{}
    |> Tenant.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_tenant_by_slug(String.t()) :: Tenant.t() | nil
  def get_tenant_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Tenant, slug: slug)
  end

  @spec get_tenant!(Ecto.UUID.t()) :: Tenant.t()
  def get_tenant!(id), do: Repo.get!(Tenant, id)

  @spec list_tenants() :: [Tenant.t()]
  def list_tenants, do: Repo.all(from t in Tenant, order_by: [asc: t.slug])

  @spec list_active_tenants() :: [Tenant.t()]
  def list_active_tenants do
    Repo.all(from t in Tenant, where: t.status == "active", order_by: [asc: t.slug])
  end

  @spec update_tenant(Tenant.t(), map()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def update_tenant(tenant, attrs) do
    tenant
    |> Tenant.update_changeset(attrs)
    |> Repo.update()
  end

  @spec update_status(Tenant.t(), String.t()) :: {:ok, Tenant.t()} | {:error, term()}
  def update_status(tenant, status) do
    tenant
    |> Tenant.status_changeset(status)
    |> Repo.update()
  end

  @spec change_tenant(Tenant.t(), map()) :: Ecto.Changeset.t()
  def change_tenant(tenant, attrs \\ %{}), do: Tenant.update_changeset(tenant, attrs)
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/atrium/tenants_test.exs
```

Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/tenants.ex test/atrium/tenants_test.exs
git commit -m "feat(tenants): add CRUD context for tenant records"
```

---

## Task 6: Global audit events migration and Audit.GlobalEvent schema

**Files:**
- Create: migration `priv/repo/migrations/<timestamp>_create_audit_events_global.exs`
- Create: `lib/atrium/audit/global_event.ex`
- Create: `lib/atrium/audit.ex`
- Test: `test/atrium/audit_test.exs`

- [ ] **Step 1: Generate migration**

```bash
mix ecto.gen.migration create_audit_events_global
```

- [ ] **Step 2: Write migration body**

```elixir
defmodule Atrium.Repo.Migrations.CreateAuditEventsGlobal do
  use Ecto.Migration

  def change do
    create table(:audit_events_global, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, :binary_id
      add :actor_type, :string, null: false
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :string
      add :changes, :map, null: false, default: %{}
      add :context, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:audit_events_global, [:actor_id, :occurred_at])
    create index(:audit_events_global, [:resource_type, :resource_id, :occurred_at])
    create index(:audit_events_global, [:action, :occurred_at])
  end
end
```

Run `mix ecto.migrate`.

- [ ] **Step 3: Write failing test for Audit.log_global/2**

Create `test/atrium/audit_test.exs`:

```elixir
defmodule Atrium.AuditTest do
  use Atrium.DataCase, async: true
  alias Atrium.Audit

  describe "log_global/2" do
    test "writes a row with action, actor, changes, context" do
      {:ok, event} =
        Audit.log_global("tenant.created", %{
          actor: {:super_admin, "11111111-1111-1111-1111-111111111111"},
          resource: {"Tenant", "abc-123"},
          changes: %{"slug" => [nil, "mcl"]},
          context: %{"request_id" => "req-1"}
        })

      assert event.action == "tenant.created"
      assert event.actor_type == "super_admin"
      assert event.actor_id == "11111111-1111-1111-1111-111111111111"
      assert event.resource_type == "Tenant"
      assert event.resource_id == "abc-123"
      assert event.changes == %{"slug" => [nil, "mcl"]}
      assert event.context == %{"request_id" => "req-1"}
      assert event.occurred_at
    end

    test "supports system actor" do
      {:ok, event} = Audit.log_global("system.heartbeat", %{actor: :system})
      assert event.actor_type == "system"
      assert event.actor_id == nil
    end

    test "requires an action" do
      assert_raise ArgumentError, fn -> Audit.log_global(nil, %{}) end
    end
  end

  describe "list_global/1" do
    test "filters by action and paginates" do
      for i <- 1..3 do
        {:ok, _} = Audit.log_global("tenant.created", %{actor: :system, resource: {"Tenant", "id-#{i}"}})
      end

      {:ok, _} = Audit.log_global("tenant.suspended", %{actor: :system, resource: {"Tenant", "id-1"}})

      events = Audit.list_global(action: "tenant.created")
      assert length(events) == 3
      assert Enum.all?(events, &(&1.action == "tenant.created"))
    end
  end
end
```

- [ ] **Step 4: Run test, confirm it fails**

```bash
mix test test/atrium/audit_test.exs
```

Expected: FAIL — module not loaded.

- [ ] **Step 5: Implement GlobalEvent schema**

Create `lib/atrium/audit/global_event.ex`:

```elixir
defmodule Atrium.Audit.GlobalEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "audit_events_global" do
    field :actor_id, :binary_id
    field :actor_type, :string
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :changes, :map, default: %{}
    field :context, :map, default: %{}
    field :occurred_at, :utc_datetime_usec
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:actor_id, :actor_type, :action, :resource_type, :resource_id, :changes, :context, :occurred_at])
    |> validate_required([:actor_type, :action, :occurred_at])
  end
end
```

- [ ] **Step 6: Implement Audit context**

Create `lib/atrium/audit.ex`:

```elixir
defmodule Atrium.Audit do
  @moduledoc """
  Append-only audit logging.

  Phase 0a exposes `log_global/2` and `list_global/1` for public-schema events.
  Tenant-scoped `log/2` and `list/1` are added in plan 0e.
  """
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit.GlobalEvent

  @type actor ::
          :system
          | {:super_admin, Ecto.UUID.t()}
          | {:user, Ecto.UUID.t()}

  @spec log_global(String.t(), map()) :: {:ok, GlobalEvent.t()} | {:error, Ecto.Changeset.t()}
  def log_global(action, opts) when is_binary(action) do
    {actor_type, actor_id} = decode_actor(Map.get(opts, :actor, :system))
    {resource_type, resource_id} = decode_resource(Map.get(opts, :resource))

    attrs = %{
      actor_type: actor_type,
      actor_id: actor_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      changes: stringify_keys(Map.get(opts, :changes, %{})),
      context: stringify_keys(Map.get(opts, :context, %{})),
      occurred_at: DateTime.utc_now()
    }

    %GlobalEvent{}
    |> GlobalEvent.changeset(attrs)
    |> Repo.insert()
  end

  def log_global(nil, _opts), do: raise(ArgumentError, "action is required")

  @spec list_global(keyword()) :: [GlobalEvent.t()]
  def list_global(filters \\ []) do
    query = from e in GlobalEvent, order_by: [desc: e.occurred_at]

    Enum.reduce(filters, query, fn
      {:action, action}, q -> where(q, [e], e.action == ^action)
      {:actor_id, id}, q -> where(q, [e], e.actor_id == ^id)
      {:resource_type, t}, q -> where(q, [e], e.resource_type == ^t)
      {:resource_id, id}, q -> where(q, [e], e.resource_id == ^id)
      {:limit, n}, q -> limit(q, ^n)
      _, q -> q
    end)
    |> Repo.all()
  end

  defp decode_actor(:system), do: {"system", nil}
  defp decode_actor({:super_admin, id}) when is_binary(id), do: {"super_admin", id}
  defp decode_actor({:user, id}) when is_binary(id), do: {"user", id}

  defp decode_resource(nil), do: {nil, nil}
  defp decode_resource({type, id}) when is_binary(type), do: {type, to_string(id)}

  defp stringify_keys(map) when is_map(map) do
    for {k, v} <- map, into: %{}, do: {to_string(k), v}
  end
end
```

- [ ] **Step 7: Run tests to verify**

```bash
mix test test/atrium/audit_test.exs
```

Expected: 4 tests pass.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(audit): add global audit_events table and Audit.log_global"
```

---

## Task 7: SuperAdmin schema, migration, and context

**Files:**
- Create: migration `priv/repo/migrations/<timestamp>_create_super_admins.exs`
- Create: `lib/atrium/super_admins/super_admin.ex`
- Create: `lib/atrium/super_admins.ex`
- Test: `test/atrium/super_admins_test.exs`

- [ ] **Step 1: Generate and write migration**

```bash
mix ecto.gen.migration create_super_admins
```

```elixir
defmodule Atrium.Repo.Migrations.CreateSuperAdmins do
  use Ecto.Migration

  def change do
    create table(:super_admins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :name, :string, null: false
      add :hashed_password, :string, null: false
      add :status, :string, null: false, default: "active"
      add :last_login_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:super_admins, [:email])
  end
end
```

Note: `citext` requires the extension. Add an earlier migration if not present:

```bash
mix ecto.gen.migration enable_citext
```

With body:

```elixir
defmodule Atrium.Repo.Migrations.EnableCitext do
  use Ecto.Migration
  def change, do: execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"
end
```

Ensure the citext migration runs before `create_super_admins` (it will, since it's generated first).

Run `mix ecto.migrate`.

- [ ] **Step 2: Write failing tests**

Create `test/atrium/super_admins_test.exs`:

```elixir
defmodule Atrium.SuperAdminsTest do
  use Atrium.DataCase, async: true
  alias Atrium.SuperAdmins
  alias Atrium.SuperAdmins.SuperAdmin

  describe "create_super_admin/1" do
    test "creates a super admin with a hashed password" do
      {:ok, sa} = SuperAdmins.create_super_admin(%{email: "ops@atrium.example", name: "Ops", password: "correct-horse-battery-staple"})
      assert sa.hashed_password
      refute sa.hashed_password == "correct-horse-battery-staple"
    end

    test "rejects short passwords" do
      {:error, cs} = SuperAdmins.create_super_admin(%{email: "a@b.co", name: "A", password: "short"})
      refute cs.valid?
      assert %{password: [_ | _]} = errors_on(cs)
    end

    test "rejects duplicate email case-insensitively" do
      {:ok, _} = SuperAdmins.create_super_admin(%{email: "Ops@atrium.example", name: "Ops", password: "correct-horse-battery-staple"})
      {:error, cs} = SuperAdmins.create_super_admin(%{email: "ops@atrium.example", name: "Ops2", password: "correct-horse-battery-staple"})
      assert "has already been taken" in errors_on(cs).email
    end
  end

  describe "authenticate/2" do
    setup do
      {:ok, sa} = SuperAdmins.create_super_admin(%{email: "ops@atrium.example", name: "Ops", password: "correct-horse-battery-staple"})
      {:ok, sa: sa}
    end

    test "returns {:ok, sa} on correct password", %{sa: sa} do
      assert {:ok, found} = SuperAdmins.authenticate("ops@atrium.example", "correct-horse-battery-staple")
      assert found.id == sa.id
    end

    test "returns {:error, :invalid_credentials} on wrong password" do
      assert {:error, :invalid_credentials} = SuperAdmins.authenticate("ops@atrium.example", "wrong")
    end

    test "returns {:error, :invalid_credentials} for unknown email" do
      assert {:error, :invalid_credentials} = SuperAdmins.authenticate("nope@atrium.example", "whatever")
    end

    test "returns {:error, :suspended} when status is suspended", %{sa: sa} do
      {:ok, _} = SuperAdmins.update_status(sa, "suspended")
      assert {:error, :suspended} = SuperAdmins.authenticate("ops@atrium.example", "correct-horse-battery-staple")
    end
  end
end
```

- [ ] **Step 3: Run to fail**

```bash
mix test test/atrium/super_admins_test.exs
```

Expected: FAIL — modules missing.

- [ ] **Step 4: Implement SuperAdmin schema**

Create `lib/atrium/super_admins/super_admin.ex`:

```elixir
defmodule Atrium.SuperAdmins.SuperAdmin do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "super_admins" do
    field :email, :string
    field :name, :string
    field :hashed_password, :string
    field :status, :string, default: "active"
    field :last_login_at, :utc_datetime_usec
    field :password, :string, virtual: true, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(sa, attrs) do
    sa
    |> cast(attrs, [:email, :name, :password])
    |> validate_required([:email, :name, :password])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    |> validate_length(:password, min: 16, max: 128)
    |> unique_constraint(:email)
    |> put_hashed_password()
  end

  def status_changeset(sa, status) when status in ~w(active suspended) do
    change(sa, status: status)
  end

  def last_login_changeset(sa, at) do
    change(sa, last_login_at: at)
  end

  defp put_hashed_password(%Ecto.Changeset{valid?: true, changes: %{password: pw}} = cs) do
    cs
    |> put_change(:hashed_password, Argon2.hash_pwd_salt(pw))
    |> delete_change(:password)
  end

  defp put_hashed_password(cs), do: cs
end
```

- [ ] **Step 5: Implement SuperAdmins context**

Create `lib/atrium/super_admins.ex`:

```elixir
defmodule Atrium.SuperAdmins do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.SuperAdmins.SuperAdmin

  @spec create_super_admin(map()) :: {:ok, SuperAdmin.t()} | {:error, Ecto.Changeset.t()}
  def create_super_admin(attrs) do
    %SuperAdmin{}
    |> SuperAdmin.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_super_admin!(Ecto.UUID.t()) :: SuperAdmin.t()
  def get_super_admin!(id), do: Repo.get!(SuperAdmin, id)

  @spec authenticate(String.t(), String.t()) ::
          {:ok, SuperAdmin.t()} | {:error, :invalid_credentials | :suspended}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    sa = Repo.one(from s in SuperAdmin, where: fragment("lower(?)", s.email) == ^String.downcase(email))

    cond do
      is_nil(sa) ->
        Argon2.no_user_verify()
        {:error, :invalid_credentials}

      not Argon2.verify_pass(password, sa.hashed_password) ->
        {:error, :invalid_credentials}

      sa.status != "active" ->
        {:error, :suspended}

      true ->
        {:ok, record_login!(sa)}
    end
  end

  def update_status(%SuperAdmin{} = sa, status) do
    sa |> SuperAdmin.status_changeset(status) |> Repo.update()
  end

  defp record_login!(sa) do
    sa |> SuperAdmin.last_login_changeset(DateTime.utc_now()) |> Repo.update!()
  end
end
```

- [ ] **Step 6: Run tests**

```bash
mix test test/atrium/super_admins_test.exs
```

Expected: 7 tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(super_admins): add schema, context, and local authentication"
```

---

## Task 8: Tenant provisioner (Triplex schema creation + tenant lifecycle)

**Files:**
- Create: `lib/atrium/tenants/provisioner.ex`
- Test: `test/atrium/tenants/provisioner_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/atrium/tenants/provisioner_test.exs`:

```elixir
defmodule Atrium.Tenants.ProvisionerTest do
  use Atrium.DataCase, async: false
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup do
    on_exit(fn ->
      # Clean up any tenant schemas created by tests
      for slug <- ~w(pr-test-mcl pr-test-fail) do
        _ = Triplex.drop(slug)
      end
    end)

    :ok
  end

  describe "provision/1" do
    test "creates tenant schema and marks tenant active" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "pr-test-mcl", name: "MCL"})
      assert {:ok, provisioned} = Provisioner.provision(tenant)
      assert provisioned.status == "active"
      assert "tenant_pr-test-mcl" in Triplex.all()
    end

    test "writes audit_events_global entry on success" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "pr-test-mcl", name: "MCL"})
      {:ok, _} = Provisioner.provision(tenant)

      events = Atrium.Audit.list_global(action: "tenant.created")
      assert Enum.any?(events, fn e -> e.resource_id == tenant.id end)
    end

    test "rolls back tenant status when schema creation fails" do
      # Slugs with dashes work for Triplex; craft a failure by pre-creating the schema
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "pr-test-fail", name: "Fail"})
      Triplex.create("pr-test-fail")

      assert {:error, _reason} = Provisioner.provision(tenant)
      refreshed = Tenants.get_tenant!(tenant.id)
      assert refreshed.status == "provisioning"
    end
  end

  describe "suspend/1 and resume/1" do
    test "transitions an active tenant and audits both events" do
      {:ok, tenant} = Tenants.create_tenant_record(%{slug: "pr-test-mcl", name: "MCL"})
      {:ok, tenant} = Provisioner.provision(tenant)

      {:ok, suspended} = Provisioner.suspend(tenant)
      assert suspended.status == "suspended"

      {:ok, resumed} = Provisioner.resume(suspended)
      assert resumed.status == "active"

      actions = Atrium.Audit.list_global() |> Enum.map(& &1.action) |> Enum.uniq()
      assert "tenant.suspended" in actions
      assert "tenant.resumed" in actions
    end
  end
end
```

- [ ] **Step 2: Run to fail**

```bash
mix test test/atrium/tenants/provisioner_test.exs
```

Expected: FAIL — `Atrium.Tenants.Provisioner` not loaded.

- [ ] **Step 3: Implement Provisioner**

Create `lib/atrium/tenants/provisioner.ex`:

```elixir
defmodule Atrium.Tenants.Provisioner do
  @moduledoc """
  Creates and tears down per-tenant schemas via Triplex, and keeps the public
  tenant record in sync. Always writes to `audit_events_global`.
  """
  alias Atrium.{Audit, Repo, Tenants}
  alias Atrium.Tenants.Tenant

  @spec provision(Tenant.t(), keyword()) :: {:ok, Tenant.t()} | {:error, term()}
  def provision(%Tenant{} = tenant, opts \\ []) do
    actor = Keyword.get(opts, :actor, :system)

    case Triplex.create(tenant.slug) do
      {:ok, _schema} ->
        case Tenants.update_status(tenant, "active") do
          {:ok, updated} ->
            {:ok, _} =
              Audit.log_global("tenant.created", %{
                actor: actor,
                resource: {"Tenant", tenant.id},
                changes: %{"slug" => [nil, tenant.slug], "status" => ["provisioning", "active"]}
              })

            {:ok, updated}

          {:error, reason} ->
            _ = Triplex.drop(tenant.slug)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec suspend(Tenant.t(), keyword()) :: {:ok, Tenant.t()} | {:error, term()}
  def suspend(%Tenant{status: "active"} = tenant, opts \\ []) do
    actor = Keyword.get(opts, :actor, :system)

    with {:ok, updated} <- Tenants.update_status(tenant, "suspended") do
      {:ok, _} =
        Audit.log_global("tenant.suspended", %{
          actor: actor,
          resource: {"Tenant", tenant.id},
          changes: %{"status" => ["active", "suspended"]}
        })

      {:ok, updated}
    end
  end

  def suspend(%Tenant{} = tenant, _), do: {:error, {:invalid_status_transition, tenant.status, "suspended"}}

  @spec resume(Tenant.t(), keyword()) :: {:ok, Tenant.t()} | {:error, term()}
  def resume(%Tenant{status: "suspended"} = tenant, opts \\ []) do
    actor = Keyword.get(opts, :actor, :system)

    with {:ok, updated} <- Tenants.update_status(tenant, "active") do
      {:ok, _} =
        Audit.log_global("tenant.resumed", %{
          actor: actor,
          resource: {"Tenant", tenant.id},
          changes: %{"status" => ["suspended", "active"]}
        })

      {:ok, updated}
    end
  end

  def resume(%Tenant{} = tenant, _), do: {:error, {:invalid_status_transition, tenant.status, "active"}}

  @spec destroy(Tenant.t()) :: :ok | {:error, term()}
  def destroy(%Tenant{} = tenant) do
    with {:ok, _} <- Triplex.drop(tenant.slug),
         {:ok, _} <- Repo.delete(tenant) do
      :ok
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/atrium/tenants/provisioner_test.exs
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(tenants): add Provisioner (schema create, suspend, resume) with audit"
```

---

## Task 9: Mix task `atrium.provision_tenant`

**Files:**
- Create: `lib/mix/tasks/atrium.provision_tenant.ex`
- Test: `test/mix/tasks/provision_tenant_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/mix/tasks/provision_tenant_test.exs`:

```elixir
defmodule Mix.Tasks.Atrium.ProvisionTenantTest do
  use Atrium.DataCase, async: false
  alias Atrium.Tenants

  setup do
    on_exit(fn -> _ = Triplex.drop("task-test-mcl") end)
    :ok
  end

  test "creates and provisions a tenant from CLI args" do
    Mix.Tasks.Atrium.ProvisionTenant.run(["--slug", "task-test-mcl", "--name", "MCL"])

    tenant = Tenants.get_tenant_by_slug("task-test-mcl")
    assert tenant
    assert tenant.status == "active"
    assert "tenant_task-test-mcl" in Triplex.all()
  end

  test "exits with non-zero status on invalid slug" do
    assert_raise Mix.Error, ~r/invalid/i, fn ->
      Mix.Tasks.Atrium.ProvisionTenant.run(["--slug", "INVALID", "--name", "x"])
    end
  end
end
```

- [ ] **Step 2: Run to fail**

```bash
mix test test/mix/tasks/provision_tenant_test.exs
```

Expected: FAIL — task not defined.

- [ ] **Step 3: Implement task**

Create `lib/mix/tasks/atrium.provision_tenant.ex`:

```elixir
defmodule Mix.Tasks.Atrium.ProvisionTenant do
  @shortdoc "Provision a new tenant: create public record and tenant schema"
  @moduledoc """
  Usage:

      mix atrium.provision_tenant --slug mcl --name "MCL"
  """
  use Mix.Task

  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [slug: :string, name: :string])

    slug = Keyword.get(opts, :slug) || Mix.raise("--slug is required")
    name = Keyword.get(opts, :name) || Mix.raise("--name is required")

    case Tenants.create_tenant_record(%{slug: slug, name: name}) do
      {:ok, tenant} ->
        case Provisioner.provision(tenant) do
          {:ok, provisioned} ->
            Mix.shell().info("Provisioned tenant #{provisioned.slug} (#{provisioned.id})")

          {:error, reason} ->
            Mix.raise("Failed to provision: #{inspect(reason)}")
        end

      {:error, changeset} ->
        Mix.raise("Invalid tenant attrs: #{inspect(errors(changeset))}")
    end
  end

  defp errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/mix/tasks/provision_tenant_test.exs
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(tenants): add mix atrium.provision_tenant task"
```

---

## Task 10: Tenant resolver plug

**Files:**
- Create: `lib/atrium_web/plugs/tenant_resolver.ex`
- Test: `test/atrium_web/plugs/tenant_resolver_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/atrium_web/plugs/tenant_resolver_test.exs`:

```elixir
defmodule AtriumWeb.Plugs.TenantResolverTest do
  use AtriumWeb.ConnCase, async: false
  alias AtriumWeb.Plugs.TenantResolver
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup do
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: "resolver-test", name: "Test"})
    {:ok, tenant} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop("resolver-test") end)
    {:ok, tenant: tenant}
  end

  describe "call/2" do
    test "resolves tenant by subdomain and assigns tenant + prefix", %{conn: conn, tenant: tenant} do
      conn =
        conn
        |> Map.put(:host, "resolver-test.atrium.example")
        |> TenantResolver.call([])

      assert conn.assigns.tenant.id == tenant.id
      assert conn.assigns.tenant_prefix == Triplex.to_prefix("resolver-test")
    end

    test "returns 404 for unknown subdomain", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "nope.atrium.example")
        |> TenantResolver.call([])

      assert conn.status == 404
      assert conn.halted
    end

    test "returns 503 for suspended tenant", %{conn: conn, tenant: tenant} do
      {:ok, _} = Provisioner.suspend(tenant)

      conn =
        conn
        |> Map.put(:host, "resolver-test.atrium.example")
        |> TenantResolver.call([])

      assert conn.status == 503
      assert conn.halted
    end

    test "ignores platform host (admin.*)" do
      # Platform host should never reach the resolver; test that if it does,
      # it halts with a clear error.
      conn = Phoenix.ConnTest.build_conn(:get, "/")
      conn = Map.put(conn, :host, "admin.atrium.example")
      conn = TenantResolver.call(conn, [])
      assert conn.halted
      assert conn.status in [400, 404]
    end
  end
end
```

- [ ] **Step 2: Run to fail**

```bash
mix test test/atrium_web/plugs/tenant_resolver_test.exs
```

Expected: FAIL.

- [ ] **Step 3: Implement plug**

Create `lib/atrium_web/plugs/tenant_resolver.ex`:

```elixir
defmodule AtriumWeb.Plugs.TenantResolver do
  @moduledoc """
  Resolves the tenant from the request host's leading subdomain, loads the
  tenant record, rejects suspended/missing tenants, and sets the Triplex
  prefix for the request.

  This plug MUST NOT be mounted on platform-admin routes; those routes run
  under a separate pipeline that never sets a tenant prefix.
  """
  import Plug.Conn
  alias Atrium.Tenants

  @platform_subdomains ~w(admin www)

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, slug} <- extract_slug(conn.host),
         %Tenants.Tenant{} = tenant <- Tenants.get_tenant_by_slug(slug) do
      handle_tenant(conn, tenant)
    else
      :platform_host ->
        conn
        |> send_resp(400, "Platform host cannot serve tenant routes")
        |> halt()

      :no_subdomain ->
        conn
        |> send_resp(400, "Missing tenant subdomain")
        |> halt()

      nil ->
        conn
        |> send_resp(404, "Unknown tenant")
        |> halt()
    end
  end

  defp extract_slug(host) do
    case String.split(host, ".", parts: 2) do
      [sub, _rest] when sub in @platform_subdomains -> :platform_host
      [sub, _rest] when sub != "" -> {:ok, sub}
      _ -> :no_subdomain
    end
  end

  defp handle_tenant(conn, %{status: "active"} = tenant) do
    conn
    |> assign(:tenant, tenant)
    |> assign(:tenant_prefix, Triplex.to_prefix(tenant.slug))
  end

  defp handle_tenant(conn, %{status: "suspended"}) do
    conn |> send_resp(503, "Tenant suspended") |> halt()
  end

  defp handle_tenant(conn, %{status: "provisioning"}) do
    conn |> send_resp(503, "Tenant provisioning") |> halt()
  end
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/atrium_web/plugs/tenant_resolver_test.exs
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(web): add TenantResolver plug for subdomain-based tenant resolution"
```

---

## Task 11: Router split + super-admin pipeline + health endpoint

**Files:**
- Modify: `lib/atrium_web/router.ex`
- Modify: `lib/atrium_web/endpoint.ex` (no change expected, just verify)
- Create: `lib/atrium_web/controllers/health_controller.ex`
- Create: `lib/atrium_web/controllers/page_controller.ex` (replace the generated one if a stub isn't useful)
- Create: `lib/atrium_web/plugs/require_super_admin.ex`
- Test: `test/atrium_web/controllers/health_controller_test.exs`

- [ ] **Step 1: Write failing test for health endpoint**

Create `test/atrium_web/controllers/health_controller_test.exs`:

```elixir
defmodule AtriumWeb.HealthControllerTest do
  use AtriumWeb.ConnCase, async: true

  test "GET /healthz returns 200 with JSON status", %{conn: conn} do
    conn = get(Map.put(conn, :host, "admin.atrium.example"), "/healthz")
    assert json_response(conn, 200)["status"] == "ok"
  end
end
```

- [ ] **Step 2: Implement HealthController**

Create `lib/atrium_web/controllers/health_controller.ex`:

```elixir
defmodule AtriumWeb.HealthController do
  use AtriumWeb, :controller

  def index(conn, _params) do
    tenants = length(Atrium.Tenants.list_active_tenants())
    json(conn, %{status: "ok", active_tenants: tenants, time: DateTime.utc_now()})
  end
end
```

- [ ] **Step 3: Implement RequireSuperAdmin plug**

Create `lib/atrium_web/plugs/require_super_admin.ex`:

```elixir
defmodule AtriumWeb.Plugs.RequireSuperAdmin do
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :super_admin_id) do
      nil ->
        conn |> redirect(to: "/super/login") |> halt()

      id ->
        case Atrium.SuperAdmins.get_super_admin!(id) do
          %{status: "active"} = sa -> assign(conn, :super_admin, sa)
          _ -> conn |> clear_session() |> redirect(to: "/super/login") |> halt()
        end
    end
  end
end
```

- [ ] **Step 4: Wire routes**

Replace `lib/atrium_web/router.ex` with:

```elixir
defmodule AtriumWeb.Router do
  use AtriumWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AtriumWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :tenant do
    plug AtriumWeb.Plugs.TenantResolver
  end

  pipeline :super_admin_required do
    plug AtriumWeb.Plugs.RequireSuperAdmin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Platform (super-admin) routes — must match BEFORE the tenant-scoped scope
  # by virtue of the host guard.
  scope "/", AtriumWeb, host: ["admin."] do
    pipe_through [:browser]
    get "/super/login", SuperAdmin.SessionController, :new
    post "/super/login", SuperAdmin.SessionController, :create
    delete "/super/logout", SuperAdmin.SessionController, :delete

    scope "/super", as: :super_admin do
      pipe_through [:super_admin_required]
      get "/", SuperAdmin.DashboardController, :index
      resources "/tenants", SuperAdmin.TenantController, except: [:delete]
    end
  end

  # Health endpoint on platform host
  scope "/", AtriumWeb, host: ["admin."] do
    pipe_through [:api]
    get "/healthz", HealthController, :index
  end

  # Tenant-scoped routes (any other host)
  scope "/", AtriumWeb do
    pipe_through [:browser, :tenant]
    get "/", PageController, :home
  end
end
```

- [ ] **Step 5: Update generated PageController if needed**

If `lib/atrium_web/controllers/page_controller.ex` does not exist or returns the default scaffold, overwrite with:

```elixir
defmodule AtriumWeb.PageController do
  use AtriumWeb, :controller

  def home(conn, _params) do
    render(conn, :home, tenant: conn.assigns.tenant)
  end
end
```

And create the corresponding template `lib/atrium_web/controllers/page_html/home.html.heex`:

```heex
<main class="p-8">
  <h1 class="text-2xl font-semibold"><%= @tenant.name %></h1>
  <p class="text-gray-500">Atrium tenant <%= @tenant.slug %> — Phase 0a skeleton</p>
</main>
```

(ensure `lib/atrium_web/controllers/page_html.ex` exists via `use AtriumWeb, :html` + `embed_templates "page_html/*"`.)

- [ ] **Step 6: Run health test**

```bash
mix test test/atrium_web/controllers/health_controller_test.exs
```

Expected: 1 test passes.

- [ ] **Step 7: Start server and smoke-test**

In one shell:

```bash
mix phx.server
```

In another:

```bash
curl -s -H "Host: admin.atrium.example" http://localhost:4000/healthz | jq
```

Expected: JSON body with `"status":"ok"`.

Stop the server.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(web): add router split, super-admin pipeline, and health endpoint"
```

---

## Task 12: Super-admin session controller (login/logout)

**Files:**
- Create: `lib/atrium_web/controllers/super_admin/session_controller.ex`
- Create: `lib/atrium_web/controllers/super_admin/session_html.ex` + `session_html/new.html.heex`
- Create: `lib/atrium_web/controllers/super_admin/dashboard_controller.ex` + template
- Test: `test/atrium_web/controllers/super_admin/session_controller_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/atrium_web/controllers/super_admin/session_controller_test.exs`:

```elixir
defmodule AtriumWeb.SuperAdmin.SessionControllerTest do
  use AtriumWeb.ConnCase, async: true
  alias Atrium.SuperAdmins

  setup %{conn: conn} do
    {:ok, sa} =
      SuperAdmins.create_super_admin(%{
        email: "ops@atrium.example",
        name: "Ops",
        password: "correct-horse-battery-staple"
      })

    conn = Map.put(conn, :host, "admin.atrium.example")
    {:ok, conn: conn, sa: sa}
  end

  test "GET /super/login renders the form", %{conn: conn} do
    conn = get(conn, "/super/login")
    assert html_response(conn, 200) =~ "Sign in"
  end

  test "POST /super/login with correct credentials redirects to dashboard and sets session", %{conn: conn, sa: sa} do
    conn = post(conn, "/super/login", %{"email" => "ops@atrium.example", "password" => "correct-horse-battery-staple"})
    assert redirected_to(conn) == "/super"
    assert get_session(conn, :super_admin_id) == sa.id
  end

  test "POST /super/login with wrong password renders form with error", %{conn: conn} do
    conn = post(conn, "/super/login", %{"email" => "ops@atrium.example", "password" => "nope"})
    assert html_response(conn, 200) =~ "Invalid"
    refute get_session(conn, :super_admin_id)
  end

  test "writes audit event on login success", %{conn: conn, sa: sa} do
    post(conn, "/super/login", %{"email" => "ops@atrium.example", "password" => "correct-horse-battery-staple"})
    events = Atrium.Audit.list_global(action: "super_admin.login")
    assert Enum.any?(events, fn e -> e.actor_id == sa.id end)
  end

  test "writes audit event on login failure", %{conn: conn} do
    post(conn, "/super/login", %{"email" => "ops@atrium.example", "password" => "wrong"})
    events = Atrium.Audit.list_global(action: "super_admin.login_failed")
    assert Enum.any?(events)
  end

  test "DELETE /super/logout clears the session", %{conn: conn, sa: sa} do
    conn = conn |> init_test_session(%{super_admin_id: sa.id})
    conn = delete(conn, "/super/logout")
    assert redirected_to(conn) == "/super/login"
    refute get_session(conn, :super_admin_id)
  end
end
```

- [ ] **Step 2: Run to fail**

```bash
mix test test/atrium_web/controllers/super_admin/session_controller_test.exs
```

Expected: FAIL.

- [ ] **Step 3: Implement SessionController**

Create `lib/atrium_web/controllers/super_admin/session_controller.ex`:

```elixir
defmodule AtriumWeb.SuperAdmin.SessionController do
  use AtriumWeb, :controller

  alias Atrium.{Audit, SuperAdmins}

  def new(conn, _params) do
    render(conn, :new, error: nil, email: "")
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case SuperAdmins.authenticate(email, password) do
      {:ok, sa} ->
        {:ok, _} =
          Audit.log_global("super_admin.login", %{
            actor: {:super_admin, sa.id},
            resource: {"SuperAdmin", sa.id},
            context: request_context(conn)
          })

        conn
        |> renew_session()
        |> put_session(:super_admin_id, sa.id)
        |> redirect(to: "/super")

      {:error, reason} ->
        {:ok, _} =
          Audit.log_global("super_admin.login_failed", %{
            actor: :system,
            context: Map.merge(request_context(conn), %{"email" => email, "reason" => to_string(reason)})
          })

        conn
        |> put_status(:ok)
        |> render(:new, error: "Invalid credentials", email: email)
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/super/login")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp request_context(conn) do
    %{
      "ip" => conn.remote_ip |> :inet.ntoa() |> to_string(),
      "user_agent" => get_req_header(conn, "user-agent") |> List.first() || ""
    }
  end
end
```

- [ ] **Step 4: Create view + template**

Create `lib/atrium_web/controllers/super_admin/session_html.ex`:

```elixir
defmodule AtriumWeb.SuperAdmin.SessionHTML do
  use AtriumWeb, :html
  embed_templates "session_html/*"
end
```

Create `lib/atrium_web/controllers/super_admin/session_html/new.html.heex`:

```heex
<main class="max-w-sm mx-auto py-16">
  <h1 class="text-2xl font-semibold mb-6">Sign in</h1>

  <%= if @error do %>
    <div class="mb-4 rounded bg-red-50 text-red-700 p-3"><%= @error %></div>
  <% end %>

  <.form :let={_f} for={%{}} as={:auth} action={~p"/super/login"} method="post" class="space-y-4">
    <div>
      <label class="block text-sm">Email</label>
      <input type="email" name="email" value={@email} class="mt-1 w-full border rounded p-2" required />
    </div>
    <div>
      <label class="block text-sm">Password</label>
      <input type="password" name="password" class="mt-1 w-full border rounded p-2" required />
    </div>
    <button type="submit" class="w-full rounded bg-slate-900 text-white p-2">Sign in</button>
  </.form>
</main>
```

- [ ] **Step 5: Implement DashboardController stub**

Create `lib/atrium_web/controllers/super_admin/dashboard_controller.ex`:

```elixir
defmodule AtriumWeb.SuperAdmin.DashboardController do
  use AtriumWeb, :controller

  def index(conn, _params) do
    render(conn, :index, super_admin: conn.assigns.super_admin, tenants: Atrium.Tenants.list_tenants())
  end
end
```

Create `lib/atrium_web/controllers/super_admin/dashboard_html.ex`:

```elixir
defmodule AtriumWeb.SuperAdmin.DashboardHTML do
  use AtriumWeb, :html
  embed_templates "dashboard_html/*"
end
```

Create `lib/atrium_web/controllers/super_admin/dashboard_html/index.html.heex`:

```heex
<main class="p-8">
  <h1 class="text-2xl font-semibold">Atrium — Platform</h1>
  <p class="text-gray-600">Signed in as <%= @super_admin.email %></p>

  <section class="mt-6">
    <h2 class="text-lg font-medium mb-2">Tenants</h2>
    <.link navigate={~p"/super/tenants/new"} class="inline-block mb-4 rounded bg-slate-900 text-white px-3 py-1">New tenant</.link>
    <ul class="divide-y border rounded">
      <%= for t <- @tenants do %>
        <li class="p-3 flex justify-between">
          <span><%= t.slug %> — <%= t.name %></span>
          <span class="text-sm text-gray-500"><%= t.status %></span>
        </li>
      <% end %>
    </ul>
  </section>
</main>
```

- [ ] **Step 6: Run tests**

```bash
mix test test/atrium_web/controllers/super_admin/session_controller_test.exs
```

Expected: 6 tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(super_admin): add session controller, login flow, and dashboard stub"
```

---

## Task 13: Super-admin tenant CRUD controller

**Files:**
- Create: `lib/atrium_web/controllers/super_admin/tenant_controller.ex` + html view + templates
- Test: `test/atrium_web/controllers/super_admin/tenant_controller_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/atrium_web/controllers/super_admin/tenant_controller_test.exs`:

```elixir
defmodule AtriumWeb.SuperAdmin.TenantControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.SuperAdmins
  alias Atrium.Tenants

  setup %{conn: conn} do
    {:ok, sa} =
      SuperAdmins.create_super_admin(%{
        email: "ops@atrium.example",
        name: "Ops",
        password: "correct-horse-battery-staple"
      })

    conn =
      conn
      |> Map.put(:host, "admin.atrium.example")
      |> init_test_session(%{super_admin_id: sa.id})

    on_exit(fn ->
      for slug <- ~w(controller-test-mcl) do
        _ = Triplex.drop(slug)
      end
    end)

    {:ok, conn: conn, sa: sa}
  end

  test "index lists tenants", %{conn: conn} do
    {:ok, _} = Tenants.create_tenant_record(%{slug: "controller-test-mcl", name: "MCL"})
    conn = get(conn, "/super/tenants")
    assert html_response(conn, 200) =~ "controller-test-mcl"
  end

  test "POST /super/tenants creates and provisions", %{conn: conn} do
    conn =
      post(conn, "/super/tenants", %{
        "tenant" => %{"slug" => "controller-test-mcl", "name" => "MCL"}
      })

    assert redirected_to(conn) =~ "/super/tenants/"
    assert %{status: "active"} = Tenants.get_tenant_by_slug("controller-test-mcl")
  end

  test "POST /super/tenants renders form with errors on invalid slug", %{conn: conn} do
    conn =
      post(conn, "/super/tenants", %{
        "tenant" => %{"slug" => "INVALID", "name" => "x"}
      })

    assert html_response(conn, 200) =~ "lowercase"
  end
end
```

- [ ] **Step 2: Implement controller**

Create `lib/atrium_web/controllers/super_admin/tenant_controller.ex`:

```elixir
defmodule AtriumWeb.SuperAdmin.TenantController do
  use AtriumWeb, :controller

  alias Atrium.Tenants
  alias Atrium.Tenants.{Provisioner, Tenant}

  def index(conn, _params) do
    render(conn, :index, tenants: Tenants.list_tenants())
  end

  def new(conn, _params) do
    render(conn, :new, changeset: Tenants.change_tenant(%Tenant{}))
  end

  def create(conn, %{"tenant" => attrs}) do
    with {:ok, tenant} <- Tenants.create_tenant_record(attrs),
         {:ok, provisioned} <- Provisioner.provision(tenant, actor: {:super_admin, conn.assigns.super_admin.id}) do
      redirect(conn, to: ~p"/super/tenants/#{provisioned.id}")
    else
      {:error, %Ecto.Changeset{} = cs} -> render(conn, :new, changeset: cs)
      {:error, reason} -> render(conn, :new, changeset: Tenants.change_tenant(%Tenant{}), error: inspect(reason))
    end
  end

  def show(conn, %{"id" => id}) do
    render(conn, :show, tenant: Tenants.get_tenant!(id))
  end

  def edit(conn, %{"id" => id}) do
    tenant = Tenants.get_tenant!(id)
    render(conn, :edit, tenant: tenant, changeset: Tenants.change_tenant(tenant))
  end

  def update(conn, %{"id" => id, "tenant" => attrs}) do
    tenant = Tenants.get_tenant!(id)

    case Tenants.update_tenant(tenant, attrs) do
      {:ok, updated} ->
        Atrium.Audit.log_global("tenant.theme_updated", %{
          actor: {:super_admin, conn.assigns.super_admin.id},
          resource: {"Tenant", updated.id},
          changes: diff(tenant, updated)
        })

        redirect(conn, to: ~p"/super/tenants/#{updated.id}")

      {:error, cs} ->
        render(conn, :edit, tenant: tenant, changeset: cs)
    end
  end

  defp diff(old, new) do
    Map.new([:name, :theme, :enabled_sections, :allow_local_login], fn key ->
      {to_string(key), [Map.get(old, key), Map.get(new, key)]}
    end)
    |> Enum.filter(fn {_k, [a, b]} -> a != b end)
    |> Map.new()
  end
end
```

- [ ] **Step 3: Create view and templates**

Create `lib/atrium_web/controllers/super_admin/tenant_html.ex`:

```elixir
defmodule AtriumWeb.SuperAdmin.TenantHTML do
  use AtriumWeb, :html
  embed_templates "tenant_html/*"
end
```

Templates (all under `lib/atrium_web/controllers/super_admin/tenant_html/`):

`index.html.heex`:

```heex
<main class="p-8">
  <div class="flex justify-between items-center mb-4">
    <h1 class="text-2xl font-semibold">Tenants</h1>
    <.link navigate={~p"/super/tenants/new"} class="rounded bg-slate-900 text-white px-3 py-1">New tenant</.link>
  </div>
  <table class="w-full border">
    <thead class="bg-slate-50"><tr><th class="p-2 text-left">Slug</th><th class="p-2 text-left">Name</th><th class="p-2 text-left">Status</th></tr></thead>
    <tbody>
      <%= for t <- @tenants do %>
        <tr class="border-t">
          <td class="p-2"><.link navigate={~p"/super/tenants/#{t.id}"}><%= t.slug %></.link></td>
          <td class="p-2"><%= t.name %></td>
          <td class="p-2"><%= t.status %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
</main>
```

`new.html.heex`:

```heex
<main class="max-w-lg p-8">
  <h1 class="text-xl font-semibold mb-4">New tenant</h1>
  <.form :let={f} for={@changeset} action={~p"/super/tenants"} class="space-y-4">
    <div>
      <label class="block text-sm">Slug</label>
      <.input field={f[:slug]} class="mt-1 w-full border rounded p-2" />
    </div>
    <div>
      <label class="block text-sm">Name</label>
      <.input field={f[:name]} class="mt-1 w-full border rounded p-2" />
    </div>
    <button type="submit" class="rounded bg-slate-900 text-white px-3 py-1">Create</button>
  </.form>
</main>
```

`show.html.heex`:

```heex
<main class="p-8">
  <h1 class="text-xl font-semibold"><%= @tenant.name %> (<%= @tenant.slug %>)</h1>
  <p class="text-gray-600">Status: <%= @tenant.status %></p>
  <.link navigate={~p"/super/tenants/#{@tenant.id}/edit"} class="inline-block mt-4 rounded bg-slate-900 text-white px-3 py-1">Edit</.link>
</main>
```

`edit.html.heex`:

```heex
<main class="max-w-lg p-8">
  <h1 class="text-xl font-semibold mb-4">Edit <%= @tenant.slug %></h1>
  <.form :let={f} for={@changeset} action={~p"/super/tenants/#{@tenant.id}"} method="put" class="space-y-4">
    <div>
      <label class="block text-sm">Name</label>
      <.input field={f[:name]} class="mt-1 w-full border rounded p-2" />
    </div>
    <div>
      <label class="block text-sm">Enabled sections (comma-separated keys)</label>
      <.input field={f[:enabled_sections]} class="mt-1 w-full border rounded p-2" />
    </div>
    <button type="submit" class="rounded bg-slate-900 text-white px-3 py-1">Save</button>
  </.form>
</main>
```

- [ ] **Step 4: Run tests**

```bash
mix test test/atrium_web/controllers/super_admin/tenant_controller_test.exs
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(super_admin): add tenant CRUD controller and templates"
```

---

## Task 14: Vue 3 + Tailwind asset pipeline (scaffold for Phase 1)

**Files:**
- Modify: `assets/package.json`, `assets/vite/esbuild` config if present, `assets/js/app.js`, `assets/css/app.css`

- [ ] **Step 1: Add Vue 3 to JS deps**

From `/Users/marcinwalczak/Kod/atrium/assets`:

```bash
npm install vue@3
```

- [ ] **Step 2: Wire a minimal Vue mount point**

Edit `assets/js/app.js` to append at the bottom (don't remove Phoenix boot code):

```js
import { createApp } from "vue"

const VueIslands = {}

export function registerVueIsland(name, component) {
  VueIslands[name] = component
}

function mountIslands() {
  document.querySelectorAll("[data-vue]").forEach((el) => {
    const name = el.dataset.vue
    const component = VueIslands[name]
    if (!component) return
    const props = el.dataset.props ? JSON.parse(el.dataset.props) : {}
    createApp(component, props).mount(el)
  })
}

window.addEventListener("DOMContentLoaded", mountIslands)
```

- [ ] **Step 3: Confirm esbuild handles Vue SFC**

For Phase 0a we are *not* using `.vue` single-file components; Phase 1 will. Confirm a plain `.js` Vue component can be registered:

Add a trivial smoke component in `assets/js/islands/hello.js`:

```js
import { h } from "vue"
import { registerVueIsland } from "../app.js"

registerVueIsland("hello", {
  props: ["name"],
  setup(props) {
    return () => h("span", {}, `Hello, ${props.name || "Atrium"}!`)
  },
})
```

And import it from `app.js` with `import "./islands/hello.js"`.

- [ ] **Step 4: Smoke-test in browser**

Temporarily add to `page_html/home.html.heex`:

```heex
<div data-vue="hello" data-props={Jason.encode!(%{name: @tenant.name})}></div>
```

Start `mix phx.server`, provision a test tenant via the mix task, visit `http://<slug>.localhost:4000`, confirm "Hello, <Name>!" renders.

Remove the smoke `<div>` before committing (or leave in Phase 0a as a visible success marker — your call; the plan assumes remove).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(assets): scaffold Vue 3 island mount + tailwind for later phases"
```

---

## Task 15: Test support — `Atrium.TenantCase`

**Files:**
- Create: `test/support/tenant_case.ex`

This helper is required by later plans (0b–0e) to build tests that operate inside a tenant schema. Ship it now so the pattern is established.

- [ ] **Step 1: Write the helper**

Create `test/support/tenant_case.ex`:

```elixir
defmodule Atrium.TenantCase do
  @moduledoc """
  Test case for tests that run inside a tenant schema.

  Usage:

      defmodule Atrium.Accounts.UsersTest do
        use Atrium.TenantCase
        # `@tenant` and `@tenant_prefix` are available in tests
      end

  Creates a unique tenant per test module (not per test — expensive), runs
  migrations in the tenant schema, and tears the schema down in `on_exit`.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Atrium.DataCase, only: [errors_on: 1]
    end
  end

  setup_all do
    slug = "test-" <> (:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower))
    {:ok, tenant} = Atrium.Tenants.create_tenant_record(%{slug: slug, name: "Test #{slug}"})
    {:ok, tenant} = Atrium.Tenants.Provisioner.provision(tenant)

    on_exit(fn ->
      _ = Triplex.drop(slug)
      _ = Atrium.Repo.delete(tenant)
    end)

    {:ok, tenant: tenant, tenant_prefix: Triplex.to_prefix(slug)}
  end

  setup %{tenant: tenant} = ctx do
    # Each test re-uses the tenant from setup_all; sandbox ownership is per-test
    # for the default repo. Tests that write to tenant schemas must use
    # `Atrium.Repo.query!/3` or `Ecto.Adapters.SQL.Sandbox.allow/3` as needed.
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Atrium.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Atrium.Repo, {:shared, self()})
    Map.put(ctx, :tenant_prefix, Triplex.to_prefix(tenant.slug))
  end
end
```

Note: Triplex + the Ecto sandbox together have quirks. Plan 0b will validate this helper against real tenant-schema migrations and refine as needed. For Phase 0a, the helper compiles and is available; it is exercised for real in 0b.

- [ ] **Step 2: Confirm it compiles**

Ensure `test/support/` is listed in `elixirc_paths` for `:test` in `mix.exs` (phx.new does this by default). Run:

```bash
mix compile --warnings-as-errors
```

Expected: clean compile.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test: add Atrium.TenantCase helper for tenant-schema tests"
```

---

## Task 16: Final integration smoke test

**Files:** none created

- [ ] **Step 1: Run the full test suite**

```bash
mix test
```

Expected: all tests pass, no warnings.

- [ ] **Step 2: End-to-end smoke via CLI**

```bash
MIX_ENV=dev mix atrium.provision_tenant --slug smoke-test --name "Smoke Test"
```

Then:

```bash
mix phx.server &
curl -s -H "Host: admin.atrium.example" http://localhost:4000/healthz | jq
curl -s -H "Host: smoke-test.localhost" http://localhost:4000/ | head -20
```

Expected:
- `/healthz` returns `{"status":"ok","active_tenants":1,...}`
- tenant `/` returns the home page with "Smoke Test" in the markup.

Stop the server. Clean up:

```bash
psql atrium_dev -c "DROP SCHEMA IF EXISTS \"tenant_smoke-test\" CASCADE"
psql atrium_dev -c "DELETE FROM tenants WHERE slug='smoke-test'"
```

- [ ] **Step 2: Commit any trailing changes**

```bash
git status
# If clean, skip. Otherwise:
git add -A && git commit -m "chore: phase 0a complete — skeleton, tenancy, super-admin"
```

- [ ] **Step 3: Tag the milestone**

```bash
git tag phase-0a-complete
```

---

## Plan 0a complete — what's next

Plan 0b will add the `Accounts` context (tenant-schema users, sessions, invitations, local login, password reset) and the tenant-schema-side of the TenantResolver (Triplex prefix setting within a controller plug). Plan 0b builds on `Atrium.TenantCase` from Task 15 and expects the Phase 0a schema skeleton.
