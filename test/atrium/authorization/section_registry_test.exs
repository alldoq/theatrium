defmodule Atrium.Authorization.SectionRegistryTest do
  use ExUnit.Case, async: true
  alias Atrium.Authorization.SectionRegistry

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
end
