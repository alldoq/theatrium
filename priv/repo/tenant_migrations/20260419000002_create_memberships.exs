defmodule Atrium.Repo.TenantMigrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:memberships, [:user_id, :group_id])
    create index(:memberships, [:group_id])
  end
end
