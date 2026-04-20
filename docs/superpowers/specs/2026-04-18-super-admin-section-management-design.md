# Super Admin Section Management Design

## Goal

Allow super admins to customize the display name and icon for each of the 14 platform sections via a dedicated UI in the super admin panel. Overrides are stored in a DB table; the app falls back to `SectionRegistry` hardcoded defaults when no override exists.

## Architecture

Sections remain code-defined in `SectionRegistry`. A new `section_customizations` table (public schema, non-tenant) stores per-section overrides. `AppShell` merges customizations over defaults at nav build time. The super admin panel gets a `/super/sections` listing and `/super/sections/:key/edit` form.

**Tech Stack:** Phoenix 1.8, Ecto, PostgreSQL, `atrium-*` CSS design system, no LiveView, no Tailwind, Heroicons SVG (inline).

---

## Components

### 1. Migration + Schema

New migration creates `section_customizations` table in the public (non-tenant) schema:

```
section_customizations
  id            :bigserial PK
  section_key   :string NOT NULL UNIQUE
  display_name  :string (nullable — nil means use default)
  icon_name     :string (nullable — nil means use default)
  inserted_at   :utc_datetime
  updated_at    :utc_datetime
```

Ecto schema: `Atrium.Sections.SectionCustomization` — no prefix (public schema).

### 2. `Atrium.Sections` Context

- `list_customizations/0` — returns all rows as a map keyed by `section_key`
- `get_customization/1` — returns customization for a section key or nil
- `upsert_customization/2` — inserts or updates override for a section key

### 3. `SectionRegistry` Extension

New function `all_with_overrides/0`:
- Calls `Sections.list_customizations/0` in one query
- Merges into `@sections` list: DB `display_name` replaces `name` if present; DB `icon_name` replaces `icon` if present
- Returns full list with overrides applied

### 4. `AtriumWeb.HeroiconsSVG`

Module holding a map of all ~300 Heroicons outline icon names → SVG path data strings. Used by a view helper `icon_svg(name, opts \\ [])` that renders a `<svg>` tag with the path inline. Falls back to a generic "square" icon if name is unknown.

### 5. `SuperAdmin.SectionController`

Routes:
```
GET  /super/sections           :index
GET  /super/sections/:key/edit :edit
PUT  /super/sections/:key      :update
```

Actions:
- `index/2` — calls `SectionRegistry.all_with_overrides/0`, renders listing
- `edit/2` — fetches section from registry, fetches existing customization, renders form
- `update/2` — calls `Sections.upsert_customization/2`, redirects to index on success, re-renders edit on error

Unknown section key → `raise Ecto.NoResultsError` (renders 404).

### 6. Templates

**`super_admin/section_html/index.html.heex`**
- Page title: "Sections"
- Table/card list of all 14 sections: icon preview, current display name, section key, "Edit" link
- Uses `atrium-*` CSS classes

**`super_admin/section_html/edit.html.heex`**
- Form with:
  - Display name text input (placeholder: section default name)
  - Icon picker: searchable grid of all ~300 Heroicons
    - Text input filters icons client-side via vanilla JS (`oninput` filter)
    - Hidden input `section[icon_name]` stores selected icon name
    - Each icon rendered as inline SVG with label below
    - Selected icon highlighted with border
  - "Save" + "Cancel" buttons
- Shows current icon name below picker

### 7. Super Admin Sidebar Update

`super_admin.html.heex` — add "Sections" nav entry between "Dashboard" and "Tenants":
```
Dashboard → Sections → Tenants
```

### 8. `AppShell` Update

`AppShell.nav_for_user/3` calls `SectionRegistry.all_with_overrides/0` instead of accessing `@sections` directly.

---

## Data Flow

1. Super admin visits `/super/sections` → index renders all 14 sections with merged name/icon
2. Super admin clicks "Edit" on a section → edit form shows current values (DB override if exists, else default)
3. Super admin selects icon from grid, optionally changes display name, submits
4. `update/2` calls `upsert_customization/2` → INSERT ... ON CONFLICT DO UPDATE
5. Redirect to index
6. Next tenant nav render: `AppShell` calls `all_with_overrides/0` → one DB query → merges → nav reflects new icon/name

---

## Error Handling

- Unknown section key in edit/update → 404
- Invalid icon name (not in known set) → changeset validates inclusion
- Blank display name submitted → treated as nil (use default); empty string normalized to nil in changeset
- DB error → standard Phoenix 500

---

## Testing

- `Atrium.SectionsTest` — unit tests for `upsert_customization`, `list_customizations`, `all_with_overrides/0` merge behavior (no override, partial override, full override)
- `SuperAdmin.SectionControllerTest` — index renders 14 sections, edit renders form with defaults, update persists override and redirects, update with invalid icon returns error, unknown key returns 404
