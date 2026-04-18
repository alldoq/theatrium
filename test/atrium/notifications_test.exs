defmodule Atrium.NotificationsTest do
  use Atrium.TenantCase
  alias Atrium.Notifications

  defp user_id, do: Ecto.UUID.generate()

  describe "create/4" do
    test "inserts a notification and returns it", %{tenant_prefix: prefix} do
      uid = user_id()
      {:ok, n} =
        Notifications.create(prefix, uid, "document_approved", %{
          title: "Doc approved",
          body: "Your document was approved.",
          resource_type: "Document",
          resource_id: Ecto.UUID.generate()
        })

      assert n.user_id == uid
      assert n.type == "document_approved"
      assert n.title == "Doc approved"
      assert n.body == "Your document was approved."
      assert is_nil(n.read_at)
    end

    test "body and resource fields are optional", %{tenant_prefix: prefix} do
      {:ok, n} = Notifications.create(prefix, user_id(), "announcement", %{title: "Hello"})
      assert n.title == "Hello"
      assert is_nil(n.body)
      assert is_nil(n.resource_type)
      assert is_nil(n.resource_id)
    end

    test "returns error changeset when title is blank", %{tenant_prefix: prefix} do
      assert {:error, cs} = Notifications.create(prefix, user_id(), "announcement", %{title: ""})
      assert errors_on(cs)[:title]
    end
  end

  describe "list_recent/3" do
    test "returns notifications newest-first, capped at limit", %{tenant_prefix: prefix} do
      uid = user_id()
      for i <- 1..5 do
        {:ok, _} = Notifications.create(prefix, uid, "announcement", %{title: "Notif #{i}"})
      end
      results = Notifications.list_recent(prefix, uid, 3)
      assert length(results) == 3
      [first | _] = results
      assert first.title == "Notif 5"
    end

    test "only returns notifications for the given user", %{tenant_prefix: prefix} do
      uid1 = user_id()
      uid2 = user_id()
      {:ok, _} = Notifications.create(prefix, uid1, "announcement", %{title: "For uid1"})
      {:ok, _} = Notifications.create(prefix, uid2, "announcement", %{title: "For uid2"})
      results = Notifications.list_recent(prefix, uid1)
      assert Enum.all?(results, &(&1.user_id == uid1))
    end
  end

  describe "count_unread/2" do
    test "counts only unread notifications for the user", %{tenant_prefix: prefix} do
      uid = user_id()
      {:ok, n1} = Notifications.create(prefix, uid, "announcement", %{title: "A"})
      {:ok, _n2} = Notifications.create(prefix, uid, "announcement", %{title: "B"})
      assert Notifications.count_unread(prefix, uid) == 2

      {:ok, _} = Notifications.mark_read(prefix, uid, n1.id)
      assert Notifications.count_unread(prefix, uid) == 1
    end

    test "returns 0 when all are read", %{tenant_prefix: prefix} do
      uid = user_id()
      {:ok, _} = Notifications.create(prefix, uid, "announcement", %{title: "X"})
      :ok = Notifications.mark_all_read(prefix, uid)
      assert Notifications.count_unread(prefix, uid) == 0
    end
  end

  describe "mark_read/3" do
    test "sets read_at on the notification", %{tenant_prefix: prefix} do
      uid = user_id()
      {:ok, n} = Notifications.create(prefix, uid, "announcement", %{title: "T"})
      {:ok, updated} = Notifications.mark_read(prefix, uid, n.id)
      assert updated.read_at != nil
    end

    test "returns error if notification does not belong to user", %{tenant_prefix: prefix} do
      uid1 = user_id()
      uid2 = user_id()
      {:ok, n} = Notifications.create(prefix, uid1, "announcement", %{title: "T"})
      assert {:error, :not_found} = Notifications.mark_read(prefix, uid2, n.id)
    end
  end

  describe "mark_all_read/2" do
    test "marks all unread notifications for the user", %{tenant_prefix: prefix} do
      uid = user_id()
      {:ok, _} = Notifications.create(prefix, uid, "announcement", %{title: "A"})
      {:ok, _} = Notifications.create(prefix, uid, "announcement", %{title: "B"})
      :ok = Notifications.mark_all_read(prefix, uid)
      assert Notifications.count_unread(prefix, uid) == 0
    end
  end
end
