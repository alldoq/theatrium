defmodule AtriumWeb.ScormController do
  use AtriumWeb, :controller
  alias Atrium.{Learning, Scorm}

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "learning"}]
       when action in [:launch, :asset, :commit]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "learning"}]
       when action in [:new_upload, :create, :delete]

  # ─── Editor: upload / delete ───────────────────────────────────────────

  def new_upload(conn, %{"id" => course_id}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, course_id)
    existing = Scorm.list_packages(prefix, course.id)
    render(conn, :new_upload, course: course, packages: existing)
  end

  def create(conn, %{"id" => course_id, "scorm" => %{"file" => %Plug.Upload{} = upload}}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    course = Learning.get_course!(prefix, course_id)

    case Scorm.upload_package(prefix, course.id, upload, user) do
      {:ok, _pkg} ->
        conn
        |> put_flash(:info, "SCORM package uploaded.")
        |> redirect(to: ~p"/learning/#{course.id}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Upload failed: #{inspect(reason)}")
        |> redirect(to: ~p"/learning/#{course.id}/scorm/upload")
    end
  end

  def create(conn, %{"id" => course_id}) do
    conn
    |> put_flash(:error, "Pick a .zip file to upload.")
    |> redirect(to: ~p"/learning/#{course_id}/scorm/upload")
  end

  def delete(conn, %{"id" => course_id, "package_id" => pkg_id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    pkg = Scorm.get_package!(prefix, pkg_id)
    {:ok, _} = Scorm.delete_package(prefix, pkg, user)

    conn
    |> put_flash(:info, "Package removed.")
    |> redirect(to: ~p"/learning/#{course_id}/scorm/upload")
  end

  # ─── Player ────────────────────────────────────────────────────────────

  def launch(conn, %{"id" => course_id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    course = Learning.get_course!(prefix, course_id)

    case Scorm.get_package_for_course(prefix, course.id) do
      nil ->
        conn |> put_flash(:error, "No SCORM package attached to this course.") |> redirect(to: ~p"/learning/#{course.id}")

      pkg ->
        {:ok, attempt} = Scorm.get_or_create_attempt(prefix, pkg, user.id)

        conn
        |> put_root_layout(false)
        |> put_layout(false)
        |> render(:launch, course: course, package: pkg, attempt: attempt)
    end
  end

  def asset(conn, %{"id" => course_id, "package_id" => pkg_id, "path" => path_parts}) do
    prefix = conn.assigns.tenant_prefix
    _course = Learning.get_course!(prefix, course_id)
    pkg = Scorm.get_package!(prefix, pkg_id)
    requested = Path.join(path_parts)
    abs_dir = Scorm.package_dir(prefix, pkg.id)
    candidate = Path.join(abs_dir, requested) |> Path.expand()
    base = Path.expand(abs_dir)

    cond do
      not String.starts_with?(candidate, base) ->
        conn |> send_resp(403, "forbidden")

      not File.regular?(candidate) ->
        conn |> send_resp(404, "not found")

      true ->
        conn
        |> put_resp_content_type(mime_for(candidate))
        |> send_file(200, candidate)
    end
  end

  def commit(conn, %{"id" => course_id, "package_id" => pkg_id} = params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    _course = Learning.get_course!(prefix, course_id)
    pkg = Scorm.get_package!(prefix, pkg_id)

    {:ok, attempt} = Scorm.get_or_create_attempt(prefix, pkg, user.id)
    cmi = Map.get(params, "cmi") || %{}
    {:ok, updated} = Scorm.commit_attempt(prefix, attempt, cmi)

    if Scorm.completed?(updated) do
      Learning.complete_course(prefix, pkg.course_id, user)
    end

    json(conn, %{ok: true, lesson_status: updated.lesson_status})
  end

  defp mime_for(path) do
    case Path.extname(path) |> String.downcase() do
      ".html" -> "text/html"
      ".htm"  -> "text/html"
      ".css"  -> "text/css"
      ".js"   -> "application/javascript"
      ".json" -> "application/json"
      ".png"  -> "image/png"
      ".jpg"  -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif"  -> "image/gif"
      ".svg"  -> "image/svg+xml"
      ".mp4"  -> "video/mp4"
      ".mp3"  -> "audio/mpeg"
      ".woff" -> "font/woff"
      ".woff2" -> "font/woff2"
      ".ttf"  -> "font/ttf"
      ".xml"  -> "application/xml"
      _ -> "application/octet-stream"
    end
  end
end
