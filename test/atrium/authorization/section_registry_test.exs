defmodule Atrium.Authorization.SectionRegistryTest do
  use Atrium.DataCase, async: true

  alias Atrium.Authorization.SectionRegistry
  alias Atrium.Sections

  test "all/0 returns exactly 14 sections" do
    assert length(SectionRegistry.all()) == 14
  end

  test "each section has the required keys" do
    for s <- SectionRegistry.all() do
      assert Map.has_key?(s, :key)
      assert Map.has_key?(s, :name)
      assert Map.has_key?(s, :default_capabilities)
      assert Map.has_key?(s, :supports_subsections)
      assert Map.has_key?(s, :default_acls)
    end
  end

  test "keys are the canonical intranet keys" do
    expected = ~w(home news directory hr departments docs tools projects helpdesk learning events social compliance feedback)a
    actual = SectionRegistry.all() |> Enum.map(& &1.key) |> Enum.sort()
    assert actual == Enum.sort(expected)
  end

  test "get/1 returns a section by key" do
    assert %{key: :hr} = SectionRegistry.get(:hr)
    assert SectionRegistry.get(:nonexistent) == nil
  end

  test "capabilities/0 returns exactly [:view, :edit, :approve]" do
    assert SectionRegistry.capabilities() == [:view, :edit, :approve]
  end

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
