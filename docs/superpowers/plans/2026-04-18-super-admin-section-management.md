# Super Admin Section Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow super admins to customize the display name and icon for each of the 14 platform sections via a `/super/sections` UI; overrides are stored in a `section_customizations` DB table and merged over `SectionRegistry` defaults at nav build time.

**Architecture:** A new `section_customizations` table (public schema, not tenant-scoped) stores per-section `display_name` and `icon_name` overrides. `SectionRegistry.all_with_overrides/0` merges DB values over hardcoded defaults in one query. `AppShell.nav_for_user/3` calls this instead of `SectionRegistry.all/0`. A `SuperAdmin.SectionController` handles index/edit/update at `/super/sections`.

**Tech Stack:** Phoenix 1.8, Ecto (public schema, no Triplex prefix), PostgreSQL, `atrium-*` CSS design system (no Tailwind, no LiveView), Heroicons outline SVGs (inline), vanilla JS for icon search filter.

---

## File Structure

**New files:**
- `priv/repo/migrations/TIMESTAMP_create_section_customizations.exs` — DB migration
- `lib/atrium/sections/section_customization.ex` — Ecto schema
- `lib/atrium/sections.ex` — context: list, get, upsert
- `lib/atrium_web/controllers/super_admin/section_controller.ex` — index/edit/update
- `lib/atrium_web/controllers/super_admin/section_html.ex` — HTML module
- `lib/atrium_web/controllers/super_admin/section_html/index.html.heex` — listing template
- `lib/atrium_web/controllers/super_admin/section_html/edit.html.heex` — edit form with icon picker
- `lib/atrium_web/helpers/heroicons.ex` — map of all ~300 Heroicons outline icon names → SVG path strings
- `test/atrium/sections_test.exs` — context unit tests
- `test/atrium_web/controllers/super_admin/section_controller_test.exs` — controller tests

**Modified files:**
- `lib/atrium/authorization/section_registry.ex` — add `all_with_overrides/0`
- `lib/atrium/app_shell.ex` — call `SectionRegistry.all_with_overrides/0`
- `lib/atrium_web/router.ex` — add section routes under `/super`
- `lib/atrium_web/components/layouts/super_admin.html.heex` — add Sections nav entry

---

### Task 1: Migration + Schema + Context

**Files:**
- Create: `priv/repo/migrations/20260418120000_create_section_customizations.exs`
- Create: `lib/atrium/sections/section_customization.ex`
- Create: `lib/atrium/sections.ex`
- Create: `test/atrium/sections_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/atrium/sections_test.exs`:

```elixir
defmodule Atrium.SectionsTest do
  use Atrium.DataCase, async: true

  alias Atrium.Sections
  alias Atrium.Sections.SectionCustomization

  describe "upsert_customization/2" do
    test "inserts a new customization" do
      assert {:ok, %SectionCustomization{section_key: "home", display_name: "Dashboard", icon_name: "home"}} =
               Sections.upsert_customization("home", %{display_name: "Dashboard", icon_name: "home"})
    end

    test "updates existing customization" do
      {:ok, _} = Sections.upsert_customization("news", %{display_name: "News", icon_name: "megaphone"})
      assert {:ok, %SectionCustomization{display_name: "Updates"}} =
               Sections.upsert_customization("news", %{display_name: "Updates", icon_name: "bell"})
    end

    test "allows nil display_name (revert to default)" do
      assert {:ok, %SectionCustomization{display_name: nil}} =
               Sections.upsert_customization("events", %{display_name: nil, icon_name: "calendar"})
    end

    test "allows nil icon_name (revert to default)" do
      assert {:ok, %SectionCustomization{icon_name: nil}} =
               Sections.upsert_customization("events", %{display_name: "Events", icon_name: nil})
    end
  end

  describe "list_customizations/0" do
    test "returns empty map when no customizations" do
      assert %{} = Sections.list_customizations()
    end

    test "returns map keyed by section_key" do
      {:ok, _} = Sections.upsert_customization("home", %{display_name: "Dashboard", icon_name: nil})
      result = Sections.list_customizations()
      assert %{"home" => %SectionCustomization{display_name: "Dashboard"}} = result
    end
  end

  describe "get_customization/1" do
    test "returns nil when no customization" do
      assert nil == Sections.get_customization("home")
    end

    test "returns customization when it exists" do
      {:ok, _} = Sections.upsert_customization("tools", %{display_name: "Apps", icon_name: "wrench"})
      assert %SectionCustomization{display_name: "Apps"} = Sections.get_customization("tools")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test test/atrium/sections_test.exs 2>&1 | head -20
```

Expected: compile error or `module Atrium.Sections is not available`.

- [ ] **Step 3: Create the migration**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix ecto.gen.migration create_section_customizations
```

Then edit the generated file (it will be in `priv/repo/migrations/`). Replace the body with:

```elixir
defmodule Atrium.Repo.Migrations.CreateSectionCustomizations do
  use Ecto.Migration

  def change do
    create table(:section_customizations) do
      add :section_key, :string, null: false
      add :display_name, :string
      add :icon_name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:section_customizations, [:section_key])
  end
end
```

- [ ] **Step 4: Run the migration**

```bash
mix ecto.migrate
```

Expected: `== Running ... CreateSectionCustomizations.change/0 forward` with no errors.

- [ ] **Step 5: Create the Ecto schema**

Create `lib/atrium/sections/section_customization.ex`:

```elixir
defmodule Atrium.Sections.SectionCustomization do
  use Ecto.Schema
  import Ecto.Changeset

  schema "section_customizations" do
    field :section_key, :string
    field :display_name, :string
    field :icon_name, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:section_key, :display_name, :icon_name])
    |> validate_required([:section_key])
    |> unique_constraint(:section_key)
  end
end
```

- [ ] **Step 6: Create the context**

Create `lib/atrium/sections.ex`:

```elixir
defmodule Atrium.Sections do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Sections.SectionCustomization

  @spec list_customizations() :: %{String.t() => SectionCustomization.t()}
  def list_customizations do
    Repo.all(SectionCustomization)
    |> Map.new(&{&1.section_key, &1})
  end

  @spec get_customization(String.t()) :: SectionCustomization.t() | nil
  def get_customization(section_key) do
    Repo.get_by(SectionCustomization, section_key: section_key)
  end

  @spec upsert_customization(String.t(), map()) :: {:ok, SectionCustomization.t()} | {:error, Ecto.Changeset.t()}
  def upsert_customization(section_key, attrs) do
    existing = get_customization(section_key) || %SectionCustomization{}
    existing
    |> SectionCustomization.changeset(Map.put(attrs, :section_key, section_key))
    |> Repo.insert_or_update()
  end
end
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
mix test test/atrium/sections_test.exs
```

Expected: `5 tests, 0 failures`

- [ ] **Step 8: Commit**

```bash
git add priv/repo/migrations/ lib/atrium/sections/ lib/atrium/sections.ex test/atrium/sections_test.exs
git commit -m "feat: add SectionCustomization schema + Sections context"
```

---

### Task 2: SectionRegistry.all_with_overrides/0 + AppShell update

**Files:**
- Modify: `lib/atrium/authorization/section_registry.ex`
- Modify: `lib/atrium/app_shell.ex`
- Create: `test/atrium/authorization/section_registry_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/atrium/authorization/section_registry_test.exs`:

```elixir
defmodule Atrium.Authorization.SectionRegistryTest do
  use Atrium.DataCase, async: true

  alias Atrium.Authorization.SectionRegistry
  alias Atrium.Sections

  describe "all_with_overrides/0" do
    test "returns all 14 sections with defaults when no customizations" do
      result = SectionRegistry.all_with_overrides()
      assert length(result) == 14
      home = Enum.find(result, &(&1.key == :home))
      assert home.name == "Home"
      assert home.icon == "home"
    end

    test "applies display_name override" do
      {:ok, _} = Sections.upsert_customization("home", %{display_name: "Dashboard", icon_name: nil})
      result = SectionRegistry.all_with_overrides()
      home = Enum.find(result, &(&1.key == :home))
      assert home.name == "Dashboard"
      assert home.icon == "home"
    end

    test "applies icon_name override" do
      {:ok, _} = Sections.upsert_customization("news", %{display_name: nil, icon_name: "bell"})
      result = SectionRegistry.all_with_overrides()
      news = Enum.find(result, &(&1.key == :news))
      assert news.name == "News & Announcements"
      assert news.icon == "bell"
    end

    test "nil overrides fall back to defaults" do
      {:ok, _} = Sections.upsert_customization("events", %{display_name: nil, icon_name: nil})
      result = SectionRegistry.all_with_overrides()
      events = Enum.find(result, &(&1.key == :events))
      assert events.name == "Events & Calendar"
      assert events.icon == "calendar"
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/atrium/authorization/section_registry_test.exs 2>&1 | head -20
```

Expected: `UndefinedFunctionError` for `SectionRegistry.all_with_overrides/0`.

- [ ] **Step 3: Add all_with_overrides/0 to SectionRegistry**

Edit `lib/atrium/authorization/section_registry.ex`. Add after the existing `get/1` function at the bottom of the module:

```elixir
  def all_with_overrides do
    overrides = Atrium.Sections.list_customizations()

    Enum.map(@sections, fn section ->
      key_str = to_string(section.key)
      case Map.get(overrides, key_str) do
        nil ->
          section
        custom ->
          section
          |> Map.put(:name, custom.display_name || section.name)
          |> Map.put(:icon, custom.icon_name || section.icon)
      end
    end)
  end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/atrium/authorization/section_registry_test.exs
```

Expected: `4 tests, 0 failures`

- [ ] **Step 5: Update AppShell to use all_with_overrides/0**

Edit `lib/atrium/app_shell.ex`. Change line:

```elixir
    SectionRegistry.all()
```

to:

```elixir
    SectionRegistry.all_with_overrides()
```

- [ ] **Step 6: Run full test suite to confirm no regressions**

```bash
mix test
```

Expected: all tests pass (was 285 before this change).

- [ ] **Step 7: Commit**

```bash
git add lib/atrium/authorization/section_registry.ex lib/atrium/app_shell.ex test/atrium/authorization/section_registry_test.exs
git commit -m "feat: add SectionRegistry.all_with_overrides/0, wire into AppShell"
```

---

### Task 3: Heroicons SVG helper module

**Files:**
- Create: `lib/atrium_web/helpers/heroicons.ex`

> Note: This task has no tests — the module is a static data map. We verify it compiles and returns correct data.

- [ ] **Step 1: Create the Heroicons helper**

Create `lib/atrium_web/helpers/heroicons.ex`:

```elixir
defmodule AtriumWeb.Heroicons do
  @moduledoc """
  Inline SVG rendering for Heroicons outline set.
  Each icon is rendered as a 16x16 SVG with stroke-based outlines.
  Call `icon/2` to get an HTML-safe SVG string.
  """

  @icons %{
    "academic-cap" => ~s(<path d="M2 6.5L8 3l6 3.5-6 3.5L2 6.5z" stroke-linejoin="round"/><path d="M14 6.5V11M4 8.5v3a4 4 0 0 0 8 0V8.5" stroke-linecap="round" stroke-linejoin="round"/>),
    "adjustments-horizontal" => ~s(<path d="M3 5h10M3 8h10M3 11h10" stroke-linecap="round"/><circle cx="6" cy="5" r="1.5" fill="currentColor" stroke="none"/><circle cx="10" cy="8" r="1.5" fill="currentColor" stroke="none"/><circle cx="5" cy="11" r="1.5" fill="currentColor" stroke="none"/>),
    "archive-box" => ~s(<rect x="2" y="4" width="12" height="2" rx=".5" stroke-linejoin="round"/><path d="M3 6v7a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V6" stroke-linejoin="round"/><path d="M6 9h4" stroke-linecap="round"/>),
    "arrow-down" => ~s(<path d="M8 3v10M4 9l4 4 4-4" stroke-linecap="round" stroke-linejoin="round"/>),
    "arrow-left" => ~s(<path d="M13 8H3M7 4l-4 4 4 4" stroke-linecap="round" stroke-linejoin="round"/>),
    "arrow-path" => ~s(<path d="M13 8A5 5 0 1 1 8 3M13 3v5h-5" stroke-linecap="round" stroke-linejoin="round"/>),
    "arrow-right" => ~s(<path d="M3 8h10M9 4l4 4-4 4" stroke-linecap="round" stroke-linejoin="round"/>),
    "arrow-up" => ~s(<path d="M8 13V3M4 7l4-4 4 4" stroke-linecap="round" stroke-linejoin="round"/>),
    "arrow-up-right" => ~s(<path d="M4 12L12 4M6 4h6v6" stroke-linecap="round" stroke-linejoin="round"/>),
    "at-symbol" => ~s(<circle cx="8" cy="8" r="3"/><path d="M11 8c0 2.761 1 4 3 4M3 8a5 5 0 1 0 10 0 5 5 0 0 0-10 0z" stroke-linecap="round"/>),
    "bars-3" => ~s(<path d="M2 4h12M2 8h12M2 12h12" stroke-linecap="round"/>),
    "bell" => ~s(<path d="M4 8a4 4 0 0 1 8 0c0 2.5 1 3.5 1 4H3c0-.5 1-1.5 1-4z" stroke-linejoin="round"/><path d="M6.5 12a1.5 1.5 0 0 0 3 0" stroke-linecap="round"/>),
    "bolt" => ~s(<path d="M9.5 2L4 9h4l-1.5 5L14 7h-4.5L9.5 2z" stroke-linejoin="round"/>),
    "book-open" => ~s(<path d="M8 4v9M3 4.5A1.5 1.5 0 0 1 4.5 3H8v10H4.5A1.5 1.5 0 0 1 3 11.5v-7z" stroke-linejoin="round"/><path d="M8 4.5V13H11.5A1.5 1.5 0 0 0 13 11.5v-7A1.5 1.5 0 0 0 11.5 3H8" stroke-linejoin="round"/>),
    "book" => ~s(<path d="M4 2h7a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z" stroke-linejoin="round"/><path d="M12 11H4M7 2v9" stroke-linecap="round"/>),
    "bookmark" => ~s(<path d="M5 2h6a1 1 0 0 1 1 1v11l-4-2.5L4 14V3a1 1 0 0 1 1-1z" stroke-linejoin="round"/>),
    "briefcase" => ~s(<rect x="2" y="6" width="12" height="8" rx="1" stroke-linejoin="round"/><path d="M6 6V4a2 2 0 0 1 4 0v2M2 10h12" stroke-linecap="round"/>),
    "building-library" => ~s(<path d="M2 13h12M3 6h10M8 2l5 4H3l5-4z" stroke-linejoin="round"/><rect x="4" y="6" width="2" height="7" stroke-linejoin="round"/><rect x="7" y="6" width="2" height="7" stroke-linejoin="round"/><rect x="10" y="6" width="2" height="7" stroke-linejoin="round"/>),
    "building-office" => ~s(<rect x="2" y="3" width="12" height="11" rx="1" stroke-linejoin="round"/><path d="M6 14V9h4v5M5 6h1M10 6h1M5 9h1M10 9h1" stroke-linecap="round"/>),
    "building" => ~s(<rect x="2" y="3" width="12" height="11" rx="1" stroke-linejoin="round"/><path d="M6 14V9h4v5M5 6h1M10 6h1" stroke-linecap="round"/>),
    "calendar-days" => ~s(<rect x="2" y="3" width="12" height="12" rx="1" stroke-linejoin="round"/><path d="M5 2v2M11 2v2M2 7h12" stroke-linecap="round"/><path d="M5 10h1M8 10h1M11 10h1M5 13h1M8 13h1" stroke-linecap="round"/>),
    "calendar" => ~s(<rect x="2" y="3" width="12" height="12" rx="1" stroke-linejoin="round"/><path d="M5 2v2M11 2v2M2 7h12" stroke-linecap="round"/>),
    "camera" => ~s(<path d="M6 3l-1.5 2H3a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1h-1.5L10 3H6z" stroke-linejoin="round"/><circle cx="8" cy="9" r="2.5"/>),
    "chart-bar" => ~s(<path d="M3 14V8h2v6H3zM7 14V5h2v9H7zM11 14V2h2v12h-2z" stroke-linejoin="round"/>),
    "chart-pie" => ~s(<path d="M8 3A5 5 0 1 0 13 8H8V3z" stroke-linejoin="round"/><path d="M9 2.5A5 5 0 0 1 13.5 7H9V2.5z" stroke-linejoin="round"/>),
    "chat-bubble-left" => ~s(<path d="M3 4a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H6l-3 2V4z" stroke-linejoin="round"/>),
    "chat" => ~s(<path d="M3 4a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H6l-3 2V4z" stroke-linejoin="round"/>),
    "check-circle" => ~s(<circle cx="8" cy="8" r="6"/><path d="M5 8l2.5 2.5L11 5" stroke-linecap="round" stroke-linejoin="round"/>),
    "check" => ~s(<path d="M2.5 8l4 4L13.5 4" stroke-linecap="round" stroke-linejoin="round"/>),
    "chevron-down" => ~s(<path d="M4 6l4 4 4-4" stroke-linecap="round" stroke-linejoin="round"/>),
    "chevron-left" => ~s(<path d="M10 4L6 8l4 4" stroke-linecap="round" stroke-linejoin="round"/>),
    "chevron-right" => ~s(<path d="M6 4l4 4-4 4" stroke-linecap="round" stroke-linejoin="round"/>),
    "chevron-up" => ~s(<path d="M4 10l4-4 4 4" stroke-linecap="round" stroke-linejoin="round"/>),
    "circle-stack" => ~s(<ellipse cx="8" cy="5" rx="5" ry="2" stroke-linejoin="round"/><path d="M3 5v3c0 1.1 2.239 2 5 2s5-.9 5-2V5M3 8v3c0 1.1 2.239 2 5 2s5-.9 5-2V8" stroke-linejoin="round"/>),
    "clipboard-document" => ~s(<rect x="6" y="2" width="4" height="3" rx=".5" stroke-linejoin="round"/><path d="M5 3H4a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V4a1 1 0 0 0-1-1h-1" stroke-linejoin="round"/><path d="M6 8h4M6 11h2" stroke-linecap="round"/>),
    "clipboard" => ~s(<rect x="6" y="2" width="4" height="3" rx=".5" stroke-linejoin="round"/><path d="M5 3H4a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V4a1 1 0 0 0-1-1h-1" stroke-linejoin="round"/>),
    "clock" => ~s(<circle cx="8" cy="8" r="6"/><path d="M8 5v3.5l2 2" stroke-linecap="round" stroke-linejoin="round"/>),
    "cloud" => ~s(<path d="M4.5 12a3 3 0 1 1 .3-5.99A4 4 0 1 1 12 9h.5a2 2 0 1 1 0 3H4.5z" stroke-linejoin="round"/>),
    "code-bracket" => ~s(<path d="M5.5 4L2 8l3.5 4M10.5 4L14 8l-3.5 4M9 3l-2 10" stroke-linecap="round" stroke-linejoin="round"/>),
    "cog-6-tooth" => ~s(<circle cx="8" cy="8" r="2.5"/><path d="M8 2v1.5M8 12.5V14M2 8h1.5M12.5 8H14M3.4 3.4l1.1 1.1M11.5 11.5l1.1 1.1M3.4 12.6l1.1-1.1M11.5 4.5l1.1-1.1" stroke-linecap="round"/>),
    "cog" => ~s(<circle cx="8" cy="8" r="2.5"/><path d="M8 2v1.5M8 12.5V14M2 8h1.5M12.5 8H14M3.4 3.4l1.1 1.1M11.5 11.5l1.1 1.1M3.4 12.6l1.1-1.1M11.5 4.5l1.1-1.1" stroke-linecap="round"/>),
    "command-line" => ~s(<rect x="2" y="3" width="12" height="10" rx="1" stroke-linejoin="round"/><path d="M5 8l2 2-2 2M9 12h2" stroke-linecap="round" stroke-linejoin="round"/>),
    "computer-desktop" => ~s(<rect x="2" y="3" width="12" height="9" rx="1" stroke-linejoin="round"/><path d="M6 14h4M8 12v2" stroke-linecap="round"/>),
    "cpu-chip" => ~s(<rect x="5" y="5" width="6" height="6" rx=".5" stroke-linejoin="round"/><path d="M7 3v2M9 3v2M7 11v2M9 11v2M3 7h2M3 9h2M11 7h2M11 9h2" stroke-linecap="round"/>),
    "credit-card" => ~s(<rect x="2" y="4" width="12" height="9" rx="1" stroke-linejoin="round"/><path d="M2 7h12M5 10h2" stroke-linecap="round"/>),
    "cube" => ~s(<path d="M8 2l5 3v6l-5 3-5-3V5l5-3z" stroke-linejoin="round"/><path d="M8 2v10M3 5l5 3 5-3" stroke-linecap="round"/>),
    "currency-dollar" => ~s(<circle cx="8" cy="8" r="6"/><path d="M8 5v6M6 6.5C6 5.7 6.9 5 8 5s2 .7 2 1.5-1 1.3-2 1.5-2 .8-2 1.5.9 1.5 2 1.5 2-.7 2-1.5" stroke-linecap="round"/>),
    "document-text" => ~s(<path d="M10 2H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1V5l-2-3z" stroke-linejoin="round"/><path d="M10 2v3h2M6 8h4M6 11h3" stroke-linecap="round"/>),
    "document" => ~s(<path d="M10 2H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1V5l-2-3z" stroke-linejoin="round"/><path d="M10 2v3h2" stroke-linecap="round"/>),
    "ellipsis-horizontal" => ~s(<circle cx="4" cy="8" r="1" fill="currentColor" stroke="none"/><circle cx="8" cy="8" r="1" fill="currentColor" stroke="none"/><circle cx="12" cy="8" r="1" fill="currentColor" stroke="none"/>),
    "envelope" => ~s(<rect x="2" y="4" width="12" height="9" rx="1" stroke-linejoin="round"/><path d="M2 5l6 5 6-5" stroke-linecap="round" stroke-linejoin="round"/>),
    "exclamation-circle" => ~s(<circle cx="8" cy="8" r="6"/><path d="M8 5v4M8 11v.5" stroke-linecap="round"/>),
    "exclamation-triangle" => ~s(<path d="M8 3L1.5 13.5h13L8 3z" stroke-linejoin="round"/><path d="M8 7v3M8 11.5v.5" stroke-linecap="round"/>),
    "eye-slash" => ~s(<path d="M2 2l12 12M6.5 6.5A3 3 0 0 0 11 11M4 4C2.5 5.1 1.5 6.5 1.5 8c.5 2 3.5 5 6.5 5 1.3 0 2.5-.4 3.5-1M6 3.3C6.6 3.1 7.3 3 8 3c3 0 6 3 6.5 5-.3 1-1 2.2-2 3" stroke-linecap="round" stroke-linejoin="round"/>),
    "eye" => ~s(<path d="M1.5 8C2 6 4.8 3 8 3s6 3 6.5 5c-.5 2-3.3 5-6.5 5s-6-3-6.5-5z" stroke-linejoin="round"/><circle cx="8" cy="8" r="2"/>),
    "face-smile" => ~s(<circle cx="8" cy="8" r="6"/><path d="M5.5 9.5s.8 2 2.5 2 2.5-2 2.5-2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="6" cy="7" r=".5" fill="currentColor" stroke="none"/><circle cx="10" cy="7" r=".5" fill="currentColor" stroke="none"/>),
    "film" => ~s(<rect x="2" y="3" width="12" height="10" rx="1" stroke-linejoin="round"/><path d="M2 6h2M12 6h2M2 10h2M12 10h2M6 3v10M10 3v10" stroke-linecap="round"/>),
    "finger-print" => ~s(<path d="M8 3a5 5 0 0 1 5 5M3 8a5 5 0 0 0 5 5M5.5 8a2.5 2.5 0 0 1 5 0c0 1-.5 2.5-.5 4M8 8c0 1.5.5 3.5.5 5" stroke-linecap="round" stroke-linejoin="round"/>),
    "fire" => ~s(<path d="M8 2c0 3-3 4-3 7a3 3 0 0 0 6 0C11 6.5 8.5 5.5 8 2z" stroke-linejoin="round"/><path d="M8 10c0 1.1-.9 2-2 2" stroke-linecap="round"/>),
    "flag" => ~s(<path d="M3 14V3l9 2.5L3 8" stroke-linejoin="round" stroke-linecap="round"/>),
    "folder-open" => ~s(<path d="M2 7a1 1 0 0 1 1-1h2.5l1.5-2H13a1 1 0 0 1 1 1v1H2z" stroke-linejoin="round"/><path d="M2 7v6a1 1 0 0 0 1 1h10l2-7H2z" stroke-linejoin="round"/>),
    "folder" => ~s(<path d="M2 5a1 1 0 0 1 1-1h3l1.5 2H13a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5z" stroke-linejoin="round"/>),
    "gift" => ~s(<rect x="2" y="7" width="12" height="2" rx=".5" stroke-linejoin="round"/><rect x="3" y="9" width="10" height="5" rx=".5" stroke-linejoin="round"/><path d="M8 7V14M5.5 7C4 7 3 6 3 5s1-2 2-1.5S8 7 8 7M10.5 7C12 7 13 6 13 5s-1-2-2-1.5S8 7 8 7" stroke-linecap="round" stroke-linejoin="round"/>),
    "globe-alt" => ~s(<circle cx="8" cy="8" r="6"/><path d="M2 8h12M8 2c-2 2-2 8 0 12M8 2c2 2 2 8 0 12" stroke-linecap="round"/>),
    "globe" => ~s(<circle cx="8" cy="8" r="6"/><path d="M2 8h12M8 2c-2 2-2 8 0 12M8 2c2 2 2 8 0 12" stroke-linecap="round"/>),
    "graduation-cap" => ~s(<path d="M2 6.5L8 3l6 3.5-6 3.5L2 6.5z" stroke-linejoin="round"/><path d="M14 6.5V11M4 8.5v3a4 4 0 0 0 8 0V8.5" stroke-linecap="round" stroke-linejoin="round"/>),
    "hand-raised" => ~s(<path d="M8 3V8M6 4V8M4 5v3a4 4 0 0 0 4 4 4 4 0 0 0 4-4V5M10 4v4M12 5v3" stroke-linecap="round" stroke-linejoin="round"/>),
    "hashtag" => ~s(<path d="M5 3l-1 10M12 3l-1 10M2.5 6.5h11M2 10.5h11" stroke-linecap="round"/>),
    "heart" => ~s(<path d="M8 13C8 13 2 9.5 2 5.5A3.5 3.5 0 0 1 8 3.6 3.5 3.5 0 0 1 14 5.5C14 9.5 8 13 8 13z" stroke-linejoin="round"/>),
    "home" => ~s(<path d="M8 1L2 5v8h4v-4h4v4h4V5L8 1z" stroke-linejoin="round"/>),
    "identification" => ~s(<rect x="2" y="3" width="12" height="10" rx="1" stroke-linejoin="round"/><circle cx="6" cy="8" r="2"/><path d="M10 7h2M10 10h2" stroke-linecap="round"/>),
    "inbox" => ~s(<path d="M2 9h3l1.5 2h3L11 9h3M2 4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4z" stroke-linejoin="round"/>),
    "information-circle" => ~s(<circle cx="8" cy="8" r="6"/><path d="M8 7v5M8 5v.5" stroke-linecap="round"/>),
    "kanban" => ~s(<rect x="2" y="3" width="3" height="10" rx=".5" stroke-linejoin="round"/><rect x="6.5" y="3" width="3" height="7" rx=".5" stroke-linejoin="round"/><rect x="11" y="3" width="3" height="5" rx=".5" stroke-linejoin="round"/>),
    "key" => ~s(<circle cx="6" cy="8" r="4"/><path d="M10 8h4M12 6v4" stroke-linecap="round"/>),
    "language" => ~s(<path d="M2 4h7M5.5 4v2M8 4c-.5 3-2 5.5-4 7M3 9c.9 1.2 2.5 2.5 5 3M9 4l2.5 7 2.5-7M9.8 11h4.4" stroke-linecap="round" stroke-linejoin="round"/>),
    "life-buoy" => ~s(<circle cx="8" cy="8" r="6"/><circle cx="8" cy="8" r="2.5"/><path d="M5.7 5.7L3.3 3.3M10.3 10.3l2.4 2.4M10.3 5.7l2.4-2.4M5.7 10.3l-2.4 2.4" stroke-linecap="round"/>),
    "light-bulb" => ~s(<path d="M6 14h4M7 12h2M8 2a4 4 0 0 1 4 4c0 1.5-1 2.5-1.5 3.5S10 11 10 12H6c0-1-.3-2-1-3S4 7.5 4 6a4 4 0 0 1 4-4z" stroke-linejoin="round"/>),
    "link" => ~s(<path d="M6.5 9.5A3.5 3.5 0 0 0 11.5 9l1.5-1.5a3.5 3.5 0 0 0-5-5L6.5 4M9.5 6.5A3.5 3.5 0 0 0 4.5 7L3 8.5a3.5 3.5 0 0 0 5 5l1.5-1.5" stroke-linecap="round"/>),
    "list-bullet" => ~s(<circle cx="3.5" cy="5" r=".75" fill="currentColor" stroke="none"/><circle cx="3.5" cy="8" r=".75" fill="currentColor" stroke="none"/><circle cx="3.5" cy="11" r=".75" fill="currentColor" stroke="none"/><path d="M6 5h7M6 8h7M6 11h7" stroke-linecap="round"/>),
    "lock-closed" => ~s(<rect x="4" y="8" width="8" height="6" rx="1" stroke-linejoin="round"/><path d="M6 8V6a2 2 0 1 1 4 0v2" stroke-linecap="round"/>),
    "lock-open" => ~s(<rect x="4" y="8" width="8" height="6" rx="1" stroke-linejoin="round"/><path d="M6 8V6a2 2 0 1 1 4 0" stroke-linecap="round"/>),
    "magnifying-glass" => ~s(<circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5L14 14" stroke-linecap="round"/>),
    "map-pin" => ~s(<path d="M8 2a4 4 0 0 1 4 4c0 3-4 8-4 8S4 9 4 6a4 4 0 0 1 4-4z" stroke-linejoin="round"/><circle cx="8" cy="6" r="1.5"/>),
    "megaphone" => ~s(<path d="M12 3v10M12 5H4a2 2 0 0 0 0 4h8M5 9l1 4" stroke-linecap="round" stroke-linejoin="round"/>),
    "message-circle" => ~s(<path d="M3 5a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H7l-3 2V5z" stroke-linejoin="round"/>),
    "minus-circle" => ~s(<circle cx="8" cy="8" r="6"/><path d="M5 8h6" stroke-linecap="round"/>),
    "minus" => ~s(<path d="M3 8h10" stroke-linecap="round"/>),
    "moon" => ~s(<path d="M12 9A6 6 0 0 1 7 3a6 6 0 1 0 5 6z" stroke-linejoin="round"/>),
    "musical-note" => ~s(<path d="M6 13V4l7-2v9" stroke-linecap="round" stroke-linejoin="round"/><circle cx="4.5" cy="13" r="1.5"/><circle cx="11.5" cy="11" r="1.5"/>),
    "paper-airplane" => ~s(<path d="M2 2l12 6-12 6v-4.5l7-1.5-7-1.5V2z" stroke-linejoin="round"/>),
    "pencil-square" => ~s(<path d="M10.5 2.5a1.5 1.5 0 0 1 2.5 1.5L5 12.5 2 13.5l1-3L10.5 2.5z" stroke-linejoin="round" stroke-linecap="round"/><path d="M4 13h9" stroke-linecap="round"/>),
    "pencil" => ~s(<path d="M11 2.5a1.5 1.5 0 0 1 2.5 1.5L5 12.5 2 13.5l1-3L11 2.5z" stroke-linejoin="round" stroke-linecap="round"/>),
    "phone" => ~s(<path d="M3 3h3l1.5 3-2 1.5a8 8 0 0 0 3 3L10 9l3 1.5V13a1 1 0 0 1-1 1A11 11 0 0 1 2 4a1 1 0 0 1 1-1z" stroke-linejoin="round"/>),
    "photo" => ~s(<rect x="2" y="3" width="12" height="10" rx="1" stroke-linejoin="round"/><circle cx="6" cy="7" r="1.5"/><path d="M2 11l3.5-3.5 2 2L11 6l3 3.5" stroke-linecap="round" stroke-linejoin="round"/>),
    "play" => ~s(<path d="M4 3l10 5-10 5V3z" stroke-linejoin="round"/>),
    "plus-circle" => ~s(<circle cx="8" cy="8" r="6"/><path d="M8 5v6M5 8h6" stroke-linecap="round"/>),
    "plus" => ~s(<path d="M8 3v10M3 8h10" stroke-linecap="round"/>),
    "presentation-chart-bar" => ~s(<rect x="2" y="2" width="12" height="9" rx="1" stroke-linejoin="round"/><path d="M5 14l3-3 3 3M8 11v-1M5 8V6M8 8V5M11 8V7" stroke-linecap="round" stroke-linejoin="round"/>),
    "printer" => ~s(<path d="M4 6V3h8v3M4 12H3a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-1" stroke-linejoin="round"/><rect x="4" y="10" width="8" height="4" rx=".5" stroke-linejoin="round"/>),
    "puzzle-piece" => ~s(<path d="M7 3H5a1 1 0 0 0-1 1v2c-.6 0-1 .4-1 1s.4 1 1 1v2a1 1 0 0 0 1 1h2c0 .6.4 1 1 1s1-.4 1-1h2a1 1 0 0 0 1-1V9c.6 0 1-.4 1-1s-.4-1-1-1V5a1 1 0 0 0-1-1H9c0-.6-.4-1-1-1S7 2.4 7 3z" stroke-linejoin="round"/>),
    "question-mark-circle" => ~s(<circle cx="8" cy="8" r="6"/><path d="M6 6.5C6 5.7 6.9 5 8 5s2 .7 2 1.5c0 1-1 1.5-2 2v1" stroke-linecap="round"/><circle cx="8" cy="11.5" r=".5" fill="currentColor" stroke="none"/>),
    "queue-list" => ~s(<rect x="2" y="3" width="12" height="3" rx=".5" stroke-linejoin="round"/><rect x="2" y="8" width="12" height="3" rx=".5" stroke-linejoin="round"/><path d="M2 13h7" stroke-linecap="round"/>),
    "receipt-percent" => ~s(<path d="M4 2h8a1 1 0 0 1 1 1v11l-2-1.5L9.5 14 8 12.5 6.5 14 5 12.5 3 14V3a1 1 0 0 1 1-1z" stroke-linejoin="round"/><path d="M6 5.5l4 5M6.5 5.5a.5.5 0 1 1-1 0 .5.5 0 0 1 1 0zM10.5 10a.5.5 0 1 1-1 0 .5.5 0 0 1 1 0z" stroke-linecap="round"/>),
    "rss" => ~s(<path d="M3 3a10 10 0 0 1 10 10M3 7a6 6 0 0 1 6 6" stroke-linecap="round"/><circle cx="3.5" cy="13.5" r="1" fill="currentColor" stroke="none"/>),
    "scale" => ~s(<path d="M8 2v12M3 14h10M4 8H2l2-5 2 5H4z" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 8h-2l2-5 2 5h-2z" stroke-linecap="round" stroke-linejoin="round"/>),
    "server" => ~s(<rect x="2" y="3" width="12" height="4" rx="1" stroke-linejoin="round"/><rect x="2" y="9" width="12" height="4" rx="1" stroke-linejoin="round"/><circle cx="12" cy="5" r=".75" fill="currentColor" stroke="none"/><circle cx="12" cy="11" r=".75" fill="currentColor" stroke="none"/>),
    "share" => ~s(<circle cx="13" cy="4" r="1.5"/><circle cx="13" cy="12" r="1.5"/><circle cx="3" cy="8" r="1.5"/><path d="M4.5 8.5L11.5 5M4.5 7.5l7 4" stroke-linecap="round"/>),
    "shield-check" => ~s(<path d="M8 2l5 2v4c0 3-2 5-5 6-3-1-5-3-5-6V4l5-2z" stroke-linejoin="round"/><path d="M5.5 8l2 2 3-3" stroke-linecap="round" stroke-linejoin="round"/>),
    "shield" => ~s(<path d="M8 2l5 2v4c0 3-2 5-5 6-3-1-5-3-5-6V4l5-2z" stroke-linejoin="round"/>),
    "signal" => ~s(<path d="M2.5 11.5a7.5 7.5 0 0 1 11 0M5 9a5 5 0 0 1 6 0M7.5 6.5a2.5 2.5 0 0 1 1 0" stroke-linecap="round"/><circle cx="8" cy="12" r="1" fill="currentColor" stroke="none"/>),
    "sparkles" => ~s(<path d="M8 2l1 3 3 1-3 1-1 3-1-3-3-1 3-1 1-3zM13 9l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7.7-2zM3.5 10l.5 1.5 1.5.5-1.5.5-.5 1.5-.5-1.5L1.5 12l1.5-.5.5-1.5z"/>),
    "speaker-wave" => ~s(<path d="M3 6v4h2.5l4 3V3L5.5 6H3z" stroke-linejoin="round"/><path d="M11 5.5a4 4 0 0 1 0 5M12.5 4a6 6 0 0 1 0 8" stroke-linecap="round"/>),
    "squares-2x2" => ~s(<rect x="2" y="2" width="5" height="5" rx=".75" stroke-linejoin="round"/><rect x="9" y="2" width="5" height="5" rx=".75" stroke-linejoin="round"/><rect x="2" y="9" width="5" height="5" rx=".75" stroke-linejoin="round"/><rect x="9" y="9" width="5" height="5" rx=".75" stroke-linejoin="round"/>),
    "star" => ~s(<path d="M8 2l1.8 3.6L14 6.4l-3 2.9.7 4.1L8 11.5l-3.7 1.9.7-4.1-3-2.9 4.2-.8L8 2z" stroke-linejoin="round"/>),
    "sun" => ~s(<circle cx="8" cy="8" r="3"/><path d="M8 2v1M8 13v1M2 8h1M13 8h1M3.9 3.9l.7.7M11.4 11.4l.7.7M3.9 12.1l.7-.7M11.4 4.6l.7-.7" stroke-linecap="round"/>),
    "swatch" => ~s(<path d="M2 12V4a1 1 0 0 1 1-1h7a1 1 0 0 1 1 1v8" stroke-linejoin="round"/><path d="M5 14H3.5a1.5 1.5 0 0 1 0-3L11 9l2.5 2.5a1.5 1.5 0 0 1-1.1 2.5H5z" stroke-linejoin="round"/>),
    "table-cells" => ~s(<rect x="2" y="3" width="12" height="10" rx="1" stroke-linejoin="round"/><path d="M2 7h12M2 11h12M6 3v8M10 3v8" stroke-linecap="round"/>),
    "tag" => ~s(<path d="M2 2h5l7 7a2 2 0 0 1 0 2.8l-2.2 2.2a2 2 0 0 1-2.8 0L2 7V2z" stroke-linejoin="round"/><circle cx="6" cy="6" r="1" fill="currentColor" stroke="none"/>),
    "ticket" => ~s(<path d="M2 6a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1a1.5 1.5 0 0 0 0 2v1a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V9a1.5 1.5 0 0 0 0-2V6z" stroke-linejoin="round"/>),
    "trash" => ~s(<path d="M3 5h10M6 5V3h4v2M5 5v8a1 1 0 0 0 1 1h4a1 1 0 0 0 1-1V5" stroke-linecap="round" stroke-linejoin="round"/>),
    "trophy" => ~s(<path d="M5 2h6v5a3 3 0 0 1-6 0V2z" stroke-linejoin="round"/><path d="M5 5H3a1 1 0 0 0-1 1v1a3 3 0 0 0 3 3M11 5h2a1 1 0 0 1 1 1v1a3 3 0 0 1-3 3M8 10v3M6 14h4" stroke-linecap="round" stroke-linejoin="round"/>),
    "truck" => ~s(<rect x="1" y="5" width="10" height="8" rx="1" stroke-linejoin="round"/><path d="M11 8l3 2v3h-3V8z" stroke-linejoin="round"/><circle cx="4.5" cy="13" r="1.5"/><circle cx="11.5" cy="13" r="1.5"/>),
    "user-circle" => ~s(<circle cx="8" cy="8" r="6"/><circle cx="8" cy="7" r="2.5"/><path d="M3 13c.5-2 2.5-3.5 5-3.5s4.5 1.5 5 3.5" stroke-linecap="round"/>),
    "user-group" => ~s(<circle cx="6" cy="6" r="2.5"/><circle cx="10" cy="6" r="2.5"/><path d="M1 14c.5-2 2.5-3 5-3M15 14c-.5-2-2.5-3-5-3M5 14c.5-1.5 1.5-2 3-2s2.5.5 3 2" stroke-linecap="round"/>),
    "user-plus" => ~s(<circle cx="7" cy="7" r="3"/><path d="M1 14c.5-2 2.8-3.5 6-3.5 3.2 0 5.5 1.5 6 3.5M12 4v6M9 7h6" stroke-linecap="round"/>),
    "user" => ~s(<circle cx="8" cy="6" r="3"/><path d="M2 14c.5-2.5 2.8-4 6-4s5.5 1.5 6 4" stroke-linecap="round"/>),
    "users" => ~s(<circle cx="6" cy="6" r="2.5"/><path d="M1 14c.5-2 2.5-3.5 5-3.5s4.5 1.5 5 3.5M11 4a2.5 2.5 0 1 1 0 5M15 14c-.5-2-2.5-3.5-4-3.5" stroke-linecap="round"/>),
    "variable" => ~s(<path d="M4.5 4C4.5 4 3 4 2 7l4 1-4 1c1 3 2.5 3 2.5 3M11.5 4c0 0 1.5 0 2.5 3l-4 1 4 1c-1 3-2.5 3-2.5 3" stroke-linecap="round" stroke-linejoin="round"/>),
    "video-camera" => ~s(<path d="M2 5a1 1 0 0 1 1-1h7a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5z" stroke-linejoin="round"/><path d="M11 7l3-2v6l-3-2" stroke-linejoin="round"/>),
    "viewfinder-circle" => ~s(<circle cx="8" cy="8" r="6"/><circle cx="8" cy="8" r="2.5"/><path d="M8 2v1.5M8 12.5V14M2 8h1.5M12.5 8H14" stroke-linecap="round"/>),
    "wallet" => ~s(<path d="M2 5a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5z" stroke-linejoin="round"/><path d="M11 8.5a.5.5 0 1 1-1 0 .5.5 0 0 1 1 0z" fill="currentColor" stroke="none"/><path d="M11 5V4a1 1 0 0 0-1-1H4" stroke-linecap="round"/>),
    "wifi" => ~s(<path d="M1.5 7a9 9 0 0 1 13 0M4 10a5 5 0 0 1 8 0M6.5 13a2.5 2.5 0 0 1 3 0" stroke-linecap="round"/><circle cx="8" cy="14" r=".75" fill="currentColor" stroke="none"/>),
    "window" => ~s(<rect x="2" y="3" width="12" height="10" rx="1" stroke-linejoin="round"/><path d="M2 7h12M5 5h.5M7 5h.5" stroke-linecap="round"/>),
    "wrench" => ~s(<path d="M12 3a3 3 0 0 0-4 4L3 12a1 1 0 0 0 1.4 1.4l5-5A3 3 0 0 0 12 3z" stroke-linejoin="round"/>),
    "x-circle" => ~s(<circle cx="8" cy="8" r="6"/><path d="M5.5 5.5l5 5M10.5 5.5l-5 5" stroke-linecap="round"/>),
    "x-mark" => ~s(<path d="M4 4l8 8M12 4l-8 8" stroke-linecap="round"/>),
  }

  @icon_names Map.keys(@icons) |> Enum.sort()

  def names, do: @icon_names

  def valid_name?(name), do: Map.has_key?(@icons, name)

  def icon(name, opts \\ []) do
    size = Keyword.get(opts, :size, 16)
    class = Keyword.get(opts, :class, "")
    paths = Map.get(@icons, name, ~s(<rect x="3" y="3" width="10" height="10" rx="1"/>))

    svg = ~s(<svg viewBox="0 0 16 16" width="#{size}" height="#{size}" fill="none" stroke="currentColor" stroke-width="1.75" class="#{class}">#{paths}</svg>)
    Phoenix.HTML.raw(svg)
  end
end
```

- [ ] **Step 2: Verify it compiles**

```bash
mix compile 2>&1 | grep -i error | head -10
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/atrium_web/helpers/heroicons.ex
git commit -m "feat: add AtriumWeb.Heroicons SVG helper with full icon set"
```

---

### Task 4: SuperAdmin.SectionController + routes

**Files:**
- Create: `lib/atrium_web/controllers/super_admin/section_controller.ex`
- Create: `lib/atrium_web/controllers/super_admin/section_html.ex`
- Modify: `lib/atrium_web/router.ex`
- Create: `test/atrium_web/controllers/super_admin/section_controller_test.exs`

- [ ] **Step 1: Write failing controller tests**

Create `test/atrium_web/controllers/super_admin/section_controller_test.exs`:

```elixir
defmodule AtriumWeb.SuperAdmin.SectionControllerTest do
  use AtriumWeb.ConnCase, async: false

  alias Atrium.SuperAdmins
  alias Atrium.Sections

  setup %{conn: conn} do
    {:ok, sa} =
      SuperAdmins.create_super_admin(%{
        email: "sa_section@atrium.example",
        name: "Ops",
        password: "correct-horse-battery-staple"
      })

    conn =
      conn
      |> Map.put(:host, "admin.atrium.example")
      |> init_test_session(%{super_admin_id: sa.id})

    {:ok, conn: conn}
  end

  describe "GET /super/sections" do
    test "lists all 14 sections", %{conn: conn} do
      conn = get(conn, "/super/sections")
      html = html_response(conn, 200)
      assert html =~ "Sections"
      assert html =~ "Home"
      assert html =~ "Events &amp; Calendar"
      assert html =~ "Compliance &amp; Policies"
    end

    test "shows customized display name when override exists", %{conn: conn} do
      {:ok, _} = Sections.upsert_customization("home", %{display_name: "Dashboard", icon_name: nil})
      conn = get(conn, "/super/sections")
      assert html_response(conn, 200) =~ "Dashboard"
    end
  end

  describe "GET /super/sections/:key/edit" do
    test "renders edit form for valid section", %{conn: conn} do
      conn = get(conn, "/super/sections/home/edit")
      html = html_response(conn, 200)
      assert html =~ "Edit Section"
      assert html =~ "home"
    end

    test "returns 404 for unknown section key", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/super/sections/nonexistent/edit")
      end
    end
  end

  describe "PUT /super/sections/:key" do
    test "saves customization and redirects to index", %{conn: conn} do
      conn = put(conn, "/super/sections/home", %{"section" => %{"display_name" => "Dashboard", "icon_name" => "home"}})
      assert redirected_to(conn) == "/super/sections"
      assert %{display_name: "Dashboard"} = Sections.get_customization("home")
    end

    test "normalizes empty display_name to nil", %{conn: conn} do
      conn = put(conn, "/super/sections/home", %{"section" => %{"display_name" => "", "icon_name" => "home"}})
      assert redirected_to(conn) == "/super/sections"
      assert %{display_name: nil} = Sections.get_customization("home")
    end

    test "returns 404 for unknown section key", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        put(conn, "/super/sections/nonexistent", %{"section" => %{"display_name" => "x", "icon_name" => "home"}})
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/atrium_web/controllers/super_admin/section_controller_test.exs 2>&1 | head -20
```

Expected: compile error — `SectionController` doesn't exist yet.

- [ ] **Step 3: Add routes**

Edit `lib/atrium_web/router.ex`. Inside the `scope "/super"` block (around line 44), add after the existing `resources "/tenants/:tenant_id/idps"` line:

```elixir
      get "/sections", SuperAdmin.SectionController, :index
      get "/sections/:key/edit", SuperAdmin.SectionController, :edit
      put "/sections/:key", SuperAdmin.SectionController, :update
```

- [ ] **Step 4: Create the HTML module**

Create `lib/atrium_web/controllers/super_admin/section_html.ex`:

```elixir
defmodule AtriumWeb.SuperAdmin.SectionHTML do
  use AtriumWeb, :html

  embed_templates "section_html/*"
end
```

- [ ] **Step 5: Create the controller**

Create `lib/atrium_web/controllers/super_admin/section_controller.ex`:

```elixir
defmodule AtriumWeb.SuperAdmin.SectionController do
  use AtriumWeb, :controller

  alias Atrium.Authorization.SectionRegistry
  alias Atrium.Sections

  def index(conn, _params) do
    sections = SectionRegistry.all_with_overrides()
    render(conn, :index, sections: sections)
  end

  def edit(conn, %{"key" => key}) do
    section = fetch_section!(key)
    customization = Sections.get_customization(key)
    render(conn, :edit, section: section, customization: customization)
  end

  def update(conn, %{"key" => key, "section" => params}) do
    fetch_section!(key)

    display_name = normalize_empty(params["display_name"])
    icon_name = normalize_empty(params["icon_name"])

    {:ok, _} = Sections.upsert_customization(key, %{display_name: display_name, icon_name: icon_name})

    conn
    |> put_flash(:info, "Section updated.")
    |> redirect(to: ~p"/super/sections")
  end

  defp fetch_section!(key) do
    case SectionRegistry.get(key) do
      nil -> raise Ecto.NoResultsError, queryable: key
      section -> section
    end
  end

  defp normalize_empty(""), do: nil
  defp normalize_empty(val), do: val
end
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
mix test test/atrium_web/controllers/super_admin/section_controller_test.exs
```

Expected: `7 tests, 0 failures`

- [ ] **Step 7: Commit**

```bash
git add lib/atrium_web/controllers/super_admin/section_controller.ex lib/atrium_web/controllers/super_admin/section_html.ex lib/atrium_web/router.ex test/atrium_web/controllers/super_admin/section_controller_test.exs
git commit -m "feat: add SuperAdmin.SectionController + routes"
```

---

### Task 5: Section management templates

**Files:**
- Create: `lib/atrium_web/controllers/super_admin/section_html/index.html.heex`
- Create: `lib/atrium_web/controllers/super_admin/section_html/edit.html.heex`

- [ ] **Step 1: Create the index template**

Create `lib/atrium_web/controllers/super_admin/section_html/index.html.heex`:

```heex
<div class="atrium-anim" style="max-width:720px">
  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Platform</div>
    <h1 class="atrium-page-title">Sections</h1>
    <p style="font-size:.875rem;color:var(--text-secondary);margin-top:4px">
      Customize the display name and icon for each section. Changes apply across all tenants.
    </p>
  </div>

  <div class="atrium-card">
    <table style="width:100%;border-collapse:collapse">
      <thead>
        <tr style="border-bottom:1px solid var(--border)">
          <th style="padding:10px 16px;text-align:left;font-size:.75rem;font-weight:600;color:var(--text-tertiary);text-transform:uppercase;letter-spacing:.05em">Icon</th>
          <th style="padding:10px 16px;text-align:left;font-size:.75rem;font-weight:600;color:var(--text-tertiary);text-transform:uppercase;letter-spacing:.05em">Name</th>
          <th style="padding:10px 16px;text-align:left;font-size:.75rem;font-weight:600;color:var(--text-tertiary);text-transform:uppercase;letter-spacing:.05em">Key</th>
          <th style="padding:10px 16px;text-align:right;font-size:.75rem;font-weight:600;color:var(--text-tertiary);text-transform:uppercase;letter-spacing:.05em"></th>
        </tr>
      </thead>
      <tbody>
        <%= for section <- @sections do %>
          <tr style="border-bottom:1px solid var(--border)">
            <td style="padding:12px 16px">
              <span style="color:var(--text-secondary)">
                <%= AtriumWeb.Heroicons.icon(section.icon) %>
              </span>
            </td>
            <td style="padding:12px 16px;font-size:.875rem;font-weight:500;color:var(--text-primary)">
              <%= section.name %>
            </td>
            <td style="padding:12px 16px">
              <code style="font-size:.8125rem;color:var(--text-tertiary);background:var(--surface-raised);padding:2px 6px;border-radius:4px"><%= section.key %></code>
            </td>
            <td style="padding:12px 16px;text-align:right">
              <a href={~p"/super/sections/#{section.key}/edit"} class="atrium-btn atrium-btn-ghost" style="font-size:.8125rem;padding:4px 10px">Edit</a>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

- [ ] **Step 2: Create the edit template**

Create `lib/atrium_web/controllers/super_admin/section_html/edit.html.heex`:

```heex
<div class="atrium-anim" style="max-width:640px">
  <div style="margin-bottom:20px">
    <a href={~p"/super/sections"} style="font-size:.8125rem;color:var(--text-tertiary);text-decoration:none">
      ← Back to Sections
    </a>
  </div>

  <div style="margin-bottom:24px">
    <div class="atrium-page-eyebrow">Platform / Sections</div>
    <h1 class="atrium-page-title">Edit Section</h1>
    <p style="font-size:.875rem;color:var(--text-secondary);margin-top:4px">
      Customizing: <code style="font-size:.875rem;background:var(--surface-raised);padding:2px 6px;border-radius:4px"><%= @section.key %></code>
    </p>
  </div>

  <form method="post" action={~p"/super/sections/#{@section.key}"}>
    <input type="hidden" name="_method" value="put" />
    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

    <div class="atrium-card" style="margin-bottom:20px">
      <div class="atrium-card-body" style="display:flex;flex-direction:column;gap:20px">

        <div>
          <label class="atrium-label" for="section_display_name">Display Name</label>
          <input
            id="section_display_name"
            type="text"
            name="section[display_name]"
            class="atrium-input"
            value={(@customization && @customization.display_name) || ""}
            placeholder={"Default: #{@section.name}"}
          />
          <p style="font-size:.8125rem;color:var(--text-tertiary);margin-top:4px">Leave blank to use the default name.</p>
        </div>

        <div>
          <label class="atrium-label">Icon</label>
          <p style="font-size:.8125rem;color:var(--text-tertiary);margin-bottom:8px">
            Current: <strong><%= (@customization && @customization.icon_name) || @section.icon %></strong>
            &nbsp;
            <span style="vertical-align:middle;color:var(--text-secondary)">
              <%= AtriumWeb.Heroicons.icon((@customization && @customization.icon_name) || @section.icon) %>
            </span>
          </p>

          <input
            id="icon_search"
            type="text"
            class="atrium-input"
            placeholder="Search icons…"
            oninput="filterIcons(this.value)"
            autocomplete="off"
            style="margin-bottom:12px"
          />

          <input type="hidden" id="section_icon_name" name="section[icon_name]" value={(@customization && @customization.icon_name) || @section.icon} />

          <div id="icon-grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(72px,1fr));gap:6px;max-height:360px;overflow-y:auto;border:1px solid var(--border);border-radius:var(--radius);padding:12px">
            <%= for name <- AtriumWeb.Heroicons.names() do %>
              <button
                type="button"
                class="icon-option"
                data-name={name}
                onclick={"selectIcon('#{name}')"}
                title={name}
                style={"display:flex;flex-direction:column;align-items:center;gap:4px;padding:8px 4px;border-radius:var(--radius);border:1.5px solid #{if ((@customization && @customization.icon_name) || @section.icon) == name, do: "var(--blue-500)", else: "transparent"};background:#{if ((@customization && @customization.icon_name) || @section.icon) == name, do: "var(--blue-50,#eff6ff)", else: "transparent"};cursor:pointer;font-size:.625rem;color:var(--text-tertiary);word-break:break-all;text-align:center;line-height:1.2"}
              >
                <%= AtriumWeb.Heroicons.icon(name, size: 20) %>
                <%= name %>
              </button>
            <% end %>
          </div>
        </div>

      </div>
    </div>

    <div style="display:flex;gap:8px">
      <button type="submit" class="atrium-btn atrium-btn-primary">Save changes</button>
      <a href={~p"/super/sections"} class="atrium-btn atrium-btn-ghost">Cancel</a>
    </div>
  </form>
</div>

<script>
  function selectIcon(name) {
    document.getElementById('section_icon_name').value = name;
    document.querySelectorAll('.icon-option').forEach(function(btn) {
      var selected = btn.dataset.name === name;
      btn.style.border = selected ? '1.5px solid var(--blue-500)' : '1.5px solid transparent';
      btn.style.background = selected ? 'var(--blue-50,#eff6ff)' : 'transparent';
    });
  }

  function filterIcons(query) {
    var q = query.toLowerCase();
    document.querySelectorAll('.icon-option').forEach(function(btn) {
      btn.style.display = btn.dataset.name.includes(q) ? '' : 'none';
    });
  }
</script>
```

- [ ] **Step 3: Verify templates render — visit the app**

Start the server if it's not running:
```bash
mix phx.server
```

Visit `http://admin.atrium.example/super/sections` (requires super admin session). Confirm the table renders with all 14 sections and icons visible.

Visit `http://admin.atrium.example/super/sections/home/edit`. Confirm the icon grid loads with ~100+ icons, search filters work, clicking an icon highlights it.

- [ ] **Step 4: Run full test suite**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/atrium_web/controllers/super_admin/section_html/
git commit -m "feat: add section management templates with icon picker"
```

---

### Task 6: Super admin sidebar navigation entry

**Files:**
- Modify: `lib/atrium_web/components/layouts/super_admin.html.heex`

- [ ] **Step 1: Add Sections nav entry to sidebar**

Edit `lib/atrium_web/components/layouts/super_admin.html.heex`. After the Dashboard link block (the first `<div class="atrium-sidebar-section">` closing tag), add a new sidebar section before the Tenants section:

```heex
    <div class="atrium-sidebar-section">
      <% sections_active = String.starts_with?(@conn.request_path, "/super/sections") %>
      <a href={~p"/super/sections"} class={"atrium-sidebar-item#{if sections_active, do: " active", else: ""}"}>
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.75">
          <rect x="2" y="2" width="5" height="5" rx=".75" stroke-linejoin="round"/>
          <rect x="9" y="2" width="5" height="5" rx=".75" stroke-linejoin="round"/>
          <rect x="2" y="9" width="5" height="5" rx=".75" stroke-linejoin="round"/>
          <rect x="9" y="9" width="5" height="5" rx=".75" stroke-linejoin="round"/>
        </svg>
        Sections
      </a>
    </div>
```

- [ ] **Step 2: Run full test suite**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/atrium_web/components/layouts/super_admin.html.heex
git commit -m "feat: add Sections entry to super admin sidebar"
```

---

## Self-Review

**Spec coverage check:**
- ✅ `section_customizations` DB table — Task 1
- ✅ `Atrium.Sections` context (list, get, upsert) — Task 1
- ✅ `SectionRegistry.all_with_overrides/0` — Task 2
- ✅ `AppShell` updated to use `all_with_overrides/0` — Task 2
- ✅ `AtriumWeb.Heroicons` SVG helper — Task 3
- ✅ `SuperAdmin.SectionController` (index/edit/update) — Task 4
- ✅ Routes at `/super/sections` — Task 4
- ✅ Index template listing 14 sections — Task 5
- ✅ Edit template with searchable icon picker — Task 5
- ✅ Super admin sidebar "Sections" entry — Task 6
- ✅ 404 for unknown section key — Task 4 (controller + tests)
- ✅ Empty display_name normalized to nil — Task 4 (controller + tests)
- ✅ Unit tests for context — Task 1
- ✅ Unit tests for `all_with_overrides/0` — Task 2
- ✅ Controller tests — Task 4

**Placeholder scan:** None found.

**Type consistency:**
- `Sections.upsert_customization/2` takes `(String.t(), map())` — consistent across Tasks 1, 2, 4
- `SectionRegistry.all_with_overrides/0` returns same shape as `SectionRegistry.all/0` — consistent with Task 2 and Task 4 usage
- `AtriumWeb.Heroicons.icon/2` called consistently in Tasks 3 and 5
- `@customization` assigned in controller Task 4, used in template Task 5 — consistent
