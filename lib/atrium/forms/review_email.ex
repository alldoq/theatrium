defmodule Atrium.Forms.ReviewEmail do
  import Swoosh.Email

  def external_reviewer(to_email, submission, token) do
    review_url = AtriumWeb.Endpoint.url() <> "/forms/review/#{token}"

    new()
    |> to(to_email)
    |> from({"Atrium", "no-reply@atrium.example"})
    |> subject("Action required: form submission review")
    |> text_body("""
    You have been asked to review a form submission.

    Visit this link to view and complete your review:
    #{review_url}

    This link is valid for 30 days.
    """)
  end
end
