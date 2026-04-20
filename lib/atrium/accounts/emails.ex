defmodule Atrium.Accounts.Emails do
  import Swoosh.Email
  alias Atrium.Tenants.Tenant

  def invitation_email(%Tenant{} = tenant, email, url) do
    new()
    |> to(email)
    |> from(sender(tenant))
    |> subject("You're invited to #{tenant.name}")
    |> text_body("""
    You've been invited to #{tenant.name} on Atrium.

    Activate your account and set your password:
    #{url}

    This link expires in 72 hours.
    """)
  end

  def password_reset_email(%Tenant{} = tenant, email, url) do
    new()
    |> to(email)
    |> from(sender(tenant))
    |> subject("Reset your #{tenant.name} password")
    |> text_body("""
    A password reset was requested for your account.

    Reset your password:
    #{url}

    This link expires in 1 hour. If you did not request this, ignore this email.
    """)
  end

  defp sender(%Tenant{name: name}) do
    addr = Application.get_env(:atrium, :system_email, "hello@alldoq.com")
    {name || "Atrium", addr}
  end
end
