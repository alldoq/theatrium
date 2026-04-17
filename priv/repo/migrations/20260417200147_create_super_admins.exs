defmodule Atrium.Repo.Migrations.CreateSuperAdmins do
  use Ecto.Migration

  def change do
    create table(:super_admins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :name, :string, null: false
      add :hashed_password, :string, null: false
      add :status, :string, null: false, default: "active"
      add :last_login_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:super_admins, [:email])
  end
end
