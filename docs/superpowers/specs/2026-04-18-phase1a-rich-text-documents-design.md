# Atrium — Phase 1a: Rich-Text Documents

**Date:** 2026-04-18
**Status:** Approved design
**Scope:** Phase 1a of Atrium. Delivers the `Documents` context: tenant-scoped rich-text documents with version history, ISO-ready document lifecycle (draft → review → approved → archived), section/subsection placement, full audit integration, and server-rendered CRUD UI with a Trix editor island.

Phase 1b (Form Builder) and Phase 1c (File Attachments) are out of scope here. Phase 1a produces a standalone, shippable feature.

---

## Product context

Atrium needs rich-text documents for HR policies, SOPs, knowledge-base articles, department pages, and compliance records. Documents are placed inside sections (e.g., `docs`, `hr`, `departments`) and optionally scoped to a subsection. They have an ISO-driven lifecycle: drafts cannot be published without an approver review, and every version is retained indefinitely for audit.

---

## Goals

- Create, edit, and publish rich-text documents within any enabled section that supports content.
- ISO-compliant lifecycle: `draft → in_review → approved → archived`. Transition rules enforced server-side.
- Full version history: every save creates an immutable version record.
- Authorization gates: `view` to read, `edit` to create/update drafts, `approve` to transition to approved.
- Audit trail: every create, update, and status change written to `audit_events` via `Atrium.Audit.log/3`.
- Per-record history component (`AtriumWeb.Components.HistoryView`) shown on the document detail page.
- Server-rendered HEEx with a Trix editor JavaScript island for body input.
- No file attachments (Phase 1c), no form embedding (Phase 1b).

---

## Non-goals

- File attachments on documents.
- Inline forms or surveys.
- Real-time collaborative editing.
- Document templates.
- Cross-section document linking.
- Full-text search (can be added in Phase 2).

---

## Stack

Existing stack. No new libraries beyond **Trix** (already bundled with Phoenix by default via esbuild) for the rich-text editor island.

---

## Architecture

### New context: `Atrium.Documents`

Tenant-schema context. Owns two schemas:

**`Document`** — the living record:
- `id` (:binary_id)
- `title` (:string, required)
- `section_key` (:string, required) — must be a valid SectionRegistry key
- `subsection_slug` (:string, nullable) — when present, must exist in `subsections`
- `status` (:string, default "draft") — enum: draft | in_review | approved | archived
- `body_html` (:text) — Trix-produced HTML; stored as-is, escaped on render
- `current_version` (:integer, default 1) — incremented on each content save
- `author_id` (:binary_id) — the user who created the document
- `approved_by_id` (:binary_id, nullable) — set when transitioning to approved
- `approved_at` (:utc_datetime_usec, nullable)
- timestamps

**`DocumentVersion`** — immutable snapshot on every save:
- `id` (:binary_id)
- `document_id` (:binary_id, FK → documents)
- `version` (:integer)
- `title` (:string)
- `body_html` (:text)
- `saved_by_id` (:binary_id)
- `saved_at` (:utc_datetime_usec)

No `timestamps` macro on versions — `saved_at` is the only timestamp, set explicitly.

### Authorization model

Reuses existing `Policy.can?/4`:

| Action | Required capability |
|--------|-------------------|
| List/read documents | `:view` on `{:section, section_key}` (or subsection if scoped) |
| Create / save draft | `:edit` on the section |
| Submit for review | `:edit` on the section |
| Approve | `:approve` on the section |
| Archive | `:approve` on the section |

### Lifecycle state machine

```
draft ──(submit)──► in_review ──(approve)──► approved ──(archive)──► archived
  ▲                     │
  └──────(reject)───────┘
```

- `submit`: draft → in_review. Actor needs `:edit`.
- `reject`: in_review → draft. Actor needs `:approve`.
- `approve`: in_review → approved. Actor needs `:approve`. Sets `approved_by_id`, `approved_at`.
- `archive`: approved → archived. Actor needs `:approve`.
- Direct edit of body/title is only allowed when status is `draft`.

### Context API

```elixir
# CRUD
Documents.create_document(prefix, attrs, actor_user)
Documents.get_document!(prefix, id)
Documents.list_documents(prefix, section_key, opts \\ [])
Documents.update_document(prefix, doc, attrs, actor_user)

# Lifecycle
Documents.submit_for_review(prefix, doc, actor_user)
Documents.reject_document(prefix, doc, actor_user)
Documents.approve_document(prefix, doc, actor_user)
Documents.archive_document(prefix, doc, actor_user)

# History
Documents.list_versions(prefix, document_id)
```

Every mutating function:
1. Validates the transition is legal.
2. Inserts/updates the `Document`.
3. On content saves, inserts a `DocumentVersion` snapshot.
4. Calls `Audit.log/3` with actor, resource, and diff.

### Web layer

Controller-based, server-rendered. No LiveView for Phase 1a.

**Routes** (inside authenticated tenant scope, after RequireUser + AssignNav):
```
get  /sections/:section_key/documents            -> DocumentController :index
get  /sections/:section_key/documents/new        -> DocumentController :new
post /sections/:section_key/documents            -> DocumentController :create
get  /sections/:section_key/documents/:id        -> DocumentController :show
get  /sections/:section_key/documents/:id/edit   -> DocumentController :edit
put  /sections/:section_key/documents/:id        -> DocumentController :update
post /sections/:section_key/documents/:id/submit -> DocumentController :submit
post /sections/:section_key/documents/:id/reject -> DocumentController :reject
post /sections/:section_key/documents/:id/approve-> DocumentController :approve
post /sections/:section_key/documents/:id/archive-> DocumentController :archive
```

Subsection-scoped documents use the same controller with an optional `:subsection_slug` param embedded in the body or as a query param at creation time.

**Authorization in controller:** `DocumentController` calls `Policy.can?` before each action and returns 403 via the `Authorize` plug if denied.

**Trix editor island:** A small `<trix-editor>` web component in the new/edit form. Input value is submitted as a hidden field `body_html`. No JavaScript framework needed — Trix is a standalone custom element.

### File structure

```
priv/repo/tenant_migrations/
  20260421000001_create_documents.exs
  20260421000002_create_document_versions.exs

lib/atrium/documents/
  document.ex
  document_version.ex

lib/atrium/documents.ex

lib/atrium_web/controllers/
  document_controller.ex
  document_html.ex
  document_html/
    index.html.heex
    show.html.heex
    new.html.heex
    edit.html.heex

test/atrium/documents_test.exs
test/atrium_web/controllers/document_controller_test.exs
```

### Audit events emitted

| Event | When |
|-------|------|
| `document.created` | `create_document` success |
| `document.updated` | `update_document` success |
| `document.submitted` | `submit_for_review` success |
| `document.rejected` | `reject_document` success |
| `document.approved` | `approve_document` success |
| `document.archived` | `archive_document` success |

Changes use `Audit.changeset_diff/2` for content updates; status transitions record the old/new status in changes.

### Testing strategy

- `Atrium.TenantCase` for all context tests.
- Context tests cover: CRUD, lifecycle transitions (valid and invalid), version snapshots, audit events written.
- Controller tests cover: 200/403 responses, form submission, lifecycle action routes.
- No JavaScript tests for Trix — the editor is a drop-in web component, integration tested via form submission.

---

## Design decisions

**Why Trix over a custom editor?** Phoenix ships Trix by default. It produces safe HTML, handles copy-paste well, and requires zero JavaScript build configuration. For Phase 1a a custom editor would be over-engineering.

**Why no LiveView?** Documents are long-form writing. Real-time collaboration is a Phase 2+ concern. A conventional form with a Trix island is simpler, more accessible, and easier to test.

**Why server-side lifecycle enforcement rather than a state machine library?** The four states and five transitions fit in a single module with explicit guard clauses. A library would add a dependency with no meaningful reduction in code.

**Why a separate `DocumentVersion` table rather than storing versions in the document?** Versions are immutable audit records. Storing them separately keeps the `Document` table lean and makes `list_versions` a simple indexed query.

**Why `body_html` stored as-is?** Trix produces well-formed HTML. Phoenix's `raw/1` helper is used only where we control the source; user-supplied HTML from Trix is acceptable because Trix sanitises on input. We will add explicit sanitisation in Phase 2 if needed.

---

## Open questions resolved

- **Cross-section documents?** Not needed for Phase 1a. Documents belong to exactly one section.
- **Draft editing by multiple users?** Last-write-wins for now. Conflict detection is Phase 2.
- **Subsection-scoped documents?** Supported at creation time; `subsection_slug` is an optional attribute.
