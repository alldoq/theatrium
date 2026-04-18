# Learning & Development Design

## Goal

Allow staff to browse a course catalog, view course materials (linked documents and external URLs), and self-report completion. People & Culture staff manage courses (create, edit, archive).

## Architecture

New tenant-scoped tables (`courses`, `course_materials`, `course_completions`) managed by the `Atrium.Learning` context. `LearningController` handles all UI at `/learning`. No quiz, scoring, or manager sign-off — self-reported completion only.

**Tech Stack:** Phoenix 1.8, Ecto, PostgreSQL (Triplex tenant prefix), `atrium-*` CSS, no LiveView, no Tailwind.

---

## Components

### 1. Database Schema

**`courses`** (tenant-scoped)
```
id             :bigserial PK
title          :string NOT NULL
description    :text
category       :string
status         :string NOT NULL DEFAULT 'draft'  -- draft | published | archived
created_by_id  :bigint FK users
inserted_at    :utc_datetime
updated_at     :utc_datetime
```

**`course_materials`** (tenant-scoped)
```
id          :bigserial PK
course_id   :bigint FK courses NOT NULL
type        :string NOT NULL  -- document | url
position    :integer NOT NULL DEFAULT 0
title       :string NOT NULL
document_id :bigint FK documents (nullable — only for type=document)
url         :string (nullable — only for type=url)
inserted_at :utc_datetime
updated_at  :utc_datetime
```

**`course_completions`** (tenant-scoped)
```
id           :bigserial PK
course_id    :bigint FK courses NOT NULL
user_id      :bigint FK users NOT NULL
completed_at :utc_datetime NOT NULL
UNIQUE (course_id, user_id)
```

### 2. Ecto Schemas

- `Atrium.Learning.Course` — no prefix (Triplex injects at query time)
- `Atrium.Learning.CourseMaterial` — belongs_to Course; validates `url` starts with `http://` or `https://` when type=url; validates `document_id` present when type=document
- `Atrium.Learning.CourseCompletion` — belongs_to Course + User; unique_constraint on (course_id, user_id)

### 3. `Atrium.Learning` Context

- `list_courses(prefix, opts \\ [])` — returns published courses; editors also see draft/archived via `status: :all` opt; ordered by category then title
- `get_course!(prefix, id)` — raises if not found
- `create_course(prefix, attrs)` — inserts with status: draft
- `update_course(prefix, course, attrs)` — updates title/description/category
- `archive_course(prefix, course)` — sets status: archived; only valid from published
- `publish_course(prefix, course)` — sets status: published from draft
- `list_materials(prefix, course_id)` — ordered by position
- `add_material(prefix, course_id, attrs)` — inserts material
- `delete_material(prefix, material_id)` — removes material
- `complete_course(prefix, course_id, user_id)` — upserts completion row (no-op if exists)
- `uncomplete_course(prefix, course_id, user_id)` — deletes completion row
- `completed?(prefix, course_id, user_id)` — boolean
- `completion_count(prefix, course_id)` — integer count for editors

### 4. `LearningController`

Routes:
```
GET    /learning                  :index
GET    /learning/new              :new
POST   /learning                  :create
GET    /learning/:id              :show
GET    /learning/:id/edit         :edit
PUT    /learning/:id              :update
POST   /learning/:id/publish      :publish
POST   /learning/:id/archive      :archive
POST   /learning/:id/complete     :complete
DELETE /learning/:id/complete     :uncomplete
```

Authorization plug: `:view` for index/show/complete/uncomplete; `:edit` for new/create/edit/update/publish/archive.

Draft/archived courses: `show` returns 404 for non-editors.

### 5. Templates

**`learning_html/index.html.heex`**
- Page title: "Learning & Development"
- Published courses grouped by category — card grid, each card: title, category badge, material count, green checkmark if completed by current user
- Editors see "New course" button + separate table of draft/archived courses below

**`learning_html/show.html.heex`**
- Course title, description, category badge
- Materials list: document links (to existing doc show page) open in same tab; URL links open in new tab
- "Mark as complete" button (POST to `:complete`) if not completed; "Mark as incomplete" link (DELETE to `:uncomplete`) if completed
- Editors see completion count: "N staff completed"
- Edit/Archive buttons for editors

**`learning_html/new.html.heex` / `edit.html.heex`**
- Title (required), description (textarea), category (text input)
- Materials section: list of existing materials with delete buttons; "Add document" row (document_id hidden input + title display) and "Add URL" row (title + url inputs)
- Materials ordered by position; position managed via hidden integer inputs
- Save → draft; separate Publish button on edit form for published state

---

## Data Flow

1. P&C staff creates course (draft) → adds materials → publishes
2. Staff visits `/learning` → sees published courses with completion status
3. Staff opens course → reads materials → clicks "Mark as complete" → POST `/learning/:id/complete` → upsert completion → redirect back to show with updated state
4. Staff can click "Mark as incomplete" → DELETE `/learning/:id/complete` → removes completion row

---

## Error Handling

- Draft/archived course accessed by non-editor → 404
- Duplicate complete → no-op (upsert)
- URL material without `http(s)://` → changeset error, re-render form
- Document material with invalid document_id → changeset error
- Archive on non-published course → changeset error, redirect with flash

---

## Testing

- `Atrium.LearningTest` — list_courses filters by status, create/update/archive, complete/uncomplete toggles, completed? boolean, completion_count
- `LearningControllerTest` — index shows published only for staff, editors see drafts, show renders materials + completion button, complete/uncomplete toggles state, 404 on draft for non-editor, archive redirects
