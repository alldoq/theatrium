# Customers Contact Book — Design

**Date:** 2026-05-18
**Status:** Approved
**Topic:** New "Customers" section — a contact book where each customer has multiple associated people.

## Summary

Add a 15th canonical intranet section, `customers`, to Atrium. It is a contact book:
each customer record has multiple people (contacts) associated with it. The section is
per-tenant toggleable via `enabled_sections` and access-restricted to the `super_users`
group. Full CRUD is provided in-app for both customers and their people.

## Goals

- A new `customers` section that follows existing section conventions.
- Per-tenant on/off toggle via the existing `enabled_sections` mechanism.
- One customer has many people; deleting a customer cascades to its people.
- Restricted visibility: only `super_users` may view and edit.

## Non-Goals (YAGNI)

- No deals, pipelines, activity logs, or general CRM features.
- No subsections.
- No global typeahead search integration (see Search section for rationale).
- No import/export.

## Data Model

Two new tables in `priv/repo/tenant_migrations/` (per-tenant schema, accessed with `prefix`).

### `customers`

| column      | type        | constraints              |
|-------------|-------------|--------------------------|
| id          | binary_id   | PK                       |
| name        | string      | not null                 |
| website     | string      |                          |
| notes       | text        |                          |
| inserted_at | utc_datetime|                          |
| updated_at  | utc_datetime|                          |

### `customer_people`

| column      | type        | constraints                                   |
|-------------|-------------|-----------------------------------------------|
| id          | binary_id   | PK                                            |
| customer_id | binary_id   | FK -> customers, not null, on_delete: delete_all |
| name        | string      | not null                                      |
| job_title   | string      |                                               |
| email       | string      |                                               |
| phone       | string      |                                               |
| primary     | boolean     | default false                                 |
| inserted_at | utc_datetime|                                               |
| updated_at  | utc_datetime|                                               |

Index on `customer_id`.

### Schemas

- `Atrium.Customers.Customer` — `has_many :people, Customer.Person`. Fields: name, website, notes.
- `Atrium.Customers.Person` — `belongs_to :customer`. Fields: name, job_title, email, phone, primary.

Validations: customer requires `name`; person requires `name`. `email` validated with a
basic format regex when present (matches app norms). Other fields optional.

## Section Registration & Access

Append a 15th entry to `Atrium.Authorization.SectionRegistry` `@sections`:

```elixir
%{
  key: :customers,
  name: "Customers",
  icon: "address-book",          # fallback "users" if icon not present in icon set
  supports_subsections: false,
  default_capabilities: @capabilities,   # [:view, :edit, :approve]
  default_acls: [{:group, :super_users, :view}, {:group, :super_users, :edit}]
}
```

- **Restricted ACL** — only `super_users`, NOT `all_staff`. Customer data is hidden from
  general staff.
- **New tenants** — `Atrium.Tenants.Seed.seed_default_acls/1` iterates the registry, so the
  ACL is seeded automatically on provisioning.
- **Existing tenants** — a migration in `tenant_migrations/` calls
  `Atrium.Tenants.Seed.ensure_default_acls/1` (idempotent — inserts only missing ACLs)
  across each tenant schema.
- **Toggle** — `customers` becomes a valid `enabled_sections` key. The super-admin tenant
  edit page renders its checkbox automatically from the registry. Off by default until a
  tenant admin enables it.

## Routes

```
GET    /customers                       index           customer list (+ ?q= search)
GET    /customers/new                    new             new customer form
POST   /customers                        create
GET    /customers/:id                    show            customer detail + people list
GET    /customers/:id/edit               edit
PUT    /customers/:id                    update
DELETE /customers/:id                    delete          cascades people

POST   /customers/:id/people             create_person   add person to customer
GET    /customers/:id/people/:pid/edit   edit_person
PUT    /customers/:id/people/:pid        update_person
DELETE /customers/:id/people/:pid        delete_person
```

## Controller

Single `AtriumWeb.CustomerController` handles customers and nested people.

- ACL plug guards (mirrors `DirectoryController`):
  - `:view` capability for `index`, `show`.
  - `:edit` capability for `create`, `update`, `delete`, and all person actions.
  - `target: {:section, "customers"}`.
- Person actions scoped under `:id` — controller verifies the person belongs to the named
  customer before mutating (rejects cross-customer `:id`/`:pid` mismatch).
- All queries pass `prefix: conn.assigns.tenant_prefix`.

## Context

`Atrium.Customers`:

- `list_customers(prefix, opts)` — list, optional `:q` name search.
- `get_customer!(prefix, id)` — preloads `:people`.
- `create_customer/2`, `update_customer/3`, `delete_customer/2`.
- `add_person/3`, `update_person/3`, `delete_person/2`.

## UI Flow

Templates follow existing section style (`directory_html` and peers).

- **Index** — name search box, customer rows/cards with per-customer person count,
  "New customer" button. Empty state when no customers.
- **Show** — customer info (name, website, notes); people table (name, job title, email,
  phone, primary badge); inline "Add person" form + per-row edit/delete; edit/delete
  customer buttons. Empty state when customer has no people.
- **New / Edit** — simple forms for customer and person.

## Navigation

The sidebar nav is built from the registry filtered by `enabled_sections`
(`Atrium.AppShell`). The new section appears automatically once the registry entry exists
and the tenant enables it. No nav code change beyond the registry entry.

## Search

The `customers` section is **excluded** from global typeahead search (`Atrium.Search`).
Global search results are visible to the searcher, but `customers` is restricted to
`super_users`; indexing it risks leaking customer names to general staff. In-section
`?q=` search (by name) is provided instead. ACL-filtered global search could be a
separate future task.

## Testing

- **Context tests** — `Atrium.Customers` CRUD, cascade delete (customer -> people),
  name search filter.
- **Controller tests** — ACL: `super_users` member gets 200; non-member gets 403.
  Person actions reject a `:pid` that does not belong to the named customer.
- **Section toggle** — section hidden / route inaccessible when `customers` is not in
  `enabled_sections`.

## Edge Cases

- Delete customer with people → DB-level cascade (`on_delete: :delete_all`).
- Person `email` / `phone` optional; `email` gets a basic format check when present.
- Empty states — no customers; customer with no people.
- Existing-tenant ACL backfill — `tenant_migrations/` migration invoking
  `Seed.ensure_default_acls/1` across all tenant schemas.

## Files Touched (estimate)

- `priv/repo/tenant_migrations/` — 2 new (`create_customers`, `create_customer_people`),
  1 ACL backfill migration.
- `lib/atrium/customers.ex` — new context.
- `lib/atrium/customers/customer.ex`, `lib/atrium/customers/person.ex` — new schemas.
- `lib/atrium/authorization/section_registry.ex` — append 15th section.
- `lib/atrium_web/controllers/customer_controller.ex` + `customer_html/` templates — new.
- `lib/atrium_web/router.ex` — new routes.
- Tests under `test/`.
