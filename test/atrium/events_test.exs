defmodule Atrium.EventsTest do
  use Atrium.TenantCase, async: false

  alias Atrium.Events
  alias Atrium.Accounts

  defp build_user(prefix) do
    {:ok, %{user: user}} =
      Accounts.invite_user(prefix, %{
        email: "events_actor_#{System.unique_integer([:positive])}@example.com",
        name: "Events Actor"
      })
    user
  end

  defp build_event(prefix, user, attrs \\ %{}) do
    base = %{
      title: "Team Offsite",
      starts_at: ~U[2026-06-15 09:00:00Z],
      ends_at: ~U[2026-06-15 17:00:00Z],
      all_day: false
    }
    merged = Map.merge(base, attrs)
    # Drop ends_at if starts_at was overridden and ends_at was not explicitly set,
    # to avoid the ends_after_starts validation firing on the default ends_at.
    merged =
      if Map.has_key?(attrs, :starts_at) and not Map.has_key?(attrs, :ends_at) do
        Map.delete(merged, :ends_at)
      else
        merged
      end
    Events.create_event(prefix, merged, user)
  end

  describe "create_event/3" do
    test "creates an event with required fields", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      assert event.title == "Team Offsite"
      assert event.author_id == user.id
      assert event.all_day == false
    end

    test "returns error for missing title", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:error, cs} = Events.create_event(prefix, %{starts_at: ~U[2026-06-15 09:00:00Z]}, user)
      assert errors_on(cs)[:title]
    end

    test "returns error for missing starts_at", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      assert {:error, cs} = Events.create_event(prefix, %{title: "No Date"}, user)
      assert errors_on(cs)[:starts_at]
    end

    test "logs event.created audit event", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      events = Atrium.Audit.history_for(prefix, "Event", event.id)
      assert Enum.any?(events, &(&1.action == "event.created"))
    end
  end

  describe "get_event!/2" do
    test "returns the event by id", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      found = Events.get_event!(prefix, event.id)
      assert found.id == event.id
    end

    test "raises Ecto.NoResultsError for unknown id", %{tenant_prefix: prefix} do
      assert_raise Ecto.NoResultsError, fn ->
        Events.get_event!(prefix, Ecto.UUID.generate())
      end
    end
  end

  describe "list_events_for_month/3" do
    test "returns events whose starts_at falls in the given month", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, june_event} = build_event(prefix, user, %{title: "June Event", starts_at: ~U[2026-06-10 10:00:00Z]})
      {:ok, _july_event} = build_event(prefix, user, %{title: "July Event", starts_at: ~U[2026-07-01 10:00:00Z]})
      results = Events.list_events_for_month(prefix, 2026, 6)
      ids = Enum.map(results, & &1.id)
      assert june_event.id in ids
      refute Enum.any?(results, &(&1.title == "July Event"))
    end

    test "returns empty list when no events in month", %{tenant_prefix: prefix} do
      assert Events.list_events_for_month(prefix, 2099, 12) == []
    end

    test "returns events ordered by starts_at ascending", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, _} = build_event(prefix, user, %{title: "Later", starts_at: ~U[2026-06-20 10:00:00Z]})
      {:ok, _} = build_event(prefix, user, %{title: "Earlier", starts_at: ~U[2026-06-05 10:00:00Z]})
      results = Events.list_events_for_month(prefix, 2026, 6)
      titles = Enum.map(results, & &1.title)
      earlier_idx = Enum.find_index(titles, &(&1 == "Earlier"))
      later_idx = Enum.find_index(titles, &(&1 == "Later"))
      assert earlier_idx < later_idx
    end
  end

  describe "update_event/4" do
    test "updates title and location", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      {:ok, updated} = Events.update_event(prefix, event, %{title: "New Title", location: "HQ"}, user)
      assert updated.title == "New Title"
      assert updated.location == "HQ"
    end

    test "returns error for blank title", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      assert {:error, cs} = Events.update_event(prefix, event, %{title: ""}, user)
      assert errors_on(cs)[:title]
    end

    test "logs event.updated audit event", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      {:ok, _} = Events.update_event(prefix, event, %{title: "Updated"}, user)
      history = Atrium.Audit.history_for(prefix, "Event", event.id)
      assert Enum.any?(history, &(&1.action == "event.updated"))
    end
  end

  describe "delete_event/3" do
    test "removes the event", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      {:ok, _} = Events.delete_event(prefix, event, user)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event!(prefix, event.id) end
    end

    test "logs event.deleted audit event", %{tenant_prefix: prefix} do
      user = build_user(prefix)
      {:ok, event} = build_event(prefix, user)
      {:ok, _} = Events.delete_event(prefix, event, user)
      history = Atrium.Audit.history_for(prefix, "Event", event.id)
      assert Enum.any?(history, &(&1.action == "event.deleted"))
    end
  end
end
