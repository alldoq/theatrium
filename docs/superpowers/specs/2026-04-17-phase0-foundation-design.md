# Atrium — Phase 0: Platform Foundation

**Date:** 2026-04-17
**Status:** Draft design, awaiting review
**Scope:** Phase 0 of the Atrium multi-brand intranet platform. This spec covers the architectural backbone only: multi-tenancy, authentication, users/groups, permissions, audit logging, and the application shell. Phase 1 content primitives (rich-text documents, form builder, file storage) and Phase 2 feature sections (the 14 areas) are out of scope.

## Product context

Atrium is a multi-brand intranet platform. The initial deployment serves two brands — MCL and ALLDOQ — from a single codebase and deployment, with further brands added at runtime. The platform must support ISO accreditation: auditable document and permission history, governed workflows, and strong tenant isolation.

The full system has fourteen feature sections (home, news, employee directory, HR, departments, documents, tools, projects, helpdesk, learning, events, social, compliance, feedback), runtime-editable SOPs with version control, a drag-and-drop form builder, and granular permissions. Phase 0 builds the foundation that all of that sits on.

## Goals for Phase 0

- One codebase, one deployment, many brands. New brands provisioned at runtime with no code change or deploy.
- Strong tenant data isolation sufficient for ISO audit claims.
- Per-tenant theming and feature-section toggling from database configuration.
- Per-tenant SSO (OIDC/SAML) with local-account fallback.
- Section-level permissions with one level of sub-section overrides; group- or user-scoped; capabilities of view, edit, approve.
- Reusable audit logging wired to all Phase 0 events, ready for Phase 1 primitives to plug into.
- An application shell that reads the tenant's theme and enabled sections and renders the correct navigation and branding.

## Non-goals

- Any content primitive (rich-text documents, forms, files).
- Any of the 14 feature sections beyond stub routes and nav entries driven by the section registry.
- Email delivery infrastructure beyond what auth needs (invitations, password resets).
- Impersonation or "support login" flows for super-admins.
- SSO for super-admin accounts.
- A tenant self-service signup flow — tenants are created by super-admins.

## Stack

- Phoenix (latest), Elixir, Ecto, Postgres.
- Triplex for schema-per-tenant isolation.
- Vue 3 + Tailwind for interactive islands mounted into HEEx templates via small hook components. Phase 0 has few such islands; the plumbing is in place for Phase 1.
- LiveView reserved for surfaces that genuinely benefit from it (notifications, presence). Most Phase 0 pages are plain server-rendered HEEx.
- Argon2 for password hashing.

## Architecture

### Phoenix contexts

Each context owns its schemas and exposes a narrow public API. No context reaches into another's schemas directly; cross-context work goes through public functions.

- `Tenants` — tenant records, theme, feature toggles, IdP config at the tenant-catalogue level, lifecycle (provision schema, seed defaults, suspend, resume). Public-schema context.
- `Accounts` — users, sessions, credentials (local + federated), invitations, password reset. Tenant-schema context.
- `Authorization` — groups, memberships, section/sub-section ACLs, the policy resolver. Tenant-schema context.
- `Audit` — append-only audit logging, diff utility, query API. Writes to `audit_events` (tenant) or `audit_events_global` (public) based on scope.
- `AppShell` — section registry, per-tenant feature-toggle resolution, navigation assembly, theme resolution for layout rendering.

### Tenant resolution

Subdomain-based. `mcl.atrium.example` and `alldoq.atrium.example` each resolve to a tenant record. A plug runs early in the endpoint pipeline:

1. Read the host, extract the tenant slug.
2. Look up the tenant in the public schema. Reject `404` if missing, `503` if suspended or still provisioning.
3. Set the Triplex prefix on the repo for this request.
4. Assign `conn.assigns.tenant`, `conn.assigns.theme`, `conn.assigns.enabled_sections` for downstream use.

A separate platform host (e.g., `admin.atrium.example`) bypasses this plug and runs a different pipeline that only touches the public schema. Super-admin routes live there.

### Shared vs tenant schema split

**Public schema:**

- `tenants`
- `super_admins`
- `audit_events_global`
- Provisioning metadata (migration state per tenant, managed by Triplex)

**Per-tenant schema (one copy per tenant):**

- `users`, `user_identities`, `sessions`
- `idp_configurations`
- `groups`, `memberships`
- `sections` (seeded from the code-defined registry), `subsections`
- `section_acls`, `subsection_acls`
- `audit_events`

## Data model

Field-level migration detail belongs in the implementation plan, not this spec. The shape below is what the implementation plan must honour.

### Public schema

- **`tenants`**
  - `id` (uuid), `slug` (unique, used for subdomain), `name`, `status` (`active` | `provisioning` | `suspended`)
  - `theme` (jsonb: `logo_url`, `primary`, `secondary`, `accent`, `font`, any other design tokens exposed to Tailwind via CSS custom properties)
  - `enabled_sections` (array of section keys, a subset of the 14 canonical keys)
  - `allow_local_login` (boolean, default true)
  - `session_idle_timeout_minutes` (int, default 480)
  - `session_absolute_timeout_days` (int, default 30)
  - `audit_retention_days` (int, default 2555 — roughly 7 years)
  - `inserted_at`, `updated_at`

- **`super_admins`** — platform-level operators, fully separate from tenant users. Local credentials only in Phase 0. Fields: `id`, `email`, `hashed_password`, `name`, `status`, `last_login_at`.

- **`audit_events_global`** — cross-tenant events (tenant lifecycle, super-admin actions). See audit schema below.

### Tenant schema

- **`users`** — `id`, `email` (unique within tenant), `name`, `status` (`invited` | `active` | `suspended`), `hashed_password` (nullable; null if SSO-only), `last_login_at`.

- **`user_identities`** — federated identity links. `user_id`, `provider` (`oidc` | `saml` | `local`), `provider_subject`, `raw_claims` (jsonb). Unique on `(provider, provider_subject)`. One user may have multiple identities (e.g., OIDC plus local fallback).

- **`idp_configurations`** — per-tenant IdP config. `id`, `kind` (`oidc` | `saml`), `name` (display label), `discovery_url` (OIDC) or `metadata_xml` (SAML), `client_id`, `client_secret` (encrypted at rest via a platform-managed key), `claim_mappings` (jsonb: which claim maps to email, name, groups), `provisioning_mode` (`strict` | `auto_create` | `link_only`), `default_group_ids` (for `auto_create`), `enabled` (bool), `is_default` (bool). At most one `is_default: true` per tenant.

- **`sessions`** — server-side session records, token cookie references a row. `id`, `user_id`, `token` (hashed), `expires_at`, `last_seen_at`, `ip`, `user_agent`, `created_at`. "Sign out everywhere" deletes all rows for a user.

- **`groups`** — `id`, `name`, `description`, `kind` (`system` | `custom`). System seeds on tenant provisioning: `all_staff`, `super_users`, `people_and_culture`, `it`, `finance`, `communications`, `compliance_officers`. Seeds are starting points — tenants can rename, add, or remove them. `all_staff` is special: auto-populated with every active user.

- **`memberships`** — `user_id`, `group_id`, unique together. `all_staff` membership is maintained by an `Accounts` callback on user activate/deactivate rather than manual assignment.

- **`sections`** — seeded from the code-defined registry on tenant provisioning. Fields: `key` (one of the 14 canonical keys), `name`, `enabled` (mirrors the tenant's `enabled_sections` for ease of join). Not user-created.

- **`subsections`** — `id`, `section_key`, `slug`, `name`, `description`. Only one level deep; no `parent_subsection_id` column exists, so the schema itself prevents nesting. Unique on `(section_key, slug)`.

- **`section_acls`** — `section_key`, `principal_type` (`user` | `group`), `principal_id`, `capability` (`view` | `edit` | `approve`), `granted_by`, `granted_at`. Unique on `(section_key, principal_type, principal_id, capability)`.

- **`subsection_acls`** — same shape but scoped to `(section_key, subsection_slug)`. Presence of any row for a principal on a subsection **overrides** the parent section for that principal. Absence falls through to the parent.

- **`audit_events`** — see audit schema below.

### Audit schema

Both `audit_events` (tenant) and `audit_events_global` (public) share this shape:

- `id` (uuid)
- `actor_id` (nullable — system events have no actor)
- `actor_type` (`user` | `system` | `super_admin`)
- `action` (string, e.g., `user.login`, `section_acl.granted`, `tenant.created`)
- `resource_type` (nullable, e.g., `User`, `SectionAcl`, `Tenant`)
- `resource_id` (nullable)
- `changes` (jsonb — a diff of old/new values, with redactions applied)
- `context` (jsonb — `ip`, `user_agent`, `request_id`, and any action-specific metadata)
- `occurred_at` (timestamptz)

Indexes: `(actor_id, occurred_at)`, `(resource_type, resource_id, occurred_at)`, `(action, occurred_at)`.

## Permissions

### Capabilities

Phase 0 defines a fixed capability set: `view`, `edit`, `approve`. No custom capabilities. Phase 1 primitives may introduce primitive-specific rules on top (e.g., "publish" for documents) but do not add new columns to `section_acls`; they build those rules on top of view/edit/approve plus primitive state.

### Resolution algorithm

Single policy module `Authorization.Policy`. Every controller, LiveView, and nav-rendering helper that gates access calls this module. No ad-hoc permission checks elsewhere.

```
can?(user, capability, target) where target is {section_key} or {section_key, subsection_slug}

principals = [{:user, user.id}] ++ [{:group, gid} for gid in user.group_ids]

if target is a subsection:
  subsection_rows = subsection_acls where
    section_key = target.section_key and
    subsection_slug = target.subsection_slug and
    principal in principals

  if any subsection_row exists for this principal (any capability):
    # child overrides parent for this principal
    grant = any(row.capability == capability for row in subsection_rows matching this principal)
    return grant

  # fall through to section

section_rows = section_acls where
  section_key = target.section_key and
  principal in principals and
  capability = capability

return section_rows is non-empty
```

Override semantics: if a principal has *any* subsection ACL entry, that principal's access to that subsection is determined entirely by subsection ACLs — the parent section is not consulted for that principal. If a principal has no subsection entry, the parent is consulted. This gives the HR "locked staff-docs" case a clean expression: subsection grants to `people_and_culture` only; absence of a row for `all_staff` in the subsection means `all_staff` falls through to the parent, and the parent intentionally has no row for `all_staff`.

### Principals

Either a group or a user. UI favours groups ("Grant access to a group (recommended)" vs "Grant to individual user"). Group grants are the norm; user grants exist for the edge cases the brief calls out.

### `all_staff` handling

Rather than writing one ACL row per user, the `all_staff` group is auto-populated. Default tenant seeds use `all_staff:view` on the sections that the brief marks as "all staff (read)".

### Default ACLs on tenant provisioning

A seed script writes ACL entries per the brief's permission table for each enabled section. These are starting points; admins change them through the ACL UI. The mapping lives in code next to the section registry so it stays reviewable.

## Authentication

### Login page

`GET /login` on a tenant subdomain renders:

- One SSO button per enabled `idp_configurations` row; the default IdP is visually prominent.
- Local email/password form, shown only if `tenants.allow_local_login` is true.

### OIDC

1. `/auth/oidc/:idp_id/start` — build authorize URL from the discovery document, store `state` and `nonce` in the session, redirect.
2. `/auth/oidc/callback` — validate `state`, exchange the code, verify the ID token signature against the discovery JWKS and verify claims (iss, aud, nonce, exp).
3. `Accounts.upsert_from_idp(tenant, idp, claims)` — look up `user_identities` by `(provider, provider_subject)`. If present, return the user. If absent, apply the IdP's `provisioning_mode`.
4. Create a session; audit `user.login` with `method: :oidc`, `idp_id`, `ip`, `user_agent`; redirect to the intended target or the dashboard.

### SAML

Same shape via POST binding. Signed assertions; validate signature against configured metadata; verify `NotBefore`/`NotOnOrAfter`, audience, and recipient. Same `Accounts.upsert_from_idp/3` interface.

### Local auth

Email/password, Argon2 hashing, rate-limited per-IP and per-email with exponential backoff. Session cookie references a server-side session row. Password reset via signed, single-use, time-bounded token emailed to the user. **No self-registration** — users exist because an admin invited them.

### Provisioning modes (per IdP)

- `strict` — the email claim must match an existing active user; otherwise login fails with an audit row of `user.login_failed` reason `user_not_found`.
- `auto_create` — on first successful SSO, create a `users` row and a `user_identities` row, then add memberships from `default_group_ids`. Suitable for orgs where the IdP is the source of truth for employees.
- `link_only` — the email claim must match an existing user; the first SSO prompts for the local password to confirm the link, then creates the `user_identities` row. Subsequent logins skip the prompt.

### Invitations

An admin with permission invites by email → pending `users` row → signed, single-use invite token emailed. The invitee sets a password (local flow) or is sent to the tenant's default IdP (`strict`/`link_only`). Audit: `user.invited`, `user.activated`.

### Sessions

- Server-side session records in `sessions`. Cookie holds a token that is hashed and matched against `sessions.token`.
- Idle timeout per tenant (`session_idle_timeout_minutes`); absolute timeout per tenant (`session_absolute_timeout_days`).
- Every request updates `sessions.last_seen_at`. A sweeper job (scheduled via Oban or an equivalent) deletes expired sessions and emits a `session.expired` audit row (system actor).
- "Sign out everywhere" deletes all sessions for the user and audits each deletion.

### Super-admin auth

Separate login on the platform host. Local credentials only in Phase 0. All super-admin actions write to `audit_events_global`. Super-admins can manage tenant records, theme, `enabled_sections`, IdP catalogue, and read tenant audit logs; they cannot read tenant content or impersonate tenant users in Phase 0.

## Audit

### Scope in Phase 0

Tenant events (`audit_events`):

- Auth: `user.login` (with method), `user.login_failed` (with reason), `user.logout`, `session.expired`, `session.revoked`, `password.reset_requested`, `password.reset_completed`.
- Account lifecycle: `user.invited`, `user.activated`, `user.deactivated`, `user.updated` (with diff).
- Group: `group.created`, `group.updated`, `group.deleted`, `membership.added`, `membership.removed`.
- Permissions: `section_acl.granted`, `section_acl.revoked`, `subsection_acl.granted`, `subsection_acl.revoked`, `subsection.created`, `subsection.updated`, `subsection.deleted`.
- IdP config: `idp.created`, `idp.updated`, `idp.deleted`, `idp.enabled`, `idp.disabled` — with client secrets redacted.

Platform events (`audit_events_global`):

- Tenant lifecycle: `tenant.created`, `tenant.suspended`, `tenant.resumed`, `tenant.theme_updated`, `tenant.sections_toggled`.
- Super-admin: `super_admin.login`, `super_admin.login_failed`, a generic `super_admin.action` wrapper for other ops.

### Integrity

- Append-only by convention. No public API to update or delete `audit_events`. Only a retention sweeper, scoped to a single dedicated module and called from a scheduled job, can purge rows beyond the tenant's `audit_retention_days`. The sweeper writes a `system` actor audit row for each purge batch recording the date range removed.
- Audit writes are in the same DB transaction as the mutation they record. No fire-and-forget writes that can silently drop events.
- Secrets and password fields are redacted by `Audit.changeset_diff` using a per-schema redaction list declared on each Ecto schema module.
- Every row carries `actor`, `occurred_at`, `request_id`, `ip`, `user_agent` wherever those exist for the calling context.

### Public API of the `Audit` context

- `Audit.log(action, opts)` — opts: `actor`, `resource`, `changes`, `context`, `scope` (`:tenant` | `:global`).
- `Audit.changeset_diff(old_struct, new_struct, opts)` — utility that produces a jsonb diff honouring the schema's redaction list.
- `Audit.list(filters, pagination)` — queryable for the audit viewers.
- `Audit.history_for(resource_type, resource_id)` — used by the per-record history view; Phase 1 primitives call this directly.

### Viewers

- **Tenant audit log viewer** under the compliance section. Filters: actor, action, resource_type, resource_id, date range. CSV export. Access controlled by the section ACL on `compliance` (`view`).
- **Per-record history view** — a reusable component that renders the sequence of `changes` diffs for a given resource_type + resource_id. Phase 0 consumers: user edits, ACL changes, IdP config changes. Phase 1 primitives (documents, forms) consume the same component.
- **Super-admin viewer** for `audit_events_global` on the platform host.

## Application shell

### Section registry

The catalogue of 14 sections is declared in code as a module-level list:

```
%{
  key: :hr,
  name: "HR & People Services",
  icon: "users",
  default_capabilities: [:view, :edit, :approve],
  supports_subsections: true,
  default_acls: [{group: :all_staff, capability: :view}, {group: :people_and_culture, capability: :edit}, {group: :people_and_culture, capability: :approve}]
}
```

The registry is source-controlled. Tenants choose their subset via `enabled_sections`; adding a 15th section requires a code change and a migration (intentional — sections are structural, not runtime data).

### Theming

Tenant `theme` is resolved per-request and exposed as CSS custom properties (`--color-primary`, `--color-secondary`, `--color-accent`, `--font`) on the `<html>` element via the root layout. Tailwind components reference these custom properties. Logo is an `<img>` driven by `theme.logo_url`. A new brand = a new `tenants` row + an uploaded logo; no code change, no deploy.

### Navigation

Assembled at render time from `enabled_sections` intersected with the user's view-capable sections per the policy. Sections the user cannot view do not appear in the nav. Subsections with distinct permissions are linked as children of their section.

## Testing

- **Unit tests for `Authorization.Policy`** — property-style, table-driven. Every combination of (section ACL, subsection ACL, group, user, capability, presence/absence of subsection override) with an explicit expected outcome. This module is the one that cannot be wrong.
- **Context tests** for `Tenants`, `Accounts`, `Authorization`, `Audit`, against a real Postgres sandbox. No mocking the database.
- **Multi-tenant isolation tests**: under normal operation, under a forgotten-prefix bug, and under concurrent requests, assert that Tenant A queries never return Tenant B rows.
- **OIDC integration test** with a mock IdP fixture.
- **SAML integration test** with a static signed-assertion fixture.
- **Local auth end-to-end** test including invitation, activation, login, reset.
- **Audit coverage tests**: every mutating path in Phase 0 has an assertion that the corresponding audit row was written with the expected actor, action, and diff shape. Redaction is tested directly.
- **Browser tests** (Wallaby or Playwright): local login, OIDC login via mock IdP, nav changes when a section ACL is granted or revoked, subsection override visible in UI.

## Observability

- `:telemetry` events for tenant resolution, auth attempts (success/failure), permission checks (with outcome), audit writes.
- Structured JSON logs enriched with `tenant_id`, `user_id`, `request_id`.
- LiveDashboard enabled behind super-admin auth on the platform host only.
- `/healthz` endpoint: DB connectivity, migration state, count of provisioned tenants.

## Provisioning

A mix task `mix atrium.provision_tenant` creates the public record, the tenant schema (via Triplex), runs migrations, and seeds system groups, sections, default IdP-less configuration, and default ACLs — atomically. A failing step rolls back both the public record and any partially-created schema.

## Open questions deferred to implementation planning

- Encryption-at-rest mechanism for `client_secret` on `idp_configurations` (application-level with Cloak vs Postgres pgcrypto). Implementation plan to choose.
- Background job runner choice (Oban is the default assumption).
- Precise rate-limit parameters for local login.
- Precise CSV export format and size cap for the audit viewer.

These do not change the architecture; they are implementation-level decisions with established good answers.
