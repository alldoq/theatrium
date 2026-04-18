defmodule AtriumWeb.AuditViewerController do
  use AtriumWeb, :controller
  alias Atrium.Audit

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "compliance"}]
       when action in [:index, :export]

  def index(conn, params) do
    filters = build_filters(params)
    events = Audit.list(conn.assigns.tenant_prefix, Keyword.put(filters, :limit, 200))
    render(conn, :index, events: events, filters: params)
  end

  def export(conn, params) do
    filters = build_filters(params)
    events = Audit.list(conn.assigns.tenant_prefix, Keyword.put(filters, :limit, 10_000))
    csv = to_csv(events)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=audit-export.csv")
    |> send_resp(200, csv)
  end

  defp build_filters(params) do
    Enum.reduce([:action, :actor_id, :resource_type, :resource_id], [], fn key, acc ->
      case Map.get(params, to_string(key)) do
        nil -> acc
        "" -> acc
        val -> [{key, val} | acc]
      end
    end)
  end

  defp to_csv(events) do
    header = "occurred_at,actor_type,actor_id,action,resource_type,resource_id,changes,context"

    rows =
      Enum.map(events, fn e ->
        Enum.join(
          [
            DateTime.to_iso8601(e.occurred_at),
            e.actor_type,
            e.actor_id,
            e.action,
            e.resource_type,
            e.resource_id,
            Jason.encode!(e.changes),
            Jason.encode!(e.context)
          ],
          ","
        )
      end)

    Enum.join([header | rows], "\n")
  end
end
