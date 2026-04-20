defmodule AtriumWeb.ComplianceController do
  use AtriumWeb, :controller
  alias Atrium.Documents

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "compliance"}]
       when action in [:index]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    policies = Documents.list_documents(prefix, "compliance", status: "approved")

    drafts =
      if Atrium.Authorization.Policy.can?(prefix, conn.assigns.current_user, :edit, {:section, "compliance"}) do
        Documents.list_documents(prefix, "compliance")
        |> Enum.reject(&(&1.status == "approved"))
      else
        []
      end

    render(conn, :index, policies: policies, drafts: drafts)
  end
end
