defmodule Atrium.SuperAdmins.SuperAdmin do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "super_admins" do
    field :email, :string
    field :name, :string
    field :hashed_password, :string
    field :status, :string, default: "active"
    field :last_login_at, :utc_datetime_usec
    field :password, :string, virtual: true, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(sa, attrs) do
    sa
    |> cast(attrs, [:email, :name, :password])
    |> validate_required([:email, :name, :password])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    |> validate_length(:password, min: 16, max: 128)
    |> unique_constraint(:email)
    |> put_hashed_password()
  end

  def status_changeset(sa, status) do
    sa
    |> change(status: status)
    |> validate_inclusion(:status, ~w(active suspended), message: "must be one of: active, suspended")
  end

  def last_login_changeset(sa, at) do
    change(sa, last_login_at: at)
  end

  defp put_hashed_password(%Ecto.Changeset{valid?: true, changes: %{password: pw}} = cs) do
    cs
    |> put_change(:hashed_password, Argon2.hash_pwd_salt(pw))
    |> delete_change(:password)
  end

  defp put_hashed_password(cs), do: cs
end
