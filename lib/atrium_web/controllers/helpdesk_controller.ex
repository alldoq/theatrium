defmodule AtriumWeb.HelpdeskController do
  use AtriumWeb, :controller
  alias Atrium.Forms

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "helpdesk"}]
       when action in [:index]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    ticket_forms = Forms.list_forms(prefix, "helpdesk") |> Enum.filter(&(&1.status == "published"))
    my_submissions = Forms.list_submissions_for_user(prefix, user.id, "helpdesk")

    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "helpdesk"})

    pending =
      if can_edit do
        Forms.list_pending_submissions(prefix, "helpdesk")
      else
        []
      end

    render(conn, :index,
      ticket_forms: ticket_forms,
      my_submissions: my_submissions,
      pending: pending,
      can_edit: can_edit
    )
  end
end
