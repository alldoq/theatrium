# Customers Contact Book Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-tenant toggleable "Customers" section — a contact book where each customer has many associated people — restricted to the `super_users` group.

**Architecture:** A 15th canonical section registered in `Atrium.Authorization.SectionRegistry`. Two per-tenant-schema tables (`customers`, `customer_people`) created via `tenant_migrations/`. An `Atrium.Customers` context, an `AtriumWeb.CustomerController` guarded by the existing `Authorize` plug, and HEEx templates following the `directory`/`projects` section conventions.

**Tech Stack:** Elixir, Phoenix, Ecto, Triplex (multi-tenant schemas), PostgreSQL.

---

## File Structure

- `priv/repo/tenant_migrations/20260518000001_create_customers.exs` — creates both tables.
- `priv/repo/tenant_migrations/20260518000002_seed_customers_acls.exs` — backfills ACLs for existing tenants.
- `lib/atrium/customers/customer.ex` — `Customer` schema.
- `lib/atrium/customers/person.ex` — `Person` schema.
- `lib/atrium/customers.ex` — context module (CRUD).
- `lib/atrium/authorization/section_registry.ex` — append 15th section (modify).
- `lib/atrium_web/controllers/customer_controller.ex` — controller.
- `lib/atrium_web/controllers/customer_html.ex` — view module.
- `lib/atrium_web/controllers/customer_html/index.html.heex` — customer list.
- `lib/atrium_web/controllers/customer_html/show.html.heex` — customer detail + people.
- `lib/atrium_web/controllers/customer_html/new.html.heex` — new customer form.
- `lib/atrium_web/controllers/customer_html/edit.html.heex` — edit customer form.
- `lib/atrium_web/controllers/customer_html/edit_person.html.heex` — edit person form.
- `lib/atrium_web/router.ex` — add routes (modify).
- `test/atrium/customers_test.exs` — context tests.
- `test/atrium_web/controllers/customer_controller_test.exs` — controller/ACL tests.

---

## Task 1: Tenant migration — customers and customer_people tables

**Files:**
- Create: `priv/repo/tenant_migrations/20260518000001_create_customers.exs`

- [ ] **Step 1: Write the migration**

```elixir
defmodule Atrium.Repo.TenantMigrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :website, :string
      add :notes, :text
      timestamps(type: :utc_datetime_usec)
    end

    create table(:customer_people, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :customer_id, references(:customers, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :job_title, :string
      add :email, :string
      add :phone, :string
      add :primary, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:customer_people, [:customer_id])
  end
end
```

- [ ] **Step 2: Verify migration compiles**

Run: `mix compile`
Expected: compiles with no errors.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/tenant_migrations/20260518000001_create_customers.exs
git commit -m "feat(customers): add customers and customer_people tenant tables"
```

---

## Task 2: Customer schema

**Files:**
- Create: `lib/atrium/customers/customer.ex`
- Test: `test/atrium/customers_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Atrium.CustomersTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.Customers
  alias Atrium.Customers.Customer
  alias Atrium.Tenants
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "cust_#{:erlang.unique_integer([:positive])}"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Customers Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    {:ok, prefix: Triplex.to_prefix(slug)}
  end

  test "customer changeset requires name" do
    cs = Customer.changeset(%Customer{}, %{"website" => "x.com"})
    refute cs.valid?
    assert %{name: ["can't be blank"]} = errors_on(cs)
  end

  test "customer changeset is valid with a name" do
    cs = Customer.changeset(%Customer{}, %{"name" => "Acme Co"})
    assert cs.valid?
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/atrium/customers_test.exs`
Expected: FAIL — `Atrium.Customers.Customer` does not exist.

- [ ] **Step 3: Write the Customer schema**

```elixir
defmodule Atrium.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  alias Atrium.Customers.Person

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customers" do
    field :name, :string
    field :website, :string
    field :notes, :string

    has_many :people, Person

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:name, :website, :notes])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/atrium/customers_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/customers/customer.ex test/atrium/customers_test.exs
git commit -m "feat(customers): add Customer schema"
```

---

## Task 3: Person schema

**Files:**
- Create: `lib/atrium/customers/person.ex`
- Test: `test/atrium/customers_test.exs` (append)

- [ ] **Step 1: Write the failing test**

Append to `test/atrium/customers_test.exs`, inside the module:

```elixir
  test "person changeset requires name" do
    cs = Atrium.Customers.Person.changeset(%Atrium.Customers.Person{}, %{"email" => "a@b.com"})
    refute cs.valid?
    assert %{name: ["can't be blank"]} = errors_on(cs)
  end

  test "person changeset rejects malformed email" do
    cs = Atrium.Customers.Person.changeset(%Atrium.Customers.Person{}, %{"name" => "Bob", "email" => "not-an-email"})
    refute cs.valid?
    assert %{email: ["must be a valid email"]} = errors_on(cs)
  end

  test "person changeset is valid without an email" do
    cs = Atrium.Customers.Person.changeset(%Atrium.Customers.Person{}, %{"name" => "Bob"})
    assert cs.valid?
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/atrium/customers_test.exs`
Expected: FAIL — `Atrium.Customers.Person` does not exist.

- [ ] **Step 3: Write the Person schema**

```elixir
defmodule Atrium.Customers.Person do
  use Ecto.Schema
  import Ecto.Changeset

  alias Atrium.Customers.Customer

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  schema "customer_people" do
    field :name, :string
    field :job_title, :string
    field :email, :string
    field :phone, :string
    field :primary, :boolean, default: false

    belongs_to :customer, Customer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(person, attrs) do
    person
    |> cast(attrs, [:name, :job_title, :email, :phone, :primary, :customer_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_format(:email, @email_regex, message: "must be a valid email")
  end
end
```

Note: `validate_format` is skipped automatically when `email` is nil/absent, so a person without an email stays valid.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/atrium/customers_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/customers/person.ex test/atrium/customers_test.exs
git commit -m "feat(customers): add Person schema"
```

---

## Task 4: Customers context — customer CRUD

**Files:**
- Create: `lib/atrium/customers.ex`
- Test: `test/atrium/customers_test.exs` (append)

- [ ] **Step 1: Write the failing test**

Append inside the module:

```elixir
  test "create_customer / list_customers / get_customer!", %{prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co", "website" => "acme.com"})
    assert c.name == "Acme Co"

    assert [listed] = Customers.list_customers(prefix)
    assert listed.id == c.id

    fetched = Customers.get_customer!(prefix, c.id)
    assert fetched.id == c.id
    assert fetched.people == []
  end

  test "list_customers filters by name query", %{prefix: prefix} do
    {:ok, _} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, _} = Customers.create_customer(prefix, %{"name" => "Globex"})

    assert [only] = Customers.list_customers(prefix, q: "acme")
    assert only.name == "Acme Co"
  end

  test "update_customer changes fields", %{prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, updated} = Customers.update_customer(prefix, c, %{"name" => "Acme Inc"})
    assert updated.name == "Acme Inc"
  end

  test "delete_customer removes the customer", %{prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, _} = Customers.delete_customer(prefix, c)
    assert Customers.list_customers(prefix) == []
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/atrium/customers_test.exs`
Expected: FAIL — `Atrium.Customers.create_customer/2` undefined.

- [ ] **Step 3: Write the context (customer functions)**

```elixir
defmodule Atrium.Customers do
  @moduledoc "Context for the Customers contact book section."

  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Customers.{Customer, Person}

  def list_customers(prefix, opts \\ []) do
    query = from(c in Customer, order_by: [asc: c.name])

    query =
      case Keyword.get(opts, :q) do
        nil -> query
        "" -> query
        q ->
          like = "%#{String.downcase(q)}%"
          from(c in query, where: like(fragment("lower(?)", c.name), ^like))
      end

    Repo.all(query, prefix: prefix)
  end

  def get_customer!(prefix, id) do
    Customer
    |> Repo.get!(id, prefix: prefix)
    |> Repo.preload([people: from(p in Person, order_by: [desc: p.primary, asc: p.name])], prefix: prefix)
  end

  def create_customer(prefix, attrs) do
    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  def update_customer(prefix, %Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update(prefix: prefix)
  end

  def delete_customer(prefix, %Customer{} = customer) do
    Repo.delete(customer, prefix: prefix)
  end

  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/atrium/customers_test.exs`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/customers.ex test/atrium/customers_test.exs
git commit -m "feat(customers): add Customers context with customer CRUD"
```

---

## Task 5: Customers context — person CRUD and cascade

**Files:**
- Modify: `lib/atrium/customers.ex`
- Test: `test/atrium/customers_test.exs` (append)

- [ ] **Step 1: Write the failing test**

Append inside the module:

```elixir
  test "add_person / get_person! / update_person / delete_person", %{prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})

    {:ok, p} = Customers.add_person(prefix, c.id, %{"name" => "Bob", "email" => "bob@acme.com"})
    assert p.customer_id == c.id

    fetched = Customers.get_person!(prefix, c.id, p.id)
    assert fetched.id == p.id

    {:ok, updated} = Customers.update_person(prefix, fetched, %{"job_title" => "CEO"})
    assert updated.job_title == "CEO"

    {:ok, _} = Customers.delete_person(prefix, updated)
    assert Customers.get_customer!(prefix, c.id).people == []
  end

  test "get_person! rejects a person from a different customer", %{prefix: prefix} do
    {:ok, c1} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, c2} = Customers.create_customer(prefix, %{"name" => "Globex"})
    {:ok, p} = Customers.add_person(prefix, c1.id, %{"name" => "Bob"})

    assert_raise Ecto.NoResultsError, fn ->
      Customers.get_person!(prefix, c2.id, p.id)
    end
  end

  test "deleting a customer cascades to its people", %{prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, _} = Customers.add_person(prefix, c.id, %{"name" => "Bob"})

    {:ok, _} = Customers.delete_customer(prefix, c)

    assert Atrium.Repo.all(Atrium.Customers.Person, prefix: prefix) == []
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/atrium/customers_test.exs`
Expected: FAIL — `Atrium.Customers.add_person/3` undefined.

- [ ] **Step 3: Add person functions to the context**

Add to `lib/atrium/customers.ex`, inside the module after `change_customer/2`:

```elixir
  def get_person!(prefix, customer_id, person_id) do
    Repo.one!(
      from(p in Person, where: p.id == ^person_id and p.customer_id == ^customer_id),
      prefix: prefix
    )
  end

  def add_person(prefix, customer_id, attrs) do
    attrs = Map.put(stringify(attrs), "customer_id", customer_id)

    %Person{}
    |> Person.changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  def update_person(prefix, %Person{} = person, attrs) do
    person
    |> Person.changeset(stringify(attrs))
    |> Repo.update(prefix: prefix)
  end

  def delete_person(prefix, %Person{} = person) do
    Repo.delete(person, prefix: prefix)
  end

  def change_person(%Person{} = person, attrs \\ %{}) do
    Person.changeset(person, attrs)
  end

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/atrium/customers_test.exs`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/atrium/customers.ex test/atrium/customers_test.exs
git commit -m "feat(customers): add person CRUD and cascade delete to context"
```

---

## Task 6: Register the customers section

**Files:**
- Modify: `lib/atrium/authorization/section_registry.ex`

- [ ] **Step 1: Add the section entry**

In `lib/atrium/authorization/section_registry.ex`, add this entry to the end of the `@sections` list (after the `:feedback` entry, before the closing `]`):

```elixir
    ,
    %{
      key: :customers,
      name: "Customers",
      icon: "address-book",
      supports_subsections: false,
      default_capabilities: @capabilities,
      default_acls: [{:group, :super_users, :view}, {:group, :super_users, :edit}]
    }
```

Note: the `,` on its own line joins it to the preceding `:feedback` map. The moduledoc still says "14 canonical sections" — update the moduledoc count from "14" to "15" in the same edit.

- [ ] **Step 2: Verify the registry loads the new key**

Run: `mix run -e 'IO.inspect(Enum.member?(Atrium.Authorization.SectionRegistry.keys(), :customers))'`
Expected: prints `true`.

- [ ] **Step 3: Verify icon exists, fall back if not**

Run: `grep -rl "address-book" lib/atrium_web/components/ assets/ 2>/dev/null`
Expected: at least one match. If there are NO matches, change `icon: "address-book"` to `icon: "users"` in the entry from Step 1.

- [ ] **Step 4: Commit**

```bash
git add lib/atrium/authorization/section_registry.ex
git commit -m "feat(customers): register customers as 15th section"
```

---

## Task 7: ACL backfill migration for existing tenants

**Files:**
- Create: `priv/repo/tenant_migrations/20260518000002_seed_customers_acls.exs`

- [ ] **Step 1: Write the migration**

```elixir
defmodule Atrium.Repo.TenantMigrations.SeedCustomersAcls do
  use Ecto.Migration

  # Runs per-tenant. Triplex sets the migration prefix to the tenant schema,
  # so Seed.ensure_default_acls/1 inserts the customers ACL into this tenant.
  def up do
    prefix = repo().config()[:migration_default_prefix] || prefix() || "public"
    flush()
    Atrium.Tenants.Seed.ensure_default_acls(to_string(prefix))
  end

  def down, do: :ok
end
```

Note: if `Atrium.Tenants.Seed.ensure_default_acls/1` requires the tenant prefix and the above does not resolve it correctly, instead resolve the prefix from the migrator. Check how an existing `tenant_migrations` data migration obtains its prefix before writing this — search: `grep -rl "prefix()" priv/repo/tenant_migrations/`. Use the same mechanism the codebase already uses. If no precedent exists, leave this migration as `up: :ok` and instead document a manual post-deploy step: `Atrium.Tenants` enumerate tenants and call `Atrium.Tenants.Seed.ensure_default_acls/1` for each.

- [ ] **Step 2: Verify migration compiles**

Run: `mix compile`
Expected: compiles with no errors.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/tenant_migrations/20260518000002_seed_customers_acls.exs
git commit -m "feat(customers): backfill customers ACL for existing tenants"
```

---

## Task 8: Routes

**Files:**
- Modify: `lib/atrium_web/router.ex`

- [ ] **Step 1: Add the routes**

In `lib/atrium_web/router.ex`, find the scope/pipeline where other authenticated tenant section routes live (e.g. the block containing `get "/directory", DirectoryController, :index`). Add, inside that same scope:

```elixir
    get "/customers", CustomerController, :index
    get "/customers/new", CustomerController, :new
    post "/customers", CustomerController, :create
    get "/customers/:id", CustomerController, :show
    get "/customers/:id/edit", CustomerController, :edit
    put "/customers/:id", CustomerController, :update
    delete "/customers/:id", CustomerController, :delete

    post "/customers/:id/people", CustomerController, :create_person
    get "/customers/:id/people/:pid/edit", CustomerController, :edit_person
    put "/customers/:id/people/:pid", CustomerController, :update_person
    delete "/customers/:id/people/:pid", CustomerController, :delete_person
```

Order matters: `/customers/new` must be declared before `/customers/:id` so it is not captured as an `:id`.

- [ ] **Step 2: Verify routes registered**

Run: `mix phx.routes | grep customers`
Expected: 11 customer routes printed.

- [ ] **Step 3: Commit**

```bash
git add lib/atrium_web/router.ex
git commit -m "feat(customers): add customer routes"
```

---

## Task 9: Controller — index and show

**Files:**
- Create: `lib/atrium_web/controllers/customer_controller.ex`
- Create: `lib/atrium_web/controllers/customer_html.ex`
- Create: `lib/atrium_web/controllers/customer_html/index.html.heex`
- Create: `lib/atrium_web/controllers/customer_html/show.html.heex`
- Test: `test/atrium_web/controllers/customer_controller_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule AtriumWeb.CustomerControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.{Accounts, Authorization, Tenants, Customers}
  alias Atrium.Tenants.Provisioner

  setup do
    slug = "cc_#{:erlang.unique_integer([:positive])}"
    host = "#{slug}.atrium.example"
    {:ok, tenant} = Tenants.create_tenant_record(%{slug: slug, name: "Customer Ctrl Test"})
    {:ok, _} = Provisioner.provision(tenant)
    on_exit(fn -> _ = Triplex.drop(slug) end)
    prefix = Triplex.to_prefix(slug)

    {:ok, %{user: editor}} = Accounts.invite_user(prefix, %{
      email: "editor_#{System.unique_integer([:positive])}@example.com",
      name: "Editor"
    })
    {:ok, editor} = Accounts.activate_user_with_password(prefix, editor, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })
    Authorization.grant_section(prefix, "customers", {:user, editor.id}, :view)
    Authorization.grant_section(prefix, "customers", {:user, editor.id}, :edit)

    {:ok, %{user: outsider}} = Accounts.invite_user(prefix, %{
      email: "outsider_#{System.unique_integer([:positive])}@example.com",
      name: "Outsider"
    })
    {:ok, outsider} = Accounts.activate_user_with_password(prefix, outsider, %{
      password: "Correct-horse-battery1",
      password_confirmation: "Correct-horse-battery1"
    })

    editor_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: editor.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    outsider_conn =
      build_conn()
      |> Map.put(:host, host)
      |> post("/login", %{email: outsider.email, password: "Correct-horse-battery1"})
      |> recycle()
      |> Map.put(:host, host)

    {:ok, editor_conn: editor_conn, outsider_conn: outsider_conn, prefix: prefix}
  end

  test "GET /customers shows index to authorized user", %{editor_conn: conn} do
    conn = get(conn, "/customers")
    assert html_response(conn, 200) =~ "Customers"
  end

  test "GET /customers is forbidden for unauthorized user", %{outsider_conn: conn} do
    conn = get(conn, "/customers")
    assert conn.status == 403
  end

  test "GET /customers/:id shows a customer and its people", %{editor_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, _} = Customers.add_person(prefix, c.id, %{"name" => "Bob Vance"})

    conn = get(conn, "/customers/#{c.id}")
    body = html_response(conn, 200)
    assert body =~ "Acme Co"
    assert body =~ "Bob Vance"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/atrium_web/controllers/customer_controller_test.exs`
Expected: FAIL — `AtriumWeb.CustomerController` does not exist.

- [ ] **Step 3: Write the controller (index + show)**

```elixir
defmodule AtriumWeb.CustomerController do
  use AtriumWeb, :controller

  alias Atrium.Customers

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "customers"}]
       when action in [:index, :show]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "customers"}]
       when action in [
              :new,
              :create,
              :edit,
              :update,
              :delete,
              :create_person,
              :edit_person,
              :update_person,
              :delete_person
            ]

  def index(conn, params) do
    prefix = conn.assigns.tenant_prefix
    customers = Customers.list_customers(prefix, q: params["q"])
    render(conn, :index, customers: customers, query: params["q"] || "")
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    customer = Customers.get_customer!(prefix, id)
    render(conn, :show, customer: customer)
  end
end
```

- [ ] **Step 4: Write the view module**

```elixir
defmodule AtriumWeb.CustomerHTML do
  use AtriumWeb, :html

  embed_templates "customer_html/*"
end
```

- [ ] **Step 5: Write `customer_html/index.html.heex`**

```heex
<div class="mx-auto max-w-4xl px-4 py-8">
  <div class="flex items-center justify-between mb-6">
    <h1 class="text-2xl font-semibold">Customers</h1>
    <.link href={~p"/customers/new"} class="rounded bg-blue-600 px-4 py-2 text-white">
      New customer
    </.link>
  </div>

  <form method="get" action={~p"/customers"} class="mb-6">
    <input
      type="text"
      name="q"
      value={@query}
      placeholder="Search by name"
      class="w-full rounded border px-3 py-2"
    />
  </form>

  <div :if={@customers == []} class="text-gray-500">No customers yet.</div>

  <ul class="divide-y rounded border">
    <li :for={customer <- @customers} class="flex items-center justify-between px-4 py-3">
      <.link href={~p"/customers/#{customer.id}"} class="font-medium text-blue-700">
        {customer.name}
      </.link>
      <span :if={customer.website} class="text-sm text-gray-500">{customer.website}</span>
    </li>
  </ul>
</div>
```

- [ ] **Step 6: Write `customer_html/show.html.heex`**

```heex
<div class="mx-auto max-w-4xl px-4 py-8">
  <.link href={~p"/customers"} class="text-sm text-blue-600">&larr; All customers</.link>

  <div class="mt-2 flex items-center justify-between">
    <h1 class="text-2xl font-semibold">{@customer.name}</h1>
    <div class="flex gap-2">
      <.link href={~p"/customers/#{@customer.id}/edit"} class="rounded border px-3 py-1">
        Edit
      </.link>
      <.link
        href={~p"/customers/#{@customer.id}"}
        method="delete"
        data-confirm="Delete this customer and all its people?"
        class="rounded border border-red-300 px-3 py-1 text-red-700"
      >
        Delete
      </.link>
    </div>
  </div>

  <p :if={@customer.website} class="mt-1 text-gray-600">{@customer.website}</p>
  <p :if={@customer.notes} class="mt-2 whitespace-pre-line text-gray-700">{@customer.notes}</p>

  <h2 class="mt-8 mb-3 text-lg font-semibold">People</h2>

  <div :if={@customer.people == []} class="text-gray-500">No people yet.</div>

  <table :if={@customer.people != []} class="w-full text-left text-sm">
    <thead>
      <tr class="border-b">
        <th class="py-2">Name</th>
        <th>Job title</th>
        <th>Email</th>
        <th>Phone</th>
        <th></th>
      </tr>
    </thead>
    <tbody>
      <tr :for={person <- @customer.people} class="border-b">
        <td class="py-2">
          {person.name}
          <span :if={person.primary} class="ml-1 rounded bg-green-100 px-1 text-xs text-green-800">
            Primary
          </span>
        </td>
        <td>{person.job_title}</td>
        <td>{person.email}</td>
        <td>{person.phone}</td>
        <td class="text-right">
          <.link href={~p"/customers/#{@customer.id}/people/#{person.id}/edit"} class="text-blue-600">
            Edit
          </.link>
          <.link
            href={~p"/customers/#{@customer.id}/people/#{person.id}"}
            method="delete"
            data-confirm="Delete this person?"
            class="ml-2 text-red-700"
          >
            Delete
          </.link>
        </td>
      </tr>
    </tbody>
  </table>

  <h3 class="mt-6 mb-2 font-medium">Add a person</h3>
  <form method="post" action={~p"/customers/#{@customer.id}/people"} class="grid grid-cols-2 gap-3">
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
    <input name="person[name]" placeholder="Name" required class="rounded border px-3 py-2" />
    <input name="person[job_title]" placeholder="Job title" class="rounded border px-3 py-2" />
    <input name="person[email]" placeholder="Email" class="rounded border px-3 py-2" />
    <input name="person[phone]" placeholder="Phone" class="rounded border px-3 py-2" />
    <label class="flex items-center gap-2 text-sm">
      <input type="checkbox" name="person[primary]" value="true" /> Primary contact
    </label>
    <button type="submit" class="rounded bg-blue-600 px-4 py-2 text-white">Add person</button>
  </form>
</div>
```

- [ ] **Step 7: Run test to verify it passes**

Run: `mix test test/atrium_web/controllers/customer_controller_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/atrium_web/controllers/customer_controller.ex lib/atrium_web/controllers/customer_html.ex lib/atrium_web/controllers/customer_html/index.html.heex lib/atrium_web/controllers/customer_html/show.html.heex test/atrium_web/controllers/customer_controller_test.exs
git commit -m "feat(customers): add controller index/show with templates"
```

---

## Task 10: Controller — customer create/edit/update/delete

**Files:**
- Modify: `lib/atrium_web/controllers/customer_controller.ex`
- Create: `lib/atrium_web/controllers/customer_html/new.html.heex`
- Create: `lib/atrium_web/controllers/customer_html/edit.html.heex`
- Test: `test/atrium_web/controllers/customer_controller_test.exs` (append)

- [ ] **Step 1: Write the failing test**

Append inside the module:

```elixir
  test "POST /customers creates a customer", %{editor_conn: conn} do
    conn = post(conn, "/customers", %{customer: %{name: "New Co", website: "new.co"}})
    assert redirected_to(conn) =~ "/customers/"
  end

  test "PUT /customers/:id updates a customer", %{editor_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Old Name"})
    conn = put(conn, "/customers/#{c.id}", %{customer: %{name: "New Name"}})
    assert redirected_to(conn) == "/customers/#{c.id}"
    assert Customers.get_customer!(prefix, c.id).name == "New Name"
  end

  test "DELETE /customers/:id deletes a customer", %{editor_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    conn = delete(conn, "/customers/#{c.id}")
    assert redirected_to(conn) == "/customers"
    assert Customers.list_customers(prefix) == []
  end

  test "POST /customers is forbidden for unauthorized user", %{outsider_conn: conn} do
    conn = post(conn, "/customers", %{customer: %{name: "Nope"}})
    assert conn.status == 403
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/atrium_web/controllers/customer_controller_test.exs`
Expected: FAIL — `new`/`create`/`update`/`delete` not implemented.

- [ ] **Step 3: Add controller actions**

Add to `lib/atrium_web/controllers/customer_controller.ex`, inside the module after `show/2`:

```elixir
  def new(conn, _params) do
    changeset = Customers.change_customer(%Atrium.Customers.Customer{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"customer" => params}) do
    prefix = conn.assigns.tenant_prefix

    case Customers.create_customer(prefix, params) do
      {:ok, customer} ->
        conn
        |> put_flash(:info, "Customer created.")
        |> redirect(to: ~p"/customers/#{customer.id}")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    customer = Customers.get_customer!(prefix, id)
    changeset = Customers.change_customer(customer)
    render(conn, :edit, customer: customer, changeset: changeset)
  end

  def update(conn, %{"id" => id, "customer" => params}) do
    prefix = conn.assigns.tenant_prefix
    customer = Customers.get_customer!(prefix, id)

    case Customers.update_customer(prefix, customer, params) do
      {:ok, customer} ->
        conn
        |> put_flash(:info, "Customer updated.")
        |> redirect(to: ~p"/customers/#{customer.id}")

      {:error, changeset} ->
        render(conn, :edit, customer: customer, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    customer = Customers.get_customer!(prefix, id)
    {:ok, _} = Customers.delete_customer(prefix, customer)

    conn
    |> put_flash(:info, "Customer deleted.")
    |> redirect(to: ~p"/customers")
  end
```

- [ ] **Step 4: Write `customer_html/new.html.heex`**

```heex
<div class="mx-auto max-w-xl px-4 py-8">
  <h1 class="mb-6 text-2xl font-semibold">New customer</h1>

  <.form :let={f} for={@changeset} action={~p"/customers"} method="post" class="space-y-4">
    <div>
      <label class="block text-sm font-medium">Name</label>
      <.input field={f[:name]} type="text" />
    </div>
    <div>
      <label class="block text-sm font-medium">Website</label>
      <.input field={f[:website]} type="text" />
    </div>
    <div>
      <label class="block text-sm font-medium">Notes</label>
      <.input field={f[:notes]} type="textarea" />
    </div>
    <button type="submit" class="rounded bg-blue-600 px-4 py-2 text-white">Create</button>
  </.form>
</div>
```

- [ ] **Step 5: Write `customer_html/edit.html.heex`**

```heex
<div class="mx-auto max-w-xl px-4 py-8">
  <h1 class="mb-6 text-2xl font-semibold">Edit customer</h1>

  <.form
    :let={f}
    for={@changeset}
    action={~p"/customers/#{@customer.id}"}
    method="put"
    class="space-y-4"
  >
    <div>
      <label class="block text-sm font-medium">Name</label>
      <.input field={f[:name]} type="text" />
    </div>
    <div>
      <label class="block text-sm font-medium">Website</label>
      <.input field={f[:website]} type="text" />
    </div>
    <div>
      <label class="block text-sm font-medium">Notes</label>
      <.input field={f[:notes]} type="textarea" />
    </div>
    <button type="submit" class="rounded bg-blue-600 px-4 py-2 text-white">Save</button>
  </.form>
</div>
```

Note: if the project's `.input` core component does not accept `type="textarea"`, replace that field with a plain `<textarea name="customer[notes]">{Phoenix.HTML.Form.input_value(f, :notes)}</textarea>`. Confirm by checking `lib/atrium_web/components/core_components.ex` for the `input` component's supported types.

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/atrium_web/controllers/customer_controller_test.exs`
Expected: PASS (7 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/atrium_web/controllers/customer_controller.ex lib/atrium_web/controllers/customer_html/new.html.heex lib/atrium_web/controllers/customer_html/edit.html.heex test/atrium_web/controllers/customer_controller_test.exs
git commit -m "feat(customers): add customer create/edit/update/delete actions"
```

---

## Task 11: Controller — person create/edit/update/delete

**Files:**
- Modify: `lib/atrium_web/controllers/customer_controller.ex`
- Create: `lib/atrium_web/controllers/customer_html/edit_person.html.heex`
- Test: `test/atrium_web/controllers/customer_controller_test.exs` (append)

- [ ] **Step 1: Write the failing test**

Append inside the module:

```elixir
  test "POST /customers/:id/people adds a person", %{editor_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    conn = post(conn, "/customers/#{c.id}/people", %{person: %{name: "Bob"}})
    assert redirected_to(conn) == "/customers/#{c.id}"
    assert [%{name: "Bob"}] = Customers.get_customer!(prefix, c.id).people
  end

  test "PUT person updates the person", %{editor_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, p} = Customers.add_person(prefix, c.id, %{"name" => "Bob"})
    conn = put(conn, "/customers/#{c.id}/people/#{p.id}", %{person: %{job_title: "CEO"}})
    assert redirected_to(conn) == "/customers/#{c.id}"
    assert Customers.get_person!(prefix, c.id, p.id).job_title == "CEO"
  end

  test "DELETE person removes the person", %{editor_conn: conn, prefix: prefix} do
    {:ok, c} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, p} = Customers.add_person(prefix, c.id, %{"name" => "Bob"})
    conn = delete(conn, "/customers/#{c.id}/people/#{p.id}")
    assert redirected_to(conn) == "/customers/#{c.id}"
    assert Customers.get_customer!(prefix, c.id).people == []
  end

  test "person actions reject a pid from a different customer", %{editor_conn: conn, prefix: prefix} do
    {:ok, c1} = Customers.create_customer(prefix, %{"name" => "Acme Co"})
    {:ok, c2} = Customers.create_customer(prefix, %{"name" => "Globex"})
    {:ok, p} = Customers.add_person(prefix, c1.id, %{"name" => "Bob"})

    assert_error_sent 404, fn ->
      delete(conn, "/customers/#{c2.id}/people/#{p.id}")
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/atrium_web/controllers/customer_controller_test.exs`
Expected: FAIL — `create_person` not implemented.

- [ ] **Step 3: Add person actions to the controller**

Add to `lib/atrium_web/controllers/customer_controller.ex`, inside the module after `delete/2`:

```elixir
  def create_person(conn, %{"id" => customer_id, "person" => params}) do
    prefix = conn.assigns.tenant_prefix
    _customer = Customers.get_customer!(prefix, customer_id)

    case Customers.add_person(prefix, customer_id, params) do
      {:ok, _person} ->
        conn
        |> put_flash(:info, "Person added.")
        |> redirect(to: ~p"/customers/#{customer_id}")

      {:error, changeset} ->
        conn
        |> put_flash(:error, error_message(changeset))
        |> redirect(to: ~p"/customers/#{customer_id}")
    end
  end

  def edit_person(conn, %{"id" => customer_id, "pid" => person_id}) do
    prefix = conn.assigns.tenant_prefix
    person = Customers.get_person!(prefix, customer_id, person_id)
    changeset = Customers.change_person(person)
    render(conn, :edit_person, customer_id: customer_id, person: person, changeset: changeset)
  end

  def update_person(conn, %{"id" => customer_id, "pid" => person_id, "person" => params}) do
    prefix = conn.assigns.tenant_prefix
    person = Customers.get_person!(prefix, customer_id, person_id)

    case Customers.update_person(prefix, person, params) do
      {:ok, _person} ->
        conn
        |> put_flash(:info, "Person updated.")
        |> redirect(to: ~p"/customers/#{customer_id}")

      {:error, changeset} ->
        render(conn, :edit_person, customer_id: customer_id, person: person, changeset: changeset)
    end
  end

  def delete_person(conn, %{"id" => customer_id, "pid" => person_id}) do
    prefix = conn.assigns.tenant_prefix
    person = Customers.get_person!(prefix, customer_id, person_id)
    {:ok, _} = Customers.delete_person(prefix, person)

    conn
    |> put_flash(:info, "Person removed.")
    |> redirect(to: ~p"/customers/#{customer_id}")
  end

  defp error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end
```

Note: `create_person` calls `get_customer!` first so a bad `:id` returns 404 before insert. `get_person!` enforces the `:pid` belongs to `:id`, raising `Ecto.NoResultsError` (→ 404) on mismatch.

- [ ] **Step 4: Write `customer_html/edit_person.html.heex`**

```heex
<div class="mx-auto max-w-xl px-4 py-8">
  <h1 class="mb-6 text-2xl font-semibold">Edit person</h1>

  <.form
    :let={f}
    for={@changeset}
    action={~p"/customers/#{@customer_id}/people/#{@person.id}"}
    method="put"
    class="space-y-4"
  >
    <div>
      <label class="block text-sm font-medium">Name</label>
      <.input field={f[:name]} type="text" />
    </div>
    <div>
      <label class="block text-sm font-medium">Job title</label>
      <.input field={f[:job_title]} type="text" />
    </div>
    <div>
      <label class="block text-sm font-medium">Email</label>
      <.input field={f[:email]} type="text" />
    </div>
    <div>
      <label class="block text-sm font-medium">Phone</label>
      <.input field={f[:phone]} type="text" />
    </div>
    <div>
      <.input field={f[:primary]} type="checkbox" label="Primary contact" />
    </div>
    <button type="submit" class="rounded bg-blue-600 px-4 py-2 text-white">Save</button>
  </.form>
</div>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/atrium_web/controllers/customer_controller_test.exs`
Expected: PASS (11 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/atrium_web/controllers/customer_controller.ex lib/atrium_web/controllers/customer_html/edit_person.html.heex test/atrium_web/controllers/customer_controller_test.exs
git commit -m "feat(customers): add person create/edit/update/delete actions"
```

---

## Task 12: Full suite, format, final verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full customers test set**

Run: `mix test test/atrium/customers_test.exs test/atrium_web/controllers/customer_controller_test.exs`
Expected: PASS — 23 tests, 0 failures.

- [ ] **Step 2: Run the whole suite to check for regressions**

Run: `mix test`
Expected: no new failures vs. the `main` baseline.

- [ ] **Step 3: Format**

Run: `mix format`
Expected: no diff in the files this plan created (already formatted) — if there is a diff, the format command applied it.

- [ ] **Step 4: Commit any formatting**

```bash
git add -A
git commit -m "chore(customers): mix format" --allow-empty
```

- [ ] **Step 5: Push**

```bash
git push
```

---

## Self-Review Notes

- **Spec coverage:** data model (Tasks 1-3), section registration + restricted ACL (Task 6), existing-tenant ACL backfill (Task 7), routes (Task 8), controller with ACL guards + person scoping (Tasks 9-11), UI index/show/new/edit (Tasks 9-11), testing — context + controller + ACL + cross-customer rejection (Tasks 2-5, 9-11). Section toggle: covered implicitly — `customers` becomes a registry key, so the existing `enabled_sections` checkbox and `AppShell` nav filter pick it up with no code change; no task needed.
- **Search exclusion:** the spec excludes `customers` from global search. No task adds it to `Atrium.Search`, so it is excluded by omission — correct. No action needed unless `Atrium.Search` auto-indexes every registry section; if it does, add a task to exclude `customers`. Verify during Task 6.
- **Open verifications flagged inline:** icon name (Task 6 Step 3), tenant-migration prefix mechanism (Task 7 Step 1), `.input` textarea support (Task 10 Step 5). Each task says what to check and the fallback.
