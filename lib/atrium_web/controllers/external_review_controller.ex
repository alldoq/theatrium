defmodule AtriumWeb.ExternalReviewController do
  use AtriumWeb, :controller
  alias Atrium.Forms

  def show(conn, %{"token" => token}) do
    case Forms.get_review_by_token(token) do
      {:ok, review, prefix} ->
        submission = Forms.get_submission!(prefix, review.submission_id)
        form = Forms.get_form!(prefix, submission.form_id)
        version =
          Forms.list_versions(prefix, form.id)
          |> Enum.find(&(&1.version == submission.form_version))
        render(conn, :show, review: review, submission: submission, form: form, version: version, token: token)

      {:error, :expired} ->
        conn |> put_status(400) |> text("This review link has expired.")

      {:error, _} ->
        conn |> put_status(400) |> text("Invalid review link.")
    end
  end

  def complete(conn, %{"token" => token}) do
    case Forms.get_review_by_token(token) do
      {:ok, review, prefix} ->
        if review.status == "completed" do
          conn |> put_flash(:info, "This review has already been completed.") |> render(:show, review: review, token: token, already_done: true)
        else
          case Forms.complete_review(prefix, review, nil) do
            {:ok, _} -> conn |> put_flash(:info, "Review marked as complete. Thank you.") |> redirect(to: ~p"/forms/review/#{token}")
            {:error, _} -> conn |> put_status(500) |> text("Could not complete review.")
          end
        end

      {:error, :expired} ->
        conn |> put_status(400) |> text("This review link has expired.")

      {:error, _} ->
        conn |> put_status(400) |> text("Invalid review link.")
    end
  end
end
