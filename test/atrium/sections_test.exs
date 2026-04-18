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
