defmodule Atrium.Repo.TenantMigrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :user_id, :binary_id, null: false
      add :type, :string, null: false
      add :title, :string, null: false
      add :body, :text
      add :resource_type, :string
      add :resource_id, :binary_id
      add :read_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:notifications, [:user_id])
    create index(:notifications, [:user_id, :read_at])
  end
end
