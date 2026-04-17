defmodule Atrium.Accounts.ProvisioningTest do
  use Atrium.TenantCase
  alias Atrium.Accounts
  alias Atrium.Accounts.{Idp, Provisioning}

  defp mk_idp(prefix, mode, attrs \\ %{}) do
    {:ok, idp} =
      Idp.create_idp(prefix, Map.merge(%{
        kind: "oidc",
        name: "IdP",
        discovery_url: "x",
        client_id: "a",
        client_secret: "s",
        provisioning_mode: mode
      }, attrs))
    idp
  end

  describe "strict mode" do
    test "returns :user_not_found when email has no matching user", %{tenant_prefix: prefix} do
      idp = mk_idp(prefix, "strict")
      claims = %{"sub" => "abc", "email" => "unknown@e.co", "name" => "N"}
      assert {:error, :user_not_found} = Provisioning.upsert_from_idp(prefix, idp, claims)
    end

    test "links identity when existing user's email matches", %{tenant_prefix: prefix} do
      {:ok, %{user: user, token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
      {:ok, _} = Accounts.activate_user(prefix, raw, "superSecret1234!")

      idp = mk_idp(prefix, "strict")
      claims = %{"sub" => "abc-strict", "email" => "a@e.co", "name" => "A"}

      assert {:ok, linked_user} = Provisioning.upsert_from_idp(prefix, idp, claims)
      assert linked_user.id == user.id
      # Re-running finds by identity
      assert {:ok, again} = Provisioning.upsert_from_idp(prefix, idp, claims)
      assert again.id == user.id
    end
  end

  describe "auto_create mode" do
    test "creates user and identity on first login", %{tenant_prefix: prefix} do
      idp = mk_idp(prefix, "auto_create")
      claims = %{"sub" => "new-sub", "email" => "new@e.co", "name" => "New"}

      {:ok, user} = Provisioning.upsert_from_idp(prefix, idp, claims)
      assert user.email == "new@e.co"
      assert user.status == "active"
    end
  end

  describe "link_only mode" do
    test "returns :needs_password_confirmation on first SSO", %{tenant_prefix: prefix} do
      {:ok, %{user: _, token: raw}} = Accounts.invite_user(prefix, %{email: "b@e.co", name: "B"})
      {:ok, _} = Accounts.activate_user(prefix, raw, "superSecret1234!")

      idp = mk_idp(prefix, "link_only")
      claims = %{"sub" => "link-sub", "email" => "b@e.co", "name" => "B"}

      assert {:needs_password_confirmation, ticket} = Provisioning.upsert_from_idp(prefix, idp, claims)
      assert {:ok, _} = Provisioning.confirm_link(prefix, ticket, "superSecret1234!")
    end
  end
end
