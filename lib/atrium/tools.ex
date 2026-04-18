defmodule Atrium.Tools do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Tools.{ToolLink, ToolRequest}
  alias Atrium.Notifications.Dispatcher

  @upload_dir Application.compile_env(:atrium, :tool_uploads_dir, "priv/uploads/tools")

  # --- Tool links ------------------------------------------------------------

  def list_tool_links(prefix) do
    Repo.all(from(t in ToolLink, order_by: [asc: t.position, asc: t.inserted_at]), prefix: prefix)
  end

  def get_tool_link!(prefix, id), do: Repo.get!(ToolLink, id, prefix: prefix)

  def create_tool_link(prefix, attrs, actor_user) do
    attrs_with_author = Map.put(stringify(attrs), "author_id", actor_user.id)

    with {:ok, link} <- %ToolLink{} |> ToolLink.changeset(attrs_with_author) |> Repo.insert(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_link.created", %{actor: {:user, actor_user.id}, resource: {"ToolLink", link.id}}) do
      {:ok, link}
    end
  end

  def change_kind(prefix, %ToolLink{} = link, kind, actor_user) when kind in ["link", "download", "request"] do
    with {:ok, updated} <- link |> Ecto.Changeset.change(kind: kind) |> Repo.update(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_link.kind_changed", %{actor: {:user, actor_user.id}, resource: {"ToolLink", link.id}}) do
      {:ok, updated}
    end
  end

  def delete_tool_link(prefix, %ToolLink{} = link, actor_user) do
    if link.file_path, do: delete_upload_file(link.file_path)

    with {:ok, deleted} <- Repo.delete(link, prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_link.deleted", %{actor: {:user, actor_user.id}, resource: {"ToolLink", deleted.id}}) do
      {:ok, deleted}
    end
  end

  def attach_file(prefix, %ToolLink{} = link, %Plug.Upload{} = upload, actor_user) do
    dir = Path.join([@upload_dir, prefix])
    File.mkdir_p!(dir)

    ext = Path.extname(upload.filename)
    stored_name = "#{link.id}#{ext}"
    dest = Path.join(dir, stored_name)

    if link.file_path, do: delete_upload_file(link.file_path)

    with :ok <- File.cp(upload.path, dest),
         {:ok, %{size: size}} <- File.stat(dest),
         {:ok, updated} <-
           link
           |> ToolLink.file_changeset(%{file_path: dest, file_name: upload.filename, file_size: size})
           |> Repo.update(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_link.file_uploaded", %{actor: {:user, actor_user.id}, resource: {"ToolLink", link.id}}) do
      {:ok, updated}
    end
  end

  # --- Tool requests ---------------------------------------------------------

  def list_requests(prefix, tool_id) do
    Repo.all(
      from(r in ToolRequest, where: r.tool_id == ^tool_id, order_by: [desc: r.inserted_at]),
      prefix: prefix
    )
  end

  def count_pending_requests(prefix, tool_id) do
    Repo.one(
      from(r in ToolRequest, where: r.tool_id == ^tool_id and r.status == "pending", select: count()),
      prefix: prefix
    )
  end

  def get_request!(prefix, id), do: Repo.get!(ToolRequest, id, prefix: prefix)

  def create_request(prefix, tool_id, actor_user, message) do
    attrs = %{
      tool_id: tool_id,
      user_id: actor_user.id,
      user_name: actor_user.name,
      user_email: actor_user.email,
      message: message
    }

    with {:ok, req} <- %ToolRequest{} |> ToolRequest.changeset(attrs) |> Repo.insert(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_request.created", %{actor: {:user, actor_user.id}, resource: {"ToolRequest", req.id}}) do
      {:ok, req}
    end
  end

  def approve_request(prefix, %ToolRequest{} = req, reviewer) do
    with {:ok, updated} <- req |> ToolRequest.review_changeset("approved", reviewer.id) |> Repo.update(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_request.approved", %{actor: {:user, reviewer.id}, resource: {"ToolRequest", req.id}}) do
      tool = get_tool_link!(prefix, req.tool_id)
      Dispatcher.tool_request_approved(prefix, updated, tool, reviewer)
      {:ok, updated}
    end
  end

  def reject_request(prefix, %ToolRequest{} = req, reviewer) do
    with {:ok, updated} <- req |> ToolRequest.review_changeset("rejected", reviewer.id) |> Repo.update(prefix: prefix),
         {:ok, _} <- Audit.log(prefix, "tool_request.rejected", %{actor: {:user, reviewer.id}, resource: {"ToolRequest", req.id}}) do
      tool = get_tool_link!(prefix, req.tool_id)
      Dispatcher.tool_request_rejected(prefix, updated, tool, reviewer)
      {:ok, updated}
    end
  end

  # --- Helpers ---------------------------------------------------------------

  defp delete_upload_file(path) do
    File.rm(path)
  rescue
    _ -> :ok
  end

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
