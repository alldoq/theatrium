defmodule AtriumWeb.FeedbackController do
  use AtriumWeb, :controller
  alias Atrium.Forms

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "feedback"}]
       when action in [:index]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "feedback"})

    published = Forms.list_forms(prefix, "feedback", status: "published")

    {all_forms, submission_counts} =
      if can_edit do
        forms = Forms.list_forms(prefix, "feedback")
        counts = Map.new(forms, fn f -> {f.id, Forms.count_submissions(prefix, f.id)} end)
        {forms, counts}
      else
        {published, %{}}
      end

    render(conn, :index,
      published: published,
      all_forms: all_forms,
      submission_counts: submission_counts,
      can_edit: can_edit
    )
  end
end
