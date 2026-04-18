defmodule Atrium.Forms.NotificationWorker do
  use Oban.Worker, queue: :notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"prefix" => prefix, "submission_id" => sid}}) do
    reviews = Atrium.Forms.list_reviews(prefix, sid)
    sub = Atrium.Forms.get_submission!(prefix, sid)

    Enum.each(reviews, fn review ->
      case review.reviewer_type do
        "email" -> send_external_email(prefix, sub, review)
        "user" -> :ok
      end
    end)

    :ok
  end

  defp send_external_email(prefix, sub, review) do
    token = Phoenix.Token.sign(AtriumWeb.Endpoint, "form_review", %{
      "submission_id" => sub.id,
      "reviewer_email" => review.reviewer_email,
      "prefix" => prefix
    })

    review.reviewer_email
    |> Atrium.Forms.ReviewEmail.external_reviewer(sub, token)
    |> Atrium.Mailer.deliver()

    :ok
  end
end
