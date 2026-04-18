# Atrium — Phase 1b: Form Builder

**Date:** 2026-04-18
**Status:** Approved design
**Scope:** Phase 1b of Atrium. Delivers the `Forms` context: tenant-scoped form builder with drag-and-drop field design, versioned form schemas, form submission with multi-party completion tracking, notification routing (email for external reviewers, stub for internal), and full audit integration.

Phase 1c (in-app notification inbox, richer review dashboard, file upload storage backend) is out of scope here. Phase 1b produces a standalone, shippable feature.

---

## Product context

Atrium needs self-service process forms for HR, operations, and compliance workflows — leave requests, equipment orders, new starter onboarding, incident reports. Forms are placed inside any enabled section. They are designed by staff with `:edit` permission using a drag-and-drop builder, published as immutable versioned schemas, and filled in by any authenticated user. Submitted forms are routed to one or more reviewers (internal users, groups, or external email addresses) who must each mark their copy complete. External contractors receive a tokenised email link allowing unauthenticated completion.

---

## Goals

- Drag-and-drop form builder with field types: text (single/multi-line), number, radio, select (dropdown), checkbox group, date, file upload (submission-scoped, storage deferred to Phase 1c)
- Per-field conditional logic: show/hide a field based on another field's value
- ISO-aligned lifecycle: `draft → published → archived`. Only draft forms can be edited.
- Immutable `FormVersion` snapshot on each publish — full schema history retained.
- Multi-party completion: each submission creates one `FormSubmissionReview` per notification recipient; submission status flips to `completed` when all reviews are done.
- External reviewer support: Swoosh email with a Phoenix.Token-signed link; token encodes `{submission_id, reviewer_email}`, allows unauthenticated review completion.
- Internal reviewer notification: Oban worker enqueues email stubs; full in-app inbox deferred to Phase 1c.
- Audit trail: every create, publish, archive, submission, review completion, and submission completion written to `audit_events`.
- Authorization gates: `:view` to list/fill forms, `:edit` to create/publish, `:approve` to archive.

---

## Non-goals

- File upload storage backend (Phase 1c)
- In-app notification inbox or badge (Phase 1c)
- Richer review dashboard (Phase 1c)
- Real-time collaboration on form builder
- Form embedding inside Documents
- Cross-section form sharing
- Calculated/formula fields
- Form branching beyond single-field show/hide conditions

---

## Stack

Existing stack. No new libraries. Vue 3 island (already in use) for the drag-and-drop builder. Swoosh (already in use) for external reviewer emails. Oban (already in use) for notification workers. Phoenix.Token for external reviewer links.

---

## Architecture

### New context: `Atrium.Forms`

Tenant-schema context. Owns four schemas:

**`Form`** — the living record:
- `id` (:binary_id)
- `title` (:string, required)
- `section_key` (:string, required) — must be a valid SectionRegistry key
- `subsection_slug` (:string, nullable)
- `status` (:string, default "draft") — enum: draft | published | archived
- `current_version` (:integer, default 1)
- `author_id` (:binary_id)
- `notification_recipients` (:map, default []) — jsonb array: `[{type: "user"|"group"|"email", id: uuid_or_nil, email: string_or_nil}]`
- timestamps

**`FormVersion`** — immutable schema snapshot on each publish:
- `id` (:binary_id)
- `form_id` (:binary_id, FK → forms, on_delete: delete_all)
- `version` (:integer)
- `fields` (:map) — jsonb array of field definitions (see Field Schema below)
- `published_by_id` (:binary_id)
- `published_at` (:utc_datetime_usec)

No `timestamps` macro on versions — `published_at` is the only timestamp, set explicitly.

**`FormSubmission`** — a user's completed response:
- `id` (:binary_id)
- `form_id` (:binary_id, FK → forms)
- `form_version` (:integer) — the version at time of submission
- `submitted_by_id` (:binary_id)
- `submitted_at` (:utc_datetime_usec)
- `status` (:string, default "pending") — enum: pending | completed
- `field_values` (:map) — jsonb: `{field_id => value}`
- `file_keys` (:map, default []) — jsonb array of storage refs for file fields (populated Phase 1c)
- timestamps

**`FormSubmissionReview`** — one per notification recipient per submission:
- `id` (:binary_id)
- `submission_id` (:binary_id, FK → form_submissions, on_delete: delete_all)
- `reviewer_type` (:string) — "user" | "email"
- `reviewer_id` (:binary_id, nullable) — set when reviewer_type is "user"
- `reviewer_email` (:string, nullable) — set when reviewer_type is "email"
- `status` (:string, default "pending") — enum: pending | completed
- `completed_at` (:utc_datetime_usec, nullable)
- `completed_by_id` (:binary_id, nullable) — internal user who clicked complete (nil for external)
- timestamps

### Field Schema (jsonb)

Each entry in `FormVersion.fields`:
```json
{
  "id": "uuid-string",
  "type": "text|textarea|number|radio|select|checkbox_group|date|file",
  "label": "string",
  "required": true|false,
  "order": integer,
  "options": ["string"],
  "conditions": [
    { "field_id": "uuid-string", "operator": "eq|neq|contains", "value": "string" }
  ]
}
```

`options` is only populated for radio, select, checkbox_group types. `conditions` is an AND list — all must be true for the field to be shown.

### Authorization model

Reuses existing `Policy.can?/4`:

| Action | Required capability |
|--------|-------------------|
| List forms / view form | `:view` on `{:section, section_key}` |
| Fill in and submit a form | `:view` on the section |
| Create / edit draft | `:edit` on the section |
| Publish | `:edit` on the section |
| Archive | `:approve` on the section |
| View submissions | `:edit` on the section |
| Complete a review (internal) | `:view` on the section |
| Complete a review (external) | Phoenix.Token — no session required |

### Form lifecycle

```
draft ──(publish)──► published ──(archive)──► archived
  ▲
  └── edit only allowed when status is draft
```

- `publish`: draft → published. Creates a `FormVersion` snapshot. Actor needs `:edit`.
- `archive`: published → archived. Actor needs `:approve`.
- Re-editing a published form: `Forms.reopen_form/2` sets status back to `draft` and increments `current_version`. Original `FormVersion` snapshots are retained. Actor needs `:edit`.
- Direct edit of fields is only allowed when status is `draft`.

### Submission flow

1. User GET `/sections/:section_key/forms/:id/submit` — server renders the form from the latest published `FormVersion`. Field visibility conditions evaluated client-side via a small inline JS snippet (no framework needed).
2. User POSTs to `/sections/:section_key/forms/:id/submit` — server creates `FormSubmission` + one `FormSubmissionReview` per entry in `Form.notification_recipients`.
3. `Atrium.Forms.NotificationWorker` (Oban) is enqueued. It fans out:
   - External (`reviewer_type: "email"`): Swoosh email with a Phoenix.Token link to `/forms/review/:token`
   - Internal (`reviewer_type: "user"`): stub log entry; full in-app inbox deferred to Phase 1c
4. Reviewer visits their link (or navigates directly if internal), views submission detail, clicks "Mark complete".
5. POST `/sections/:section_key/forms/:id/submissions/:sid/complete` (internal) or POST `/forms/review/:token/complete` (external).
6. Server marks `FormSubmissionReview` completed. If all reviews for the submission are now completed, `FormSubmission.status` flips to `completed` and a `form.submission_completed` audit event is written.

### External reviewer token

```elixir
Phoenix.Token.sign(AtriumWeb.Endpoint, "form_review", %{
  submission_id: sid,
  reviewer_email: email
})
```

Max age: 30 days. Verified in `ExternalReviewController` before rendering or completing. Token is single-use at the DB level — once the review is `completed`, subsequent token use returns a "already completed" message rather than an error.

### Context API

```elixir
# Forms CRUD
Forms.create_form(prefix, attrs, actor_user)
Forms.get_form!(prefix, id)
Forms.list_forms(prefix, section_key, opts \\ [])
Forms.update_form(prefix, form, attrs, actor_user)

# Lifecycle
Forms.publish_form(prefix, form, fields, actor_user)
Forms.archive_form(prefix, form, actor_user)

# Submissions
Forms.create_submission(prefix, form, field_values, actor_user)
Forms.get_submission!(prefix, id)
Forms.list_submissions(prefix, form_id, opts \\ [])

# Reviews
Forms.complete_review(prefix, review, actor_user_or_nil)
Forms.get_review_by_token(prefix, token)

# Versions
Forms.reopen_form(prefix, form, actor_user)
Forms.list_versions(prefix, form_id)
```

Every mutating function:
1. Validates the operation is legal (status guard, token validity).
2. Inserts/updates the record.
3. Calls `Audit.log/3` with actor, resource, and diff.
4. On submission creation, enqueues `NotificationWorker`.

### Web layer

Controller-based, server-rendered HEEx. No LiveView. Vue 3 island for the drag-and-drop builder only.

**Routes** (inside authenticated tenant scope, after RequireUser + AssignNav):
```
get  /sections/:section_key/forms                              FormController :index
get  /sections/:section_key/forms/new                         FormController :new
post /sections/:section_key/forms                             FormController :create
get  /sections/:section_key/forms/:id                         FormController :show
get  /sections/:section_key/forms/:id/edit                    FormController :edit
put  /sections/:section_key/forms/:id                         FormController :update
post /sections/:section_key/forms/:id/publish                 FormController :publish
post /sections/:section_key/forms/:id/archive                 FormController :archive
get  /sections/:section_key/forms/:id/submit                  FormController :submit_form
post /sections/:section_key/forms/:id/submit                  FormController :create_submission
get  /sections/:section_key/forms/:id/submissions             FormController :submissions_index
get  /sections/:section_key/forms/:id/submissions/:sid        FormController :show_submission
post /sections/:section_key/forms/:id/submissions/:sid/complete FormController :complete_review
```

**External reviewer routes** (unauthenticated, outside tenant auth scope):
```
get  /forms/review/:token         ExternalReviewController :show
post /forms/review/:token/complete ExternalReviewController :complete
```

**Vue island:** `FormBuilderIsland.vue` mounted on the edit page via `data-vue="FormBuilderIsland"`. Props: `{fields: [...]}`. Saves field JSON to `<input type="hidden" name="form[fields]">` on form submit. No API calls — pure client-side state serialised on submit.

### File structure

```
priv/repo/tenant_migrations/
  20260422000001_create_forms.exs
  20260422000002_create_form_versions.exs
  20260422000003_create_form_submissions.exs
  20260422000004_create_form_submission_reviews.exs

lib/atrium/forms/
  form.ex
  form_version.ex
  form_submission.ex
  form_submission_review.ex
  notification_worker.ex

lib/atrium/forms.ex

lib/atrium_web/controllers/
  form_controller.ex
  form_html.ex
  form_html/
    index.html.heex
    show.html.heex
    new.html.heex
    edit.html.heex
    submit_form.html.heex
    submissions_index.html.heex
    show_submission.html.heex
  external_review_controller.ex
  external_review_html.ex
  external_review_html/
    show.html.heex

assets/js/islands/
  FormBuilderIsland.vue

test/atrium/forms_test.exs
test/atrium_web/controllers/form_controller_test.exs
test/atrium_web/controllers/external_review_controller_test.exs
```

### Audit events emitted

| Event | When |
|-------|------|
| `form.created` | `create_form` success |
| `form.updated` | `update_form` success |
| `form.published` | `publish_form` success |
| `form.archived` | `archive_form` success |
| `form.submission_created` | `create_submission` success |
| `form.review_completed` | `complete_review` success |
| `form.submission_completed` | all reviews completed, status flips |

### Notification worker

```elixir
defmodule Atrium.Forms.NotificationWorker do
  use Oban.Worker, queue: :notifications

  def perform(%Oban.Job{args: %{"prefix" => prefix, "submission_id" => sid}}) do
    # load submission + reviews
    # for each review:
    #   if reviewer_type == "email" → send Swoosh email with token link
    #   if reviewer_type == "user"  → log stub (Phase 1c: deliver to inbox)
    :ok
  end
end
```

### Testing strategy

- `Atrium.TenantCase` for all context tests.
- Context tests cover: CRUD, publish/archive lifecycle, version snapshots, submission creation, review completion, auto-complete when all reviews done, audit events.
- Controller tests cover: 200/403 responses, form builder submit (field JSON round-trip), submission creation, internal review completion.
- External reviewer controller tests: valid token renders show, POST completes review, expired/invalid token returns 400, already-completed token returns graceful message.
- Oban worker tested with `Oban.Testing` — assert job enqueued on submission creation, perform inline.

---

## Design decisions

**Why Vue island for builder only?** The builder requires client-side drag-and-drop state that is impractical in server-rendered HEEx. Everything else (rendering, submitting, reviewing) is pure server-rendered — consistent with Phase 1a.

**Why Phoenix.Token for external reviewers?** Already in the stack (used for password reset, invitation links). No new dependency. 30-day TTL matches typical review cycles for contractor workflows.

**Why jsonb for field_values?** Form schemas change per version. Storing responses as typed columns would require schema migrations per form — not viable for user-defined forms. jsonb with version reference is the correct model.

**Why notification_recipients on Form rather than FormVersion?** Recipients are an operational concern (who gets notified), not part of the form schema (what fields exist). They can change between submissions without creating a new version.

**Why file_keys deferred to Phase 1c?** File storage backend (S3 vs local, tenant isolation, encryption) is a cross-cutting concern that applies to both form attachments and document attachments. Designing it once in Phase 1c avoids inconsistency.

---

## Open questions resolved

- **External contractor access?** Phoenix.Token signed link — no account required, no session.
- **Group notification recipients?** Supported — `{type: "group", id: group_id}`. NotificationWorker expands group membership at notification time.
- **Re-editing a published form?** Bumps `current_version`, creates new draft. Old versions retained. Existing submissions reference their version snapshot.
- **Submission visibility?** Submitters see their own submissions. Users with `:edit` see all submissions for forms in their section.
