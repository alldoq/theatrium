defmodule Atrium.HomeTest do
  use Atrium.TenantCase

  alias Atrium.Home

  defp actor(prefix) do
    {:ok, %{user: u}} = Atrium.Accounts.invite_user(prefix, %{
      email: "home_actor_#{System.unique_integer([:positive])}@example.com",
      name: "Actor"
    })
    u
  end

  describe "announcements" do
    test "create and list", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, ann} = Home.create_announcement(prefix, %{title: "Hello", body_html: "<p>hi</p>"}, u)
      assert ann.title == "Hello"
      assert ann.pinned == false
      list = Home.list_announcements(prefix)
      assert Enum.any?(list, &(&1.id == ann.id))
    end

    test "update announcement", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, ann} = Home.create_announcement(prefix, %{title: "Old", body_html: ""}, u)
      {:ok, updated} = Home.update_announcement(prefix, ann, %{title: "New"}, u)
      assert updated.title == "New"
    end

    test "delete announcement", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, ann} = Home.create_announcement(prefix, %{title: "Gone", body_html: ""}, u)
      {:ok, _} = Home.delete_announcement(prefix, ann, u)
      refute Enum.any?(Home.list_announcements(prefix), &(&1.id == ann.id))
    end

    test "pinned announcements sort first", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, a1} = Home.create_announcement(prefix, %{title: "Normal", body_html: "", pinned: false}, u)
      {:ok, a2} = Home.create_announcement(prefix, %{title: "Pinned", body_html: "", pinned: true}, u)
      list = Home.list_announcements(prefix)
      ids = Enum.map(list, & &1.id)
      assert Enum.find_index(ids, &(&1 == a2.id)) < Enum.find_index(ids, &(&1 == a1.id))
    end
  end

  describe "quick links" do
    test "create and list", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, link} = Home.create_quick_link(prefix, %{label: "HR Portal", url: "https://hr.example.com", icon: "heart", position: 1}, u)
      assert link.label == "HR Portal"
      list = Home.list_quick_links(prefix)
      assert Enum.any?(list, &(&1.id == link.id))
    end

    test "delete quick link", %{tenant_prefix: prefix} do
      u = actor(prefix)
      {:ok, link} = Home.create_quick_link(prefix, %{label: "Test", url: "https://example.com", icon: "link", position: 1}, u)
      {:ok, _} = Home.delete_quick_link(prefix, link, u)
      refute Enum.any?(Home.list_quick_links(prefix), &(&1.id == link.id))
    end
  end
end
