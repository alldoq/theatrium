defmodule Atrium.Accounts.PasswordResetToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "password_reset_tokens" do
    field :user_id, :binary_id
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def new_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :token_hash, :expires_at])
    |> validate_required([:user_id, :token_hash, :expires_at])
  end

  def mark_used_changeset(token, at), do: change(token, used_at: at)
end
