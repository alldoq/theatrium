defmodule Atrium.AuditTest do
  use Atrium.DataCase, async: true
  alias Atrium.Audit

  describe "log_global/2" do
    test "writes a row with action, actor, changes, context" do
      {:ok, event} =
        Audit.log_global("tenant.created", %{
          actor: {:super_admin, "11111111-1111-1111-1111-111111111111"},
          resource: {"Tenant", "abc-123"},
          changes: %{"slug" => [nil, "mcl"]},
          context: %{"request_id" => "req-1"}
        })

      assert event.action == "tenant.created"
      assert event.actor_type == "super_admin"
      assert event.actor_id == "11111111-1111-1111-1111-111111111111"
      assert event.resource_type == "Tenant"
      assert event.resource_id == "abc-123"
      assert event.changes == %{"slug" => [nil, "mcl"]}
      assert event.context == %{"request_id" => "req-1"}
      assert event.occurred_at
    end

    test "supports system actor" do
      {:ok, event} = Audit.log_global("system.heartbeat", %{actor: :system})
      assert event.actor_type == "system"
      assert event.actor_id == nil
    end

    test "requires an action" do
      assert_raise ArgumentError, fn -> Audit.log_global(nil, %{}) end
    end
  end

  describe "list_global/1" do
    test "filters by action and paginates" do
      # Count pre-existing tenant.created events committed by other tests
      before_count = length(Audit.list_global(action: "tenant.created"))

      for i <- 1..3 do
        {:ok, _} = Audit.log_global("tenant.created", %{actor: :system, resource: {"Tenant", "id-#{i}"}})
      end

      {:ok, _} = Audit.log_global("tenant.suspended", %{actor: :system, resource: {"Tenant", "id-1"}})

      events = Audit.list_global(action: "tenant.created")
      assert length(events) == before_count + 3
      assert Enum.all?(events, &(&1.action == "tenant.created"))
    end
  end
end

defmodule Atrium.AuditTenantTest do
  use Atrium.TenantCase
  alias Atrium.Audit
  alias Atrium.Accounts

  test "log/2 writes a tenant audit event", %{tenant_prefix: prefix} do
    {:ok, event} =
      Audit.log(prefix, "user.invited", %{
        actor: :system,
        resource: {"User", "u-1"},
        changes: %{"email" => [nil, "a@e.co"]}
      })

    assert event.action == "user.invited"
    assert event.resource_type == "User"
  end

  test "list/1 filters by resource", %{tenant_prefix: prefix} do
    {:ok, _} = Audit.log(prefix, "user.invited", %{actor: :system, resource: {"User", "u-1"}})
    {:ok, _} = Audit.log(prefix, "user.invited", %{actor: :system, resource: {"User", "u-2"}})
    rows = Audit.list(prefix, resource_type: "User", resource_id: "u-1")
    assert length(rows) == 1
  end

  test "changeset_diff/2 redacts password fields", %{tenant_prefix: prefix} do
    old = %Atrium.Accounts.User{email: "a@e.co", hashed_password: "hashA"}
    new = %Atrium.Accounts.User{email: "b@e.co", hashed_password: "hashB"}
    diff = Audit.changeset_diff(old, new)
    assert diff["email"] == ["a@e.co", "b@e.co"]
    assert diff["hashed_password"] == ["[REDACTED]", "[REDACTED]"]
  end

  test "history_for/3 returns events for a resource", %{tenant_prefix: prefix} do
    {:ok, _} = Audit.log(prefix, "user.invited", %{actor: :system, resource: {"User", "u-1"}})
    {:ok, _} = Audit.log(prefix, "user.activated", %{actor: :system, resource: {"User", "u-1"}})
    history = Audit.history_for(prefix, "User", "u-1")
    assert length(history) == 2
  end
end
