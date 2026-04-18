defmodule Atrium.DirectoryTest do
  use Atrium.TenantCase
  alias Atrium.Accounts

  defp make_user(prefix, attrs \\ %{}) do
    base = %{
      email: "dir_#{System.unique_integer([:positive])}@example.com",
      name: "Dir User"
    }
    {:ok, %{user: u}} = Accounts.invite_user(prefix, Map.merge(base, attrs))
    u
  end

  describe "profile fields" do
    test "update_profile saves role and department", %{tenant_prefix: prefix} do
      u = make_user(prefix)
      {:ok, updated} = Accounts.update_profile(prefix, u, %{role: "Engineer", department: "IT"})
      assert updated.role == "Engineer"
      assert updated.department == "IT"
    end

    test "update_profile saves phone and bio", %{tenant_prefix: prefix} do
      u = make_user(prefix)
      {:ok, updated} = Accounts.update_profile(prefix, u, %{phone: "+44 7700 000000", bio: "A short bio."})
      assert updated.phone == "+44 7700 000000"
      assert updated.bio == "A short bio."
    end

    test "list_active_users returns only active users", %{tenant_prefix: prefix} do
      # Invited users are not active
      _invited = make_user(prefix)

      # Activate a user directly
      {:ok, %{user: u2}} = Accounts.invite_user(prefix, %{
        email: "active_dir_#{System.unique_integer([:positive])}@x.com",
        name: "Active User"
      })
      {:ok, _} = Accounts.activate_user_with_password(prefix, u2, %{password: "supersecretpassword123"})

      list = Accounts.list_active_users(prefix)
      assert is_list(list)
      assert Enum.any?(list, fn u -> u.email == u2.email end)
      # Invited user should not appear
      refute Enum.any?(list, fn u -> u.status == "invited" end)
    end

    test "list_active_users orders by name", %{tenant_prefix: prefix} do
      {:ok, %{user: u1}} = Accounts.invite_user(prefix, %{
        email: "zzz_#{System.unique_integer([:positive])}@x.com",
        name: "Zara Last"
      })
      {:ok, %{user: u2}} = Accounts.invite_user(prefix, %{
        email: "aaa_#{System.unique_integer([:positive])}@x.com",
        name: "Aaron First"
      })
      {:ok, _} = Accounts.activate_user_with_password(prefix, u1, %{password: "supersecretpassword123"})
      {:ok, _} = Accounts.activate_user_with_password(prefix, u2, %{password: "supersecretpassword123"})

      list = Accounts.list_active_users(prefix)
      names = Enum.map(list, & &1.name)
      aaron_idx = Enum.find_index(names, &(&1 == "Aaron First"))
      zara_idx = Enum.find_index(names, &(&1 == "Zara Last"))
      assert aaron_idx < zara_idx
    end
  end
end
