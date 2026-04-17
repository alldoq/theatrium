defmodule Atrium.SuperAdminsTest do
  use Atrium.DataCase, async: true
  alias Atrium.SuperAdmins
  alias Atrium.SuperAdmins.SuperAdmin

  describe "create_super_admin/1" do
    test "creates a super admin with a hashed password" do
      {:ok, sa} = SuperAdmins.create_super_admin(%{email: "ops@atrium.example", name: "Ops", password: "correct-horse-battery-staple"})
      assert sa.hashed_password
      refute sa.hashed_password == "correct-horse-battery-staple"
    end

    test "rejects short passwords" do
      {:error, cs} = SuperAdmins.create_super_admin(%{email: "a@b.co", name: "A", password: "short"})
      refute cs.valid?
      assert %{password: [_ | _]} = errors_on(cs)
    end

    test "rejects duplicate email case-insensitively" do
      {:ok, _} = SuperAdmins.create_super_admin(%{email: "Ops@atrium.example", name: "Ops", password: "correct-horse-battery-staple"})
      {:error, cs} = SuperAdmins.create_super_admin(%{email: "ops@atrium.example", name: "Ops2", password: "correct-horse-battery-staple"})
      assert "has already been taken" in errors_on(cs).email
    end
  end

  describe "authenticate/2" do
    setup do
      {:ok, sa} = SuperAdmins.create_super_admin(%{email: "ops@atrium.example", name: "Ops", password: "correct-horse-battery-staple"})
      {:ok, sa: sa}
    end

    test "returns {:ok, sa} on correct password", %{sa: sa} do
      assert {:ok, found} = SuperAdmins.authenticate("ops@atrium.example", "correct-horse-battery-staple")
      assert found.id == sa.id
    end

    test "returns {:error, :invalid_credentials} on wrong password" do
      assert {:error, :invalid_credentials} = SuperAdmins.authenticate("ops@atrium.example", "wrong")
    end

    test "returns {:error, :invalid_credentials} for unknown email" do
      assert {:error, :invalid_credentials} = SuperAdmins.authenticate("nope@atrium.example", "whatever")
    end

    test "returns {:error, :suspended} when status is suspended", %{sa: sa} do
      {:ok, _} = SuperAdmins.update_status(sa, "suspended")
      assert {:error, :suspended} = SuperAdmins.authenticate("ops@atrium.example", "correct-horse-battery-staple")
    end
  end
end
