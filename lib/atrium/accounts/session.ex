defmodule Atrium.Accounts.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sessions" do
    field :user_id, :binary_id
    field :token_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :ip, :string
    field :user_agent, :string
    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def new_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :token_hash, :expires_at, :last_seen_at, :ip, :user_agent])
    |> validate_required([:user_id, :token_hash, :expires_at, :last_seen_at])
  end

  def touch_changeset(session, at), do: change(session, last_seen_at: at)
end
