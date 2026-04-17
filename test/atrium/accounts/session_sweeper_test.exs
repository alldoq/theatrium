defmodule Atrium.Accounts.SessionSweeperTest do
  use Atrium.TenantCase
  alias Atrium.Accounts
  alias Atrium.Accounts.SessionSweeper

  test "sweep/1 deletes only expired sessions for a tenant", %{tenant_prefix: prefix} do
    {:ok, %{user: _u, token: raw}} = Accounts.invite_user(prefix, %{email: "x@e.co", name: "X"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "superSecret1234!")

    {:ok, %{token: good}} = Accounts.create_session(prefix, user, %{}, ttl_minutes: 60)
    {:ok, %{token: expired}} = Accounts.create_session(prefix, user, %{}, ttl_minutes: -1)

    {:ok, count} = SessionSweeper.sweep(prefix)
    assert count == 1
    assert {:ok, _} = Accounts.get_session_by_token(prefix, good)
    assert :not_found = Accounts.get_session_by_token(prefix, expired)
  end
end
