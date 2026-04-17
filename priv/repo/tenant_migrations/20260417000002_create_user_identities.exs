defmodule Atrium.Repo.TenantMigrations.CreateUserIdentities do
  use Ecto.Migration

  def change do
    create table(:user_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :provider_subject, :string, null: false
      add :raw_claims, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_identities, [:provider, :provider_subject])
    create index(:user_identities, [:user_id])
  end
end
