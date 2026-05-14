defmodule Atrium.Scorm do
  @moduledoc """
  SCORM 1.2 package storage + attempt tracking.

  Storage layout (plaintext — SCORM courses ship HTML/JS and must be
  served as-is to the player iframe):

      <uploads_root>/scorm/<tenant_prefix>/<package_id>/...

  The launch URL is resolved relative to that root.
  """

  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Scorm.{Package, Attempt}

  @max_bytes 500 * 1024 * 1024

  # ─── Packages ──────────────────────────────────────────────────────────

  def list_packages(prefix, course_id) do
    Repo.all(
      from(p in Package, where: p.course_id == ^course_id, order_by: [desc: p.inserted_at]),
      prefix: prefix
    )
  end

  def get_package!(prefix, id), do: Repo.get!(Package, id, prefix: prefix)

  def get_package_for_course(prefix, course_id) do
    Repo.one(
      from(p in Package, where: p.course_id == ^course_id, order_by: [desc: p.inserted_at], limit: 1),
      prefix: prefix
    )
  end

  def delete_package(prefix, %Package{} = pkg, actor_user) do
    Repo.transaction(fn ->
      case Repo.delete(pkg, prefix: prefix) do
        {:ok, deleted} ->
          File.rm_rf!(package_dir(prefix, deleted.id))
          {:ok, _} = Audit.log(prefix, "scorm.deleted", %{actor: {:user, actor_user.id}, resource: {"ScormPackage", deleted.id}})
          deleted
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  @doc """
  Accepts a Plug.Upload that points at a SCORM .zip file. Extracts the
  package, parses imsmanifest.xml, persists the Package row.
  """
  def upload_package(prefix, course_id, %Plug.Upload{} = upload, actor_user) do
    with :ok <- validate_upload(upload),
         {:ok, pkg_id} <- {:ok, Ecto.UUID.generate()},
         dest = package_dir(prefix, pkg_id),
         :ok <- File.mkdir_p(dest),
         {:ok, _files} <- extract(upload.path, dest),
         {:ok, manifest} <- parse_manifest(dest),
         attrs = %{
           course_id: course_id,
           title: manifest.title,
           version: manifest.version,
           launch_url: manifest.launch_url,
           manifest_json: manifest.raw,
           storage_path: storage_relpath(prefix, pkg_id),
           byte_size: upload.path |> File.stat!() |> Map.fetch!(:size),
           uploaded_by_id: actor_user.id
         },
         {:ok, pkg} <- %Package{id: pkg_id} |> Package.changeset(attrs) |> Repo.insert(prefix: prefix) do
      Audit.log(prefix, "scorm.uploaded", %{actor: {:user, actor_user.id}, resource: {"ScormPackage", pkg.id}})
      {:ok, pkg}
    else
      {:error, reason} = err ->
        # best-effort cleanup
        cleanup_partial(prefix, reason)
        err
    end
  end

  defp cleanup_partial(_prefix, _reason), do: :ok

  defp validate_upload(%Plug.Upload{path: path, filename: filename}) do
    cond do
      not File.exists?(path) -> {:error, :upload_missing}
      not String.ends_with?(String.downcase(filename), ".zip") -> {:error, :not_a_zip}
      File.stat!(path).size > @max_bytes -> {:error, :too_large}
      true -> :ok
    end
  end

  defp extract(zip_path, dest_dir) do
    case :zip.unzip(String.to_charlist(zip_path), [{:cwd, String.to_charlist(dest_dir)}]) do
      {:ok, files} -> {:ok, files}
      {:error, reason} -> {:error, {:zip_error, reason}}
    end
  end

  defp parse_manifest(dir) do
    manifest_path = Path.join(dir, "imsmanifest.xml")

    cond do
      not File.exists?(manifest_path) ->
        {:error, :missing_manifest}

      true ->
        case File.read(manifest_path) do
          {:ok, xml} -> {:ok, extract_manifest_fields(xml)}
          {:error, reason} -> {:error, {:read_error, reason}}
        end
    end
  end

  # Lightweight manifest parser. SCORM 1.2 manifests are XML; we pluck the
  # title and the first resource href without pulling in a full XML library.
  defp extract_manifest_fields(xml) do
    title =
      case Regex.run(~r/<title[^>]*>([^<]+)<\/title>/i, xml) do
        [_, t] -> String.trim(t)
        _ -> "Untitled course"
      end

    version =
      cond do
        Regex.match?(~r/schemaversion[^>]*>\s*1\.2/i, xml) -> "1.2"
        Regex.match?(~r/schemaversion[^>]*>\s*2004/i, xml) -> "2004"
        true -> "1.2"
      end

    launch_url =
      case Regex.run(~r/<resource[^>]*href=["']([^"']+)["']/i, xml) do
        [_, href] -> href
        _ -> "index.html"
      end

    %{title: title, version: version, launch_url: launch_url, raw: %{"xml" => xml}}
  end

  # ─── Storage paths ─────────────────────────────────────────────────────

  def package_dir(prefix, package_id) do
    Path.join([uploads_root(), "scorm", prefix, to_string(package_id)])
  end

  defp storage_relpath(prefix, package_id) do
    Path.join(["scorm", prefix, to_string(package_id)])
  end

  defp uploads_root do
    Application.fetch_env!(:atrium, :uploads_root)
  end

  # ─── Attempts ──────────────────────────────────────────────────────────

  def get_or_create_attempt(prefix, %Package{} = pkg, user_id) do
    case Repo.one(
           from(a in Attempt, where: a.package_id == ^pkg.id and a.user_id == ^user_id),
           prefix: prefix
         ) do
      nil ->
        attrs = %{package_id: pkg.id, user_id: user_id, started_at: DateTime.utc_now()}
        %Attempt{} |> Attempt.changeset(attrs) |> Repo.insert(prefix: prefix)

      attempt ->
        {:ok, attempt}
    end
  end

  def get_attempt(prefix, package_id, user_id) do
    Repo.one(
      from(a in Attempt, where: a.package_id == ^package_id and a.user_id == ^user_id),
      prefix: prefix
    )
  end

  @doc """
  Persist a flat map of cmi values (e.g. %{"cmi.core.lesson_status" => "completed"}).
  Recognises a handful of well-known keys and pulls them into typed columns.
  """
  def commit_attempt(prefix, %Attempt{} = attempt, cmi_map) when is_map(cmi_map) do
    cmi_merged = Map.merge(attempt.cmi || %{}, cmi_map)

    promoted = %{
      cmi: cmi_merged,
      lesson_status: cmi_merged["cmi.core.lesson_status"] || attempt.lesson_status,
      score_raw: parse_float(cmi_merged["cmi.core.score.raw"]) || attempt.score_raw,
      score_min: parse_float(cmi_merged["cmi.core.score.min"]) || attempt.score_min,
      score_max: parse_float(cmi_merged["cmi.core.score.max"]) || attempt.score_max,
      session_time: cmi_merged["cmi.core.session_time"] || attempt.session_time,
      total_time: cmi_merged["cmi.core.total_time"] || attempt.total_time,
      suspend_data: cmi_merged["cmi.suspend_data"] || attempt.suspend_data
    }

    promoted =
      if promoted.lesson_status in ["completed", "passed"] do
        Map.put(promoted, :completed_at, attempt.completed_at || DateTime.utc_now())
      else
        promoted
      end

    attempt
    |> Attempt.changeset(promoted)
    |> Repo.update(prefix: prefix)
  end

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil
  defp parse_float(n) when is_number(n), do: n * 1.0
  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  def completed?(%Attempt{lesson_status: s}), do: s in ["completed", "passed"]
  def completed?(_), do: false
end
