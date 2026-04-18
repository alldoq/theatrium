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

defmodule Atrium.Notifications.DispatcherTest do
  use Atrium.TenantCase
  alias Atrium.Notifications
  alias Atrium.Notifications.Dispatcher
  alias Atrium.Accounts
  alias Atrium.Authorization

  defp create_user(prefix, email) do
    {:ok, %{user: _user, token: raw}} =
      Accounts.invite_user(prefix, %{email: email, name: "Test User"})
    {:ok, user} = Accounts.activate_user(prefix, raw, "password123456!")
    user
  end

  defp grant(prefix, section_key, user_id, capability) do
    Authorization.grant_section(prefix, section_key, {:user, user_id}, capability)
  end

  describe "document_approved/3" do
    test "creates a notification for the document author", %{tenant_prefix: prefix} do
      author = create_user(prefix, "author_#{System.unique_integer()}@test.com")
      reviewer = create_user(prefix, "reviewer_#{System.unique_integer()}@test.com")

      document = %{
        id: Ecto.UUID.generate(),
        title: "HR Policy",
        author_id: author.id,
        section_key: "hr"
      }

      :ok = Dispatcher.document_approved(prefix, document, reviewer)

      [notif] = Notifications.list_recent(prefix, author.id)
      assert notif.type == "document_approved"
      assert notif.title =~ "HR Policy"
      assert notif.resource_type == "Document"
      assert notif.resource_id == document.id
    end
  end

  describe "document_rejected/3" do
    test "creates a notification for the document author", %{tenant_prefix: prefix} do
      author = create_user(prefix, "author2_#{System.unique_integer()}@test.com")
      reviewer = create_user(prefix, "reviewer2_#{System.unique_integer()}@test.com")

      document = %{
        id: Ecto.UUID.generate(),
        title: "Rejected Doc",
        author_id: author.id,
        section_key: "hr"
      }

      :ok = Dispatcher.document_rejected(prefix, document, reviewer)

      [notif] = Notifications.list_recent(prefix, author.id)
      assert notif.type == "document_rejected"
      assert notif.title =~ "Rejected Doc"
    end
  end

  describe "document_submitted/3" do
    test "notifies users with :approve on the section", %{tenant_prefix: prefix} do
      author = create_user(prefix, "submit_author_#{System.unique_integer()}@test.com")
      approver = create_user(prefix, "approver_#{System.unique_integer()}@test.com")
      {:ok, _} = grant(prefix, "hr", approver.id, :approve)

      document = %{
        id: Ecto.UUID.generate(),
        title: "Pending Doc",
        author_id: author.id,
        section_key: "hr"
      }

      :ok = Dispatcher.document_submitted(prefix, document, author)

      notifs = Notifications.list_recent(prefix, approver.id)
      assert length(notifs) == 1
      assert hd(notifs).type == "document_submitted"
    end

    test "does not notify the submitting author", %{tenant_prefix: prefix} do
      author = create_user(prefix, "self_submit_#{System.unique_integer()}@test.com")
      {:ok, _} = grant(prefix, "hr", author.id, :approve)

      document = %{
        id: Ecto.UUID.generate(),
        title: "Self Submit",
        author_id: author.id,
        section_key: "hr"
      }

      :ok = Dispatcher.document_submitted(prefix, document, author)

      assert Notifications.list_recent(prefix, author.id) == []
    end
  end

  describe "tool_request_approved/3" do
    test "notifies the requester", %{tenant_prefix: prefix} do
      requester = create_user(prefix, "requester_#{System.unique_integer()}@test.com")
      reviewer  = create_user(prefix, "tool_rev_#{System.unique_integer()}@test.com")

      request = %{
        id: Ecto.UUID.generate(),
        user_id: requester.id,
        tool_id: Ecto.UUID.generate()
      }

      tool = %{title: "VPN Access"}

      :ok = Dispatcher.tool_request_approved(prefix, request, tool, reviewer)

      [notif] = Notifications.list_recent(prefix, requester.id)
      assert notif.type == "tool_request_approved"
      assert notif.title =~ "VPN Access"
    end
  end

  describe "tool_request_rejected/3" do
    test "notifies the requester", %{tenant_prefix: prefix} do
      requester = create_user(prefix, "reject_req_#{System.unique_integer()}@test.com")
      reviewer  = create_user(prefix, "reject_rev_#{System.unique_integer()}@test.com")

      request = %{
        id: Ecto.UUID.generate(),
        user_id: requester.id,
        tool_id: Ecto.UUID.generate()
      }

      tool = %{title: "VPN Access"}

      :ok = Dispatcher.tool_request_rejected(prefix, request, tool, reviewer)

      [notif] = Notifications.list_recent(prefix, requester.id)
      assert notif.type == "tool_request_rejected"
    end
  end

  describe "form_submission/4" do
    test "notifies user-type notification recipients", %{tenant_prefix: prefix} do
      submitter = create_user(prefix, "submitter_#{System.unique_integer()}@test.com")
      recipient = create_user(prefix, "form_recip_#{System.unique_integer()}@test.com")

      form = %{
        id: Ecto.UUID.generate(),
        title: "Expense Form",
        notification_recipients: [%{"type" => "user", "id" => recipient.id}]
      }

      submission = %{id: Ecto.UUID.generate()}

      :ok = Dispatcher.form_submission(prefix, form, submission, submitter)

      [notif] = Notifications.list_recent(prefix, recipient.id)
      assert notif.type == "form_submission"
      assert notif.title =~ "Expense Form"
    end

    test "skips email-type recipients gracefully", %{tenant_prefix: prefix} do
      submitter = create_user(prefix, "submitter2_#{System.unique_integer()}@test.com")

      form = %{
        id: Ecto.UUID.generate(),
        title: "Expense Form",
        notification_recipients: [%{"type" => "email", "email" => "external@example.com"}]
      }

      submission = %{id: Ecto.UUID.generate()}

      assert :ok = Dispatcher.form_submission(prefix, form, submission, submitter)
    end
  end

  describe "announcement_created/3" do
    test "notifies all active users except the author", %{tenant_prefix: prefix} do
      author = create_user(prefix, "ann_author_#{System.unique_integer()}@test.com")
      reader = create_user(prefix, "ann_reader_#{System.unique_integer()}@test.com")

      announcement = %{
        id: Ecto.UUID.generate(),
        title: "Company Picnic"
      }

      :ok = Dispatcher.announcement_created(prefix, announcement, author)

      reader_notifs = Notifications.list_recent(prefix, reader.id)
      assert Enum.any?(reader_notifs, &(&1.type == "announcement" and &1.title =~ "Company Picnic"))

      author_notifs = Notifications.list_recent(prefix, author.id)
      assert Enum.all?(author_notifs, &(&1.user_id != author.id or &1.type != "announcement"))
    end
  end
end
