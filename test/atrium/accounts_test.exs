defmodule Atrium.AccountsTest do
  use Atrium.TenantCase
  alias Atrium.Accounts

  describe "invite_user/2" do
    test "creates an invited user and an invitation token", %{tenant_prefix: prefix} do
      {:ok, %{user: user, token: raw_token}} =
        Accounts.invite_user(prefix, %{email: "alice@example.com", name: "Alice"})

      assert user.status == "invited"
      assert is_binary(raw_token)
      assert String.length(raw_token) > 30
    end

    test "rejects duplicate email in the same tenant", %{tenant_prefix: prefix} do
      {:ok, _} = Accounts.invite_user(prefix, %{email: "alice@example.com", name: "Alice"})
      {:error, cs} = Accounts.invite_user(prefix, %{email: "alice@example.com", name: "Alice Two"})
      assert "has already been taken" in errors_on(cs).email
    end
  end

  describe "activate_user/3" do
    test "sets password, activates user, marks token used", %{tenant_prefix: prefix} do
      {:ok, %{user: user, token: raw}} =
        Accounts.invite_user(prefix, %{email: "bob@example.com", name: "Bob"})

      {:ok, activated} = Accounts.activate_user(prefix, raw, "superSecret1234!")
      assert activated.id == user.id
      assert activated.status == "active"

      assert {:error, :invalid_or_expired_token} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    end

    test "rejects invalid token", %{tenant_prefix: prefix} do
      assert {:error, :invalid_or_expired_token} =
               Accounts.activate_user(prefix, "not-a-real-token", "superSecret1234!")
    end
  end

  describe "authenticate_by_password/3" do
    setup %{tenant_prefix: prefix} do
      {:ok, %{user: _user, token: raw}} =
        Accounts.invite_user(prefix, %{email: "carol@example.com", name: "Carol"})

      {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
      {:ok, user: user}
    end

    test "returns {:ok, user} on correct credentials", %{tenant_prefix: prefix, user: user} do
      assert {:ok, found} = Accounts.authenticate_by_password(prefix, "carol@example.com", "superSecret1234!")
      assert found.id == user.id
    end

    test "returns invalid_credentials on wrong password", %{tenant_prefix: prefix} do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password(prefix, "carol@example.com", "nope")
    end

    test "returns invalid_credentials for unknown email", %{tenant_prefix: prefix} do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password(prefix, "nobody@example.com", "x")
    end

    test "refuses to authenticate suspended users", %{tenant_prefix: prefix, user: user} do
      {:ok, _} = Accounts.suspend_user(prefix, user)
      assert {:error, :suspended} =
               Accounts.authenticate_by_password(prefix, "carol@example.com", "superSecret1234!")
    end
  end

  describe "create_session/4 and get_session_by_token/2" do
    setup %{tenant_prefix: prefix} do
      {:ok, %{user: _u, token: raw}} = Accounts.invite_user(prefix, %{email: "dave@e.co", name: "D"})
      {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
      {:ok, user: user}
    end

    test "returns raw token once; hash is stored", %{tenant_prefix: prefix, user: user} do
      {:ok, %{token: raw, session: session}} =
        Accounts.create_session(prefix, user, %{ip: "1.2.3.4", user_agent: "test/1.0"}, ttl_minutes: 60)

      assert is_binary(raw)
      assert session.user_id == user.id

      assert {:ok, %{session: found}} = Accounts.get_session_by_token(prefix, raw)
      assert found.id == session.id
    end

    test "returns :not_found for bad token", %{tenant_prefix: prefix} do
      assert :not_found = Accounts.get_session_by_token(prefix, "nonsense")
    end

    test "returns :expired after expiration", %{tenant_prefix: prefix, user: user} do
      {:ok, %{token: raw}} = Accounts.create_session(prefix, user, %{}, ttl_minutes: -1)
      assert :expired = Accounts.get_session_by_token(prefix, raw)
    end
  end

  describe "revoke_session/2 and revoke_all_sessions_for_user/2" do
    setup %{tenant_prefix: prefix} do
      {:ok, %{user: _u, token: raw}} = Accounts.invite_user(prefix, %{email: "eve@e.co", name: "E"})
      {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
      {:ok, user: user}
    end

    test "revoke single session", %{tenant_prefix: prefix, user: user} do
      {:ok, %{token: raw}} = Accounts.create_session(prefix, user, %{})
      :ok = Accounts.revoke_session(prefix, raw)
      assert :not_found = Accounts.get_session_by_token(prefix, raw)
    end

    test "revoke all revokes every session", %{tenant_prefix: prefix, user: user} do
      {:ok, %{token: r1}} = Accounts.create_session(prefix, user, %{})
      {:ok, %{token: r2}} = Accounts.create_session(prefix, user, %{})
      {:ok, count} = Accounts.revoke_all_sessions_for_user(prefix, user)
      assert count == 2
      assert :not_found = Accounts.get_session_by_token(prefix, r1)
      assert :not_found = Accounts.get_session_by_token(prefix, r2)
    end
  end

  describe "request_password_reset/2 and reset_password/3" do
    setup %{tenant_prefix: prefix} do
      {:ok, %{user: _u, token: raw}} = Accounts.invite_user(prefix, %{email: "frank@e.co", name: "F"})
      {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
      {:ok, user: user}
    end

    test "round trip: request, reset, authenticate with new password", %{tenant_prefix: prefix, user: user} do
      {:ok, %{token: raw}} = Accounts.request_password_reset(prefix, "frank@e.co")
      {:ok, updated} = Accounts.reset_password(prefix, raw, "newSuperSecret1234!")
      assert updated.id == user.id

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password(prefix, "frank@e.co", "superSecret1234!")

      assert {:ok, _} =
               Accounts.authenticate_by_password(prefix, "frank@e.co", "newSuperSecret1234!")
    end

    test "quietly succeeds for unknown email (no account enumeration)", %{tenant_prefix: prefix} do
      assert {:ok, :maybe_sent} = Accounts.request_password_reset(prefix, "nobody@e.co")
    end
  end
end
