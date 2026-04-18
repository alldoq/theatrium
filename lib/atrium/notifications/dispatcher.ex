defmodule Atrium.Notifications.Dispatcher do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Notifications
  alias Atrium.Notifications.Notification
  alias Atrium.Accounts.User
  alias Atrium.Authorization.SectionAcl
  alias Atrium.Authorization.Membership

  def document_approved(prefix, document, _actor_user) do
    Notifications.create(prefix, document.author_id, "document_approved", %{
      title: "Document approved: #{document.title}",
      body: "Your document has been approved.",
      resource_type: "Document",
      resource_id: document.id
    })

    :ok
  end

  def document_rejected(prefix, document, _actor_user) do
    Notifications.create(prefix, document.author_id, "document_rejected", %{
      title: "Document returned for revision: #{document.title}",
      body: "Your document has been returned to draft.",
      resource_type: "Document",
      resource_id: document.id
    })

    :ok
  end

  def document_submitted(prefix, document, actor_user) do
    approver_ids = approvers_for_section(prefix, document.section_key)
    recipients = Enum.reject(approver_ids, &(&1 == actor_user.id))

    Enum.each(recipients, fn user_id ->
      Notifications.create(prefix, user_id, "document_submitted", %{
        title: "Document ready for review: #{document.title}",
        body: "A document has been submitted for your approval.",
        resource_type: "Document",
        resource_id: document.id
      })
    end)

    :ok
  end

  def form_submission(prefix, form, submission, _actor_user) do
    user_recipients =
      (form.notification_recipients || [])
      |> Enum.filter(fn r -> (r["type"] || r[:type]) == "user" end)
      |> Enum.map(fn r -> r["id"] || r[:id] end)
      |> Enum.reject(&is_nil/1)

    Enum.each(user_recipients, fn user_id ->
      Notifications.create(prefix, user_id, "form_submission", %{
        title: "New submission: #{form.title}",
        body: "A new form submission has been received.",
        resource_type: "FormSubmission",
        resource_id: submission.id
      })
    end)

    :ok
  end

  def tool_request_approved(prefix, request, tool, _reviewer) do
    Notifications.create(prefix, request.user_id, "tool_request_approved", %{
      title: "Request approved: #{tool.title}",
      body: "Your access request has been approved.",
      resource_type: "ToolRequest",
      resource_id: request.id
    })

    :ok
  end

  def tool_request_rejected(prefix, request, tool, _reviewer) do
    Notifications.create(prefix, request.user_id, "tool_request_rejected", %{
      title: "Request declined: #{tool.title}",
      body: "Your access request has been declined.",
      resource_type: "ToolRequest",
      resource_id: request.id
    })

    :ok
  end

  def announcement_created(prefix, announcement, actor_user) do
    active_user_ids =
      from(u in User, where: u.status == "active", select: u.id)
      |> Repo.all(prefix: prefix)
      |> Enum.reject(&(&1 == actor_user.id))

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rows =
      Enum.map(active_user_ids, fn uid ->
        %{
          id: Ecto.UUID.generate(),
          user_id: uid,
          type: "announcement",
          title: "New announcement: #{announcement.title}",
          body: nil,
          resource_type: "Announcement",
          resource_id: announcement.id,
          read_at: nil,
          inserted_at: now
        }
      end)

    if rows != [] do
      Repo.insert_all(Notification, rows, prefix: prefix)
    end

    :ok
  end

  defp approvers_for_section(prefix, section_key) do
    acls =
      from(a in SectionAcl,
        where: a.section_key == ^to_string(section_key) and a.capability == "approve"
      )
      |> Repo.all(prefix: prefix)

    {user_acls, group_acls} =
      Enum.split_with(acls, &(&1.principal_type == "user"))

    direct_ids = Enum.map(user_acls, & &1.principal_id)

    group_ids = Enum.map(group_acls, & &1.principal_id)

    group_member_ids =
      if group_ids == [] do
        []
      else
        from(m in Membership,
          where: m.group_id in ^group_ids,
          select: m.user_id
        )
        |> Repo.all(prefix: prefix)
      end

    (direct_ids ++ group_member_ids)
    |> Enum.uniq()
  end
end
