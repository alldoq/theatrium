defmodule AtriumWeb.ToolsController do
  use AtriumWeb, :controller
  alias Atrium.Tools

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "tools"}]
       when action in [:index, :download, :request_form, :submit_request]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "tools"}]
       when action in [:create_tool, :delete_tool, :upload_file, :change_kind, :list_requests, :approve_request, :reject_request]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    tools = Tools.list_tool_links(prefix)
    can_edit = Atrium.Authorization.Policy.can?(prefix, conn.assigns.current_user, :edit, {:section, "tools"})
    render(conn, :index, tools: tools, can_edit: can_edit)
  end

  def create_tool(conn, %{"tool" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Tools.create_tool_link(prefix, params, user) do
      {:ok, _} -> conn |> put_flash(:info, "Tool added.") |> redirect(to: ~p"/tools")
      {:error, _} -> conn |> put_flash(:error, "Could not save tool.") |> redirect(to: ~p"/tools")
    end
  end

  def delete_tool(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    link = Tools.get_tool_link!(prefix, id)

    case Tools.delete_tool_link(prefix, link, user) do
      {:ok, _} -> conn |> put_flash(:info, "Tool removed.") |> redirect(to: ~p"/tools")
      {:error, _} -> conn |> put_flash(:error, "Could not remove tool.") |> redirect(to: ~p"/tools")
    end
  end

  def change_kind(conn, %{"id" => id, "kind" => kind}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    link = Tools.get_tool_link!(prefix, id)

    case Tools.change_kind(prefix, link, kind, user) do
      {:ok, _} -> redirect(conn, to: ~p"/tools")
      {:error, _} -> conn |> put_flash(:error, "Could not update tool type.") |> redirect(to: ~p"/tools")
    end
  end

  def upload_file(conn, %{"id" => id, "file" => upload}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    link = Tools.get_tool_link!(prefix, id)

    case Tools.attach_file(prefix, link, upload, user) do
      {:ok, _} -> conn |> put_flash(:info, "File uploaded.") |> redirect(to: ~p"/tools")
      {:error, _} -> conn |> put_flash(:error, "Upload failed.") |> redirect(to: ~p"/tools")
    end
  end

  def download(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    link = Tools.get_tool_link!(prefix, id)

    if link.kind == "download" && link.file_path && File.exists?(link.file_path) do
      conn
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{link.file_name}"))
      |> send_file(200, link.file_path)
    else
      conn |> put_flash(:error, "File not available.") |> redirect(to: ~p"/tools")
    end
  end

  def request_form(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    tool = Tools.get_tool_link!(prefix, id)
    render(conn, :request_form, tool: tool)
  end

  def submit_request(conn, %{"id" => id} = params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    tool = Tools.get_tool_link!(prefix, id)
    message = get_in(params, ["request", "message"]) || ""

    case Tools.create_request(prefix, tool.id, user, message) do
      {:ok, _} ->
        conn |> put_flash(:info, "Request submitted. You will be notified when it is reviewed.") |> redirect(to: ~p"/tools")
      {:error, _} ->
        conn |> put_flash(:error, "Could not submit request.") |> render(:request_form, tool: tool)
    end
  end

  def list_requests(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    tool = Tools.get_tool_link!(prefix, id)
    requests = Tools.list_requests(prefix, tool.id)
    render(conn, :requests, tool: tool, requests: requests)
  end

  def approve_request(conn, %{"id" => tool_id, "rid" => rid}) do
    prefix = conn.assigns.tenant_prefix
    req = Tools.get_request!(prefix, rid)

    case Tools.approve_request(prefix, req, conn.assigns.current_user) do
      {:ok, _} -> conn |> put_flash(:info, "Request approved.") |> redirect(to: ~p"/tools/#{tool_id}/requests")
      {:error, _} -> conn |> put_flash(:error, "Could not approve request.") |> redirect(to: ~p"/tools/#{tool_id}/requests")
    end
  end

  def reject_request(conn, %{"id" => tool_id, "rid" => rid}) do
    prefix = conn.assigns.tenant_prefix
    req = Tools.get_request!(prefix, rid)

    case Tools.reject_request(prefix, req, conn.assigns.current_user) do
      {:ok, _} -> conn |> put_flash(:info, "Request rejected.") |> redirect(to: ~p"/tools/#{tool_id}/requests")
      {:error, _} -> conn |> put_flash(:error, "Could not reject request.") |> redirect(to: ~p"/tools/#{tool_id}/requests")
    end
  end
end
