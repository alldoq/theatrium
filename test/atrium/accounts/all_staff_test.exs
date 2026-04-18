defmodule Atrium.Accounts.AllStaffTest do
  use Atrium.TenantCase
  alias Atrium.Accounts
  alias Atrium.Authorization

  setup %{tenant_prefix: prefix} do
    # all_staff is seeded by provisioning; create it only if absent (e.g. in test contexts that skip seeding)
    case Authorization.get_group_by_slug(prefix, "all_staff") do
      nil -> {:ok, _} = Authorization.create_group(prefix, %{slug: "all_staff", name: "All staff", kind: "system"})
      _ -> :ok
    end
    :ok
  end

  test "activating a user adds them to all_staff", %{tenant_prefix: prefix} do
    {:ok, %{user: _u, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    groups = Authorization.list_groups_for_user(prefix, user)
    assert Enum.any?(groups, &(&1.slug == "all_staff"))
  end

  test "suspending a user removes them from all_staff", %{tenant_prefix: prefix} do
    {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    {:ok, _} = Accounts.suspend_user(prefix, user)
    groups = Authorization.list_groups_for_user(prefix, user)
    refute Enum.any?(groups, &(&1.slug == "all_staff"))
  end
end
