defmodule Atrium.Learning do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Learning.{Course, CourseMaterial, CourseCompletion}

  def list_courses(prefix, opts \\ []) do
    query =
      case Keyword.get(opts, :status) do
        :all -> from(c in Course, order_by: [asc: c.category, asc: c.title])
        _ -> from(c in Course, where: c.status == "published", order_by: [asc: c.category, asc: c.title])
      end

    Repo.all(query, prefix: prefix)
  end

  def get_course!(prefix, id), do: Repo.get!(Course, id, prefix: prefix)

  def create_course(prefix, attrs, actor_user) do
    attrs_with_creator = Map.put(stringify(attrs), "created_by_id", actor_user.id)

    Repo.transaction(fn ->
      with {:ok, course} <-
             %Course{}
             |> Course.changeset(attrs_with_creator)
             |> Repo.insert(prefix: prefix),
           {:ok, _} <-
             Atrium.Audit.log(prefix, "course.created", %{
               actor: {:user, actor_user.id},
               resource: {"Course", course.id}
             }) do
        course
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_course(prefix, %Course{} = course, attrs) do
    course
    |> Course.changeset(stringify(attrs))
    |> Repo.update(prefix: prefix)
  end

  def publish_course(prefix, %Course{status: "draft"} = course) do
    Repo.transaction(fn ->
      with {:ok, updated} <-
             course |> Course.changeset(%{status: "published"}) |> Repo.update(prefix: prefix),
           {:ok, _} <-
             Atrium.Audit.log(prefix, "course.published", %{
               actor: :system,
               resource: {"Course", updated.id}
             }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def publish_course(_prefix, _course), do: {:error, :invalid_status}

  def archive_course(prefix, %Course{status: "published"} = course) do
    Repo.transaction(fn ->
      with {:ok, updated} <-
             course |> Course.changeset(%{status: "archived"}) |> Repo.update(prefix: prefix),
           {:ok, _} <-
             Atrium.Audit.log(prefix, "course.archived", %{
               actor: :system,
               resource: {"Course", updated.id}
             }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def archive_course(_prefix, _course), do: {:error, :invalid_status}

  def list_materials(prefix, course_id) do
    Repo.all(
      from(m in CourseMaterial,
        where: m.course_id == ^course_id,
        order_by: [asc: m.position]
      ),
      prefix: prefix
    )
  end

  def add_material(prefix, course_id, attrs) do
    attrs_with_course = Map.put(stringify(attrs), "course_id", course_id)

    %CourseMaterial{}
    |> CourseMaterial.changeset(attrs_with_course)
    |> Repo.insert(prefix: prefix)
  end

  def delete_material(prefix, material_id) do
    case Repo.get(CourseMaterial, material_id, prefix: prefix) do
      nil -> {:error, :not_found}
      material -> Repo.delete(material, prefix: prefix)
    end
  end

  def complete_course(prefix, course_id, user_id) do
    %CourseCompletion{}
    |> CourseCompletion.changeset(%{
      course_id: course_id,
      user_id: user_id,
      completed_at: DateTime.utc_now()
    })
    |> Repo.insert(
      prefix: prefix,
      on_conflict: {:replace, [:updated_at]},
      conflict_target: [:course_id, :user_id],
      returning: true
    )
  end

  def uncomplete_course(prefix, course_id, user_id) do
    case Repo.get_by(CourseCompletion, [course_id: course_id, user_id: user_id], prefix: prefix) do
      nil -> :ok
      completion ->
        case Repo.delete(completion, prefix: prefix) do
          {:ok, _} -> :ok
          {:error, _} = err -> err
        end
    end
  end

  def completed?(prefix, course_id, user_id) do
    Repo.exists?(
      from(c in CourseCompletion,
        where: c.course_id == ^course_id and c.user_id == ^user_id
      ),
      prefix: prefix
    )
  end

  def completion_count(prefix, course_id) do
    Repo.aggregate(
      from(c in CourseCompletion, where: c.course_id == ^course_id),
      :count,
      :id,
      prefix: prefix
    )
  end

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
