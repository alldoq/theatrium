defmodule Atrium.Accounts.UserIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "user_identities" do
    field :user_id, :binary_id
    field :provider, :string
    field :provider_subject, :string
    field :raw_claims, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:user_id, :provider, :provider_subject, :raw_claims])
    |> validate_required([:user_id, :provider, :provider_subject])
    |> validate_inclusion(:provider, ~w(local oidc saml))
    |> unique_constraint([:provider, :provider_subject])
  end
end
