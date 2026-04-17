defmodule Atrium.Accounts.Emails do
  import Swoosh.Email
  alias Atrium.Tenants.Tenant

  def invitation_email(%Tenant{} = tenant, email, url) do
    new()
    |> to(email)
    |> from({"Atrium", "no-reply@atrium.example"})
    |> subject("You're invited to #{tenant.name}")
    |> text_body("""
    You've been invited to #{tenant.name} on Atrium.

    Activate your account: #{url}

    This link expires in 72 hours.
    """)
  end

  def password_reset_email(%Tenant{} = tenant, email, url) do
    new()
    |> to(email)
    |> from({"Atrium", "no-reply@atrium.example"})
    |> subject("Reset your #{tenant.name} password")
    |> text_body("""
    A password reset was requested for your account.

    Reset your password: #{url}

    This link expires in 1 hour. If you did not request this, ignore this email.
    """)
  end
end
