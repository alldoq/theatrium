defmodule Atrium.Notifications.FormMailer do
  import Swoosh.Email

  alias Atrium.Mailer
  require Logger

  def notify_submission(form, submission, recipients) when is_list(recipients) do
    Enum.each(recipients, fn recipient ->
      to_email = recipient["email"]
      to_name = recipient["name"] || recipient["email"]

      if to_email && to_email != "" do
        email =
          new()
          |> to({to_name, to_email})
          |> from({"Atrium", "no-reply@atrium.app"})
          |> subject("New submission: #{form.title}")
          |> html_body("""
          <p>A new submission has been received for <strong>#{form.title}</strong>.</p>
          <p>Please log in to Atrium to review and action this submission.</p>
          """)
          |> text_body("New submission received for #{form.title}. Please log in to Atrium to review it.")

        case Mailer.deliver(email) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.warning("FormMailer: failed to deliver to #{to_email}: #{inspect(reason)}")
        end
      end
    end)
  end

  def notify_submission(_form, _submission, _recipients), do: :ok
end
