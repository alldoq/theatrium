# Tenant Admin — User & Section Permissions Design

## Goal

Give designated tenant admins a UI to invite users, manage their section permissions (view/edit/approve per section), and toggle admin status — without requiring iex or super-admin access.

## Architecture

A new `TenantAdmin` controller namespace under `/admin`, served within the existing tenant-authenticated pipeline. A new `RequireTenantAdmin` plug gates every `/admin` route. The sidebar gains an "Admin" entry visible only when `current_user.is_admin == true`.

`is_admin` is stored as a boolean column on the tenant's `users` table (via a tenant migration). The existing `Atrium.Authorization` context handles ACL grants/revokes — no new schema tables needed.

## Data Changes

**Tenant migration** — adds `is_admin` to `users`:
```sql
ALTER TABLE users ADD COLUMN is_admin boolean NOT NULL DEFAULT false;
```

**New `Atrium.Accounts` functions:**
- `set_admin(prefix, user, bool)` — sets `is_admin`, logs `user.admin_changed` audit event
- No new query functions needed — `list_users/1` already returns all users; grants are loaded separately via `Authorization.list_section_acls/2`

## File Structure

**New files:**
- `priv/repo/tenant_migrations/20260422000010_add_is_admin_to_users.exs`
- `lib/atrium_web/plugs/require_tenant_admin.ex`
- `lib/atrium_web/controllers/tenant_admin/user_controller.ex`
- `lib/atrium_web/controllers/tenant_admin/user_html.ex`
- `lib/atrium_web/controllers/tenant_admin/user_html/index.html.heex`
- `lib/atrium_web/controllers/tenant_admin/user_html/new.html.heex`
- `lib/atrium_web/controllers/tenant_admin/user_html/show.html.heex`

**Modified files:**
- `lib/atrium/accounts.ex` — add `set_admin/3`
- `lib/atrium/tenants/user.ex` (or wherever User schema lives) — add `is_admin` field
- `lib/atrium_web/router.ex` — add `/admin` scope
- `lib/atrium_web/components/layouts/app.html.heex` — add Admin sidebar entry

## Routes

```
scope "/admin", TenantAdmin do
  pipe_through [:authenticated, :require_tenant_admin]
  get  "/users",              UserController, :index
  get  "/users/new",          UserController, :new
  post "/users",              UserController, :create       # invite
  get  "/users/:id",          UserController, :show
  post "/users/:id/permissions", UserController, :update_permissions
  post "/users/:id/toggle_admin", UserController, :toggle_admin
  post "/users/:id/suspend",  UserController, :suspend
  post "/users/:id/restore",  UserController, :restore
end
```

## Views

### `/admin/users` — User list
- Table: name, email, status badge, section count, admin badge, "Manage" link
- "Invite user" button top-right

### `/admin/users/new` — Invite form
- Fields: name (required), email (required)
- Admin toggle checkbox
- Section grid: each enabled section as a row, checkboxes for view / edit / approve
- Submit: "Send invitation"
- On success: redirect to `/admin/users/:id` with flash

### `/admin/users/:id` — User detail
- Header: name, email, status badge, admin toggle button, suspend/restore button
- Section permissions card: grid of enabled sections × capabilities (view/edit/approve)
  - Each cell is a checkbox, pre-filled from current ACLs
  - Single "Save permissions" button submits all at once
- Permissions form POSTs to `/admin/users/:id/permissions`
  - Controller computes diff: grant new, revoke removed
  - Redirects back with flash

## Permission Sync Logic

On `update_permissions` POST:
1. Load current `SectionAcl` rows for this user across all sections
2. Build desired set from submitted checkboxes: `{section_key, capability}` pairs
3. For each desired not in current → `Authorization.grant_section/5`
4. For each current not in desired → `Authorization.revoke_section/4`
5. Log `user.permissions_updated` audit event
6. Redirect to show with flash

## Plug: RequireTenantAdmin

```elixir
if current_user.is_admin, do: conn, else: 403
```

## Sidebar Entry

In `app.html.heex`, after the Audit Log entry:
```heex
<%= if assigns[:current_user] && @current_user.is_admin do %>
  <div class="atrium-sidebar-section">
    <a href="/admin/users" class="atrium-sidebar-item">
      <!-- settings icon -->
      Admin
    </a>
  </div>
<% end %>
```

## Testing

- Plug: 403 for non-admin, passes for admin
- `set_admin/3`: sets flag, emits audit event
- UserController index/show: renders correctly
- `update_permissions`: grants new, revokes removed, idempotent on no-change
- Invite with sections: user created + ACLs inserted in one flow
