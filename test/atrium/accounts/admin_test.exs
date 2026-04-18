defmodule Atrium.Accounts.AdminTest do
  use Atrium.TenantCase, async: false
  alias Atrium.Accounts

  defp create_user(prefix) do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{
      email: "admin_test_#{System.unique_integer([:positive])}@example.com",
      name: "Test User"
    })
    user
  end

  describe "set_admin/3" do
    test "sets is_admin to true", %{tenant_prefix: prefix} do
      user = create_user(prefix)
      assert user.is_admin == false
      {:ok, updated} = Accounts.set_admin(prefix, user, true)
      assert updated.is_admin == true
    end

    test "sets is_admin to false", %{tenant_prefix: prefix} do
      user = create_user(prefix)
      {:ok, user} = Accounts.set_admin(prefix, user, true)
      {:ok, updated} = Accounts.set_admin(prefix, user, false)
      assert updated.is_admin == false
    end

    test "logs user.admin_changed audit event", %{tenant_prefix: prefix} do
      user = create_user(prefix)
      {:ok, _} = Accounts.set_admin(prefix, user, true)
      events = Atrium.Audit.history_for(prefix, "User", user.id)
      assert Enum.any?(events, &(&1.action == "user.admin_changed"))
    end
  end
end
