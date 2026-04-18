defmodule AtriumWeb.FormController do
  use AtriumWeb, :controller
  alias Atrium.Forms
  alias Atrium.Forms.Form

  plug AtriumWeb.Plugs.Authorize,
       [capability: :view, target: &__MODULE__.section_target/1]
       when action in [:index, :show, :submit_form, :create_submission, :submissions_index, :show_submission]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: &__MODULE__.section_target/1]
       when action in [:new, :create, :edit, :update, :publish, :reopen, :complete_review]

  plug AtriumWeb.Plugs.Authorize,
       [capability: :approve, target: &__MODULE__.section_target/1]
       when action in [:archive]

  def section_target(conn), do: {:section, conn.path_params["section_key"]}

  def index(conn, %{"section_key" => section_key} = params) do
    prefix = conn.assigns.tenant_prefix
    opts = if st = params["status"], do: [status: st], else: []
    forms = Forms.list_forms(prefix, section_key, opts)
    render(conn, :index, forms: forms, section_key: section_key)
  end

  def new(conn, %{"section_key" => section_key}) do
    changeset = Form.changeset(%Form{}, %{})
    render(conn, :new, changeset: changeset, section_key: section_key)
  end

  def create(conn, %{"section_key" => section_key, "form" => form_params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    attrs = Map.put(form_params, "section_key", section_key)

    case Forms.create_form(prefix, attrs, user) do
      {:ok, form} ->
        conn
        |> put_flash(:info, "Form created.")
        |> redirect(to: ~p"/sections/#{section_key}/forms/#{form.id}/edit")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(422) |> render(:new, changeset: changeset, section_key: section_key)

      {:error, _} ->
        conn |> put_flash(:error, "An unexpected error occurred.") |> redirect(to: ~p"/sections/#{section_key}/forms")
    end
  end

  def show(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    form = Forms.get_form!(prefix, id)
    versions = Forms.list_versions(prefix, form.id)
    history = Atrium.Audit.history_for(prefix, "Form", form.id)
    render(conn, :show, form: form, versions: versions, history: history, section_key: section_key)
  end

  def edit(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    form = Forms.get_form!(prefix, id)

    if form.status != "draft" do
      conn
      |> put_flash(:error, "Only draft forms can be edited.")
      |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")
    else
      changeset = Form.update_changeset(form, %{})
      latest_fields =
        case Forms.list_versions(prefix, form.id) do
          [] -> []
          [v | _] -> v.fields
        end
      render(conn, :edit, form: form, changeset: changeset, section_key: section_key, latest_fields: latest_fields)
    end
  end

  def update(conn, %{"section_key" => section_key, "id" => id, "form" => form_params}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    form = Forms.get_form!(prefix, id)

    case Forms.update_form(prefix, form, form_params, user) do
      {:ok, updated} ->
        conn |> put_flash(:info, "Form updated.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{updated.id}/edit")

      {:error, :not_draft} ->
        conn |> put_flash(:error, "Only draft forms can be edited.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(422) |> render(:edit, form: form, changeset: changeset, section_key: section_key, latest_fields: [])

      {:error, _} ->
        conn |> put_flash(:error, "An unexpected error occurred.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")
    end
  end

  def publish(conn, %{"section_key" => section_key, "id" => id, "form" => %{"fields" => fields_json}}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    form = Forms.get_form!(prefix, id)
    fields = Jason.decode!(fields_json)

    case Forms.publish_form(prefix, form, fields, user) do
      {:ok, _} ->
        conn |> put_flash(:info, "Form published.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")

      {:error, _} ->
        conn |> put_flash(:error, "Could not publish form.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/edit")
    end
  end

  def archive(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    form = Forms.get_form!(prefix, id)

    case Forms.archive_form(prefix, form, user) do
      {:ok, _} -> conn |> put_flash(:info, "Form archived.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")
      {:error, _} -> conn |> put_flash(:error, "Could not archive form.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")
    end
  end

  def reopen(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    form = Forms.get_form!(prefix, id)

    case Forms.reopen_form(prefix, form, user) do
      {:ok, _} -> conn |> put_flash(:info, "Form reopened for editing.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/edit")
      {:error, _} -> conn |> put_flash(:error, "Could not reopen form.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}")
    end
  end

  def submit_form(conn, %{"section_key" => section_key, "id" => id}) do
    prefix = conn.assigns.tenant_prefix
    form = Forms.get_form!(prefix, id)

    if form.status != "published" do
      conn |> put_flash(:error, "This form is not available.") |> redirect(to: ~p"/sections/#{section_key}/forms")
    else
      version = Forms.get_latest_version!(prefix, form.id)
      render(conn, :submit_form, form: form, version: version, section_key: section_key)
    end
  end

  def create_submission(conn, %{"section_key" => section_key, "id" => id, "submission" => values}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    form = Forms.get_form!(prefix, id)

    case Forms.create_submission(prefix, form, values, user) do
      {:ok, sub} ->
        conn |> put_flash(:info, "Form submitted.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/submissions/#{sub.id}")

      {:error, _} ->
        version = Forms.get_latest_version!(prefix, form.id)
        conn |> put_status(422) |> render(:submit_form, form: form, version: version, section_key: section_key)
    end
  end

  def submissions_index(conn, %{"section_key" => section_key, "id" => id} = params) do
    prefix = conn.assigns.tenant_prefix
    form = Forms.get_form!(prefix, id)
    opts = if st = params["status"], do: [status: st], else: []
    submissions = Forms.list_submissions(prefix, form.id, opts)
    render(conn, :submissions_index, form: form, submissions: submissions, section_key: section_key)
  end

  def show_submission(conn, %{"section_key" => section_key, "id" => id, "sid" => sid}) do
    prefix = conn.assigns.tenant_prefix
    form = Forms.get_form!(prefix, id)
    submission = Forms.get_submission!(prefix, sid)
    reviews = Forms.list_reviews(prefix, submission.id)
    version =
      Forms.list_versions(prefix, form.id)
      |> Enum.find(&(&1.version == submission.form_version))
    render(conn, :show_submission, form: form, submission: submission, reviews: reviews, version: version, section_key: section_key)
  end

  def complete_review(conn, %{"section_key" => section_key, "id" => id, "sid" => sid}) do
    prefix = conn.assigns.tenant_prefix
    user = conn.assigns.current_user
    _form = Forms.get_form!(prefix, id)

    review =
      Forms.list_reviews(prefix, sid)
      |> Enum.find(&(&1.reviewer_id == user.id && &1.status == "pending"))

    case review do
      nil ->
        conn |> put_flash(:error, "No pending review found.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/submissions/#{sid}")

      r ->
        case Forms.complete_review(prefix, r, user) do
          {:ok, _} -> conn |> put_flash(:info, "Review marked complete.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/submissions/#{sid}")
          {:error, _} -> conn |> put_flash(:error, "Could not complete review.") |> redirect(to: ~p"/sections/#{section_key}/forms/#{id}/submissions/#{sid}")
        end
    end
  end
end
