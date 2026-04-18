defmodule Atrium.Forms do
  import Ecto.Query
  alias Atrium.Repo
  alias Atrium.Audit
  alias Atrium.Forms.{Form, FormVersion, FormSubmission, FormSubmissionReview}
  alias Atrium.Notifications.Dispatcher

  def create_form(prefix, attrs, actor_user) do
    string_attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    attrs_with_author = Map.put(string_attrs, "author_id", actor_user.id)

    Repo.transaction(fn ->
      with {:ok, form} <- insert_form(prefix, attrs_with_author),
           {:ok, _} <- Audit.log(prefix, "form.created", %{
             actor: {:user, actor_user.id},
             resource: {"Form", form.id},
             changes: %{"title" => [nil, form.title], "section_key" => [nil, form.section_key]}
           }) do
        form
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_form!(prefix, id) do
    Repo.get!(Form, id, prefix: prefix)
  end

  def list_forms(prefix, section_key, opts \\ []) do
    query =
      from f in Form,
        where: f.section_key == ^section_key,
        order_by: [desc: f.inserted_at]

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [f], f.status == ^status)
      end

    Repo.all(query, prefix: prefix)
  end

  def update_form(prefix, %Form{status: "draft"} = form, attrs, actor_user) do
    Repo.transaction(fn ->
      with {:ok, updated} <- apply_update(prefix, form, attrs),
           {:ok, _} <- Audit.log(prefix, "form.updated", %{
             actor: {:user, actor_user.id},
             resource: {"Form", updated.id},
             changes: Audit.changeset_diff(form, updated)
           }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_form(_prefix, _form, _attrs, _actor_user), do: {:error, :not_draft}

  def publish_form(prefix, %Form{status: "draft"} = form, fields, actor_user) do
    Repo.transaction(fn ->
      with {:ok, published} <- apply_status(prefix, form, "published"),
           {:ok, _ver} <- insert_version(prefix, published, fields, actor_user),
           {:ok, _} <- Audit.log(prefix, "form.published", %{
             actor: {:user, actor_user.id},
             resource: {"Form", published.id},
             changes: %{"status" => ["draft", "published"], "version" => [nil, published.current_version]}
           }) do
        published
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def publish_form(_prefix, _form, _fields, _actor_user), do: {:error, :invalid_transition}

  def archive_form(prefix, %Form{status: "published"} = form, actor_user) do
    Repo.transaction(fn ->
      with {:ok, archived} <- apply_status(prefix, form, "archived"),
           {:ok, _} <- Audit.log(prefix, "form.archived", %{
             actor: {:user, actor_user.id},
             resource: {"Form", archived.id},
             changes: %{"status" => ["published", "archived"]}
           }) do
        archived
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def archive_form(_prefix, _form, _actor_user), do: {:error, :invalid_transition}

  def reopen_form(prefix, %Form{status: "published"} = form, actor_user) do
    Repo.transaction(fn ->
      cs =
        form
        |> Form.status_changeset("draft")
        |> Form.version_bump_changeset()

      with {:ok, reopened} <- Repo.update(cs, prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "form.updated", %{
             actor: {:user, actor_user.id},
             resource: {"Form", reopened.id},
             changes: %{"status" => ["published", "draft"], "current_version" => [form.current_version, reopened.current_version]}
           }) do
        reopened
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def reopen_form(_prefix, _form, _actor_user), do: {:error, :invalid_transition}

  def list_versions(prefix, form_id) do
    from(v in FormVersion,
      where: v.form_id == ^form_id,
      order_by: [desc: v.version]
    )
    |> Repo.all(prefix: prefix)
  end

  def get_latest_version!(prefix, form_id) do
    from(v in FormVersion,
      where: v.form_id == ^form_id,
      order_by: [desc: v.version],
      limit: 1
    )
    |> Repo.one!(prefix: prefix)
  end

  def create_submission(prefix, form, field_values, actor_user) do
    version = form.current_version

    Repo.transaction(fn ->
      with {:ok, sub} <- insert_submission(prefix, form, version, field_values, actor_user),
           {:ok, _} <- create_reviews(prefix, sub, form.notification_recipients),
           {:ok, _} <- Audit.log(prefix, "form.submission_created", %{
             actor: {:user, actor_user.id},
             resource: {"FormSubmission", sub.id},
             changes: %{"form_id" => [nil, form.id], "form_version" => [nil, version]}
           }) do
        sub
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, sub} ->
        Dispatcher.form_submission(prefix, form, sub, actor_user)
        enqueue_notification(prefix, sub.id)
        Task.start(fn ->
          Atrium.Notifications.FormMailer.notify_submission(form, sub, form.notification_recipients || [])
        end)
        {:ok, sub}
      err -> err
    end
  end

  def get_submission!(prefix, id) do
    Repo.get!(FormSubmission, id, prefix: prefix)
  end

  def list_submissions(prefix, form_id, opts \\ []) do
    query =
      from s in FormSubmission,
        where: s.form_id == ^form_id,
        order_by: [desc: s.submitted_at]

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [s], s.status == ^status)
      end

    Repo.all(query, prefix: prefix)
  end

  def list_reviews(prefix, submission_id) do
    from(r in FormSubmissionReview,
      where: r.submission_id == ^submission_id
    )
    |> Repo.all(prefix: prefix)
  end

  def complete_review(prefix, review, actor_user_or_nil) do
    completed_by_id = if actor_user_or_nil, do: actor_user_or_nil.id, else: nil

    Repo.transaction(fn ->
      with {:ok, done} <- Repo.update(FormSubmissionReview.complete_changeset(review, completed_by_id), prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "form.review_completed", %{
             actor: if(actor_user_or_nil, do: {:user, actor_user_or_nil.id}, else: :system),
             resource: {"FormSubmissionReview", done.id},
             changes: %{"status" => ["pending", "completed"]}
           }),
           {:ok, _sub} <- maybe_complete_submission(prefix, done.submission_id) do
        done
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_review_by_token(token) do
    case Phoenix.Token.verify(AtriumWeb.Endpoint, "form_review", token, max_age: 30 * 24 * 3600) do
      {:ok, %{"submission_id" => sid, "reviewer_email" => email, "prefix" => prefix}} ->
        review =
          from(r in FormSubmissionReview,
            where: r.submission_id == ^sid and r.reviewer_email == ^email and r.reviewer_type == "email"
          )
          |> Repo.one(prefix: prefix)

        case review do
          nil -> {:error, :not_found}
          r -> {:ok, r, prefix}
        end

      {:error, :expired} -> {:error, :expired}
      {:error, _} -> {:error, :invalid}
    end
  end

  defp insert_form(prefix, attrs) do
    %Form{}
    |> Form.changeset(attrs)
    |> Repo.insert(prefix: prefix)
  end

  defp apply_update(prefix, form, attrs) do
    form
    |> Form.update_changeset(attrs)
    |> Repo.update(prefix: prefix)
  end

  defp apply_status(prefix, form, status) do
    form
    |> Form.status_changeset(status)
    |> Repo.update(prefix: prefix)
  end

  defp insert_version(prefix, form, fields, actor_user) do
    %FormVersion{}
    |> FormVersion.changeset(%{
      form_id: form.id,
      version: form.current_version,
      fields: fields,
      published_by_id: actor_user.id,
      published_at: DateTime.utc_now()
    })
    |> Repo.insert(prefix: prefix)
  end

  defp insert_submission(prefix, form, version, field_values, actor_user) do
    %FormSubmission{}
    |> FormSubmission.changeset(%{
      form_id: form.id,
      form_version: version,
      submitted_by_id: actor_user.id,
      submitted_at: DateTime.utc_now(),
      field_values: field_values
    })
    |> Repo.insert(prefix: prefix)
  end

  defp create_reviews(_prefix, _sub, []), do: {:ok, []}

  defp create_reviews(prefix, sub, recipients) do
    results =
      Enum.map(recipients, fn recipient ->
        attrs = %{
          submission_id: sub.id,
          reviewer_type: recipient["type"] || recipient[:type],
          reviewer_id: recipient["id"] || recipient[:id],
          reviewer_email: recipient["email"] || recipient[:email]
        }

        %FormSubmissionReview{}
        |> FormSubmissionReview.changeset(attrs)
        |> Repo.insert(prefix: prefix)
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))
    if errors == [], do: {:ok, results}, else: hd(errors)
  end

  defp maybe_complete_submission(prefix, submission_id) do
    pending_count =
      from(r in FormSubmissionReview,
        where: r.submission_id == ^submission_id and r.status == "pending",
        select: count()
      )
      |> Repo.one(prefix: prefix)

    if pending_count == 0 do
      sub = Repo.get!(FormSubmission, submission_id, prefix: prefix)

      with {:ok, completed} <- Repo.update(FormSubmission.complete_changeset(sub), prefix: prefix),
           {:ok, _} <- Audit.log(prefix, "form.submission_completed", %{
             actor: :system,
             resource: {"FormSubmission", completed.id},
             changes: %{"status" => ["pending", "completed"]}
           }) do
        {:ok, completed}
      end
    else
      {:ok, :not_yet_complete}
    end
  end

  def list_submissions_for_user(prefix, user_id, section_key) do
    form_ids =
      Repo.all(from(f in Form, where: f.section_key == ^section_key, select: f.id), prefix: prefix)

    subs =
      Repo.all(
        from(s in FormSubmission,
          where: s.form_id in ^form_ids and s.submitted_by_id == ^user_id,
          order_by: [desc: s.inserted_at]
        ),
        prefix: prefix
      )

    attach_forms(subs, prefix)
  end

  def list_pending_submissions(prefix, section_key) do
    form_ids =
      Repo.all(from(f in Form, where: f.section_key == ^section_key, select: f.id), prefix: prefix)

    subs =
      Repo.all(
        from(s in FormSubmission,
          where: s.form_id in ^form_ids and s.status == "pending",
          order_by: [desc: s.inserted_at]
        ),
        prefix: prefix
      )

    attach_forms(subs, prefix)
  end

  defp attach_forms(subs, prefix) do
    form_ids = subs |> Enum.map(& &1.form_id) |> Enum.uniq()
    forms_by_id = Repo.all(from(f in Form, where: f.id in ^form_ids), prefix: prefix) |> Map.new(&{&1.id, &1})
    Enum.map(subs, &Map.put(&1, :form, Map.get(forms_by_id, &1.form_id)))
  end

  defp enqueue_notification(prefix, submission_id) do
    %{prefix: prefix, submission_id: submission_id}
    |> Atrium.Forms.NotificationWorker.new()
    |> Oban.insert()
  end
end
