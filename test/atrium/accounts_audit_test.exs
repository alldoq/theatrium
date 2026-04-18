defmodule Atrium.AccountsAuditTest do
  use Atrium.TenantCase
  alias Atrium.Accounts
  alias Atrium.Audit

  test "invite_user writes user.invited event", %{tenant_prefix: prefix} do
    {:ok, %{user: user}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    events = Audit.list(prefix, action: "user.invited")
    assert Enum.any?(events, fn e -> e.resource_id == user.id end)
  end

  test "activate_user writes user.activated event", %{tenant_prefix: prefix} do
    {:ok, %{token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")
    assert Enum.any?(Audit.list(prefix, action: "user.activated"), &(&1.resource_id == user.id))
  end

  test "authenticate_by_password writes user.login on success and user.login_failed on failure", %{tenant_prefix: prefix} do
    {:ok, %{token: raw}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, _} = Accounts.activate_user(prefix, raw, "superSecret1234!")

    {:ok, _} = Accounts.authenticate_by_password(prefix, "a@e.co", "superSecret1234!")
    assert length(Audit.list(prefix, action: "user.login")) == 1

    {:error, _} = Accounts.authenticate_by_password(prefix, "a@e.co", "wrong")
    assert length(Audit.list(prefix, action: "user.login_failed")) == 1
  end

  test "reset_password writes password.reset_completed and session.revoked events", %{tenant_prefix: prefix} do
    {:ok, %{token: invite}} = Accounts.invite_user(prefix, %{email: "a@e.co", name: "A"})
    {:ok, user} = Accounts.activate_user(prefix, invite, "superSecret1234!")
    {:ok, %{token: _}} = Accounts.create_session(prefix, user, %{})
    {:ok, %{token: raw}} = Accounts.request_password_reset(prefix, "a@e.co")
    {:ok, _} = Accounts.reset_password(prefix, raw, "newSuperSecret1234!")

    assert Audit.list(prefix, action: "password.reset_completed") != []
    assert Audit.list(prefix, action: "session.revoked") != []
  end
end
