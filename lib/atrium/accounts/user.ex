defmodule Atrium.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(invited active suspended)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :email, :string
    field :name, :string
    field :status, :string, default: "invited"
    field :hashed_password, :string
    field :last_login_at, :utc_datetime_usec
    field :is_admin, :boolean, default: false
    field :role, :string
    field :department, :string
    field :phone, :string
    field :bio, :string
    field :avatar_url, :string
    field :skills, {:array, :string}, default: []
    field :password, :string, virtual: true, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def invite_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_required([:email, :name])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    |> unique_constraint(:email)
    |> put_change(:status, "invited")
  end

  def activate_password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 128)
    |> put_hashed_password()
    |> put_change(:status, "active")
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end

  def change_password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 128)
    |> put_hashed_password()
  end

  def status_changeset(user, status) do
    user
    |> change(status: status)
    |> validate_inclusion(:status, @statuses, message: "is invalid")
  end

  def last_login_changeset(user, at), do: change(user, last_login_at: at)

  def admin_changeset(user, is_admin) do
    change(user, is_admin: is_admin)
  end

  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :role, :department, :phone, :bio, :avatar_url, :skills])
    |> validate_required([:name])
    |> validate_length(:bio, max: 1000)
  end

  def statuses, do: @statuses

  defp put_hashed_password(%Ecto.Changeset{valid?: true, changes: %{password: pw}} = cs) do
    cs
    |> put_change(:hashed_password, Argon2.hash_pwd_salt(pw))
    |> delete_change(:password)
  end

  defp put_hashed_password(cs), do: cs
end
