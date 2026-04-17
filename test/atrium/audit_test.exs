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
      for i <- 1..3 do
        {:ok, _} = Audit.log_global("tenant.created", %{actor: :system, resource: {"Tenant", "id-#{i}"}})
      end

      {:ok, _} = Audit.log_global("tenant.suspended", %{actor: :system, resource: {"Tenant", "id-1"}})

      events = Audit.list_global(action: "tenant.created")
      assert length(events) == 3
      assert Enum.all?(events, &(&1.action == "tenant.created"))
    end
  end
end
