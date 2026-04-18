defmodule AtriumWeb.LearningController do
  use AtriumWeb, :controller

  alias Atrium.Learning
  alias Atrium.Learning.Course

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: {:section, "learning"}]
       when action in [:index, :show, :complete, :uncomplete]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: {:section, "learning"}]
       when action in [:new, :create, :edit, :update, :publish, :archive, :add_material, :delete_material]

  def index(conn, _params) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "learning"})

    published = Learning.list_courses(prefix)
    all_courses = if can_edit, do: Learning.list_courses(prefix, status: :all), else: []
    drafts_and_archived = Enum.reject(all_courses, &(&1.status == "published"))

    completion_ids = Learning.completed_course_ids(prefix, user.id, Enum.map(published, & &1.id))

    render(conn, :index,
      courses: published,
      drafts_and_archived: drafts_and_archived,
      completion_ids: completion_ids,
      can_edit: can_edit
    )
  end

  def show(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    course = Learning.get_course!(prefix, id)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "learning"})

    if course.status != "published" && !can_edit do
      conn |> put_status(:not_found) |> put_view(AtriumWeb.ErrorHTML) |> render(:"404") |> halt()
    else
      materials = Learning.list_materials(prefix, id)
      completed = Learning.completed?(prefix, id, user.id)
      count = if can_edit, do: Learning.completion_count(prefix, id), else: nil

      render(conn, :show,
        course: course,
        materials: materials,
        completed: completed,
        completion_count: count,
        can_edit: can_edit
      )
    end
  end

  def new(conn, _params) do
    render(conn, :new, changeset: Course.changeset(%Course{}, %{}))
  end

  def create(conn, %{"course" => params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user

    case Learning.create_course(prefix, params, user) do
      {:ok, course} ->
        conn
        |> put_flash(:info, "Course created.")
        |> redirect(to: ~p"/learning/#{course.id}/edit")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Could not create course.")
        |> render(:new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, id)
    materials = Learning.list_materials(prefix, id)
    render(conn, :edit,
      course: course,
      materials: materials,
      changeset: Course.changeset(course, %{})
    )
  end

  def update(conn, %{"id" => id, "course" => params}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, id)

    case Learning.update_course(prefix, course, params) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, "Course updated.")
        |> redirect(to: ~p"/learning/#{updated.id}")

      {:error, changeset} ->
        materials = Learning.list_materials(prefix, id)
        conn
        |> put_flash(:error, "Could not update course.")
        |> render(:edit, course: course, materials: materials, changeset: changeset)
    end
  end

  def publish(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, id)

    case Learning.publish_course(prefix, course) do
      {:ok, _} ->
        conn |> put_flash(:info, "Course published.") |> redirect(to: ~p"/learning/#{id}")
      {:error, _} ->
        conn |> put_flash(:error, "Cannot publish this course.") |> redirect(to: ~p"/learning/#{id}/edit")
    end
  end

  def archive(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, id)

    case Learning.archive_course(prefix, course) do
      {:ok, _} ->
        conn |> put_flash(:info, "Course archived.") |> redirect(to: ~p"/learning")
      {:error, _} ->
        conn |> put_flash(:error, "Cannot archive this course.") |> redirect(to: ~p"/learning/#{id}")
    end
  end

  def complete(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    course = Learning.get_course!(prefix, id)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "learning"})

    if course.status != "published" && !can_edit do
      conn |> put_status(:not_found) |> put_view(AtriumWeb.ErrorHTML) |> render(:"404") |> halt()
    else
      case Learning.complete_course(prefix, id, user.id) do
        {:ok, _} -> conn |> redirect(to: ~p"/learning/#{id}")
        {:error, _} ->
          conn |> put_flash(:error, "Could not mark as complete.") |> redirect(to: ~p"/learning/#{id}")
      end
    end
  end

  def uncomplete(conn, %{"id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    course = Learning.get_course!(prefix, id)
    can_edit = Atrium.Authorization.Policy.can?(prefix, user, :edit, {:section, "learning"})

    if course.status != "published" && !can_edit do
      conn |> put_status(:not_found) |> put_view(AtriumWeb.ErrorHTML) |> render(:"404") |> halt()
    else
      case Learning.uncomplete_course(prefix, id, user.id) do
        :ok -> conn |> redirect(to: ~p"/learning/#{id}")
        {:error, _} ->
          conn |> put_flash(:error, "Could not remove completion.") |> redirect(to: ~p"/learning/#{id}")
      end
    end
  end

  def add_material(conn, %{"id" => id, "material" => params}) do
    prefix = conn.assigns.tenant_prefix
    course = Learning.get_course!(prefix, id)

    case Learning.add_material(prefix, course.id, params) do
      {:ok, _} ->
        conn |> put_flash(:info, "Material added.") |> redirect(to: ~p"/learning/#{id}/edit")
      {:error, _changeset} ->
        conn |> put_flash(:error, "Invalid material.") |> redirect(to: ~p"/learning/#{id}/edit")
    end
  end

  def delete_material(conn, %{"id" => id, "mid" => mid}) do
    prefix = conn.assigns.tenant_prefix
    case Learning.delete_material(prefix, id, mid) do
      {:ok, _} ->
        conn |> put_flash(:info, "Material removed.") |> redirect(to: ~p"/learning/#{id}/edit")
      {:error, _} ->
        conn |> put_flash(:error, "Could not remove material.") |> redirect(to: ~p"/learning/#{id}/edit")
    end
  end
end
