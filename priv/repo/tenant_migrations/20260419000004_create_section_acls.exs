defmodule Atrium.Repo.TenantMigrations.CreateSectionAcls do
  use Ecto.Migration

  def change do
    create table(:section_acls, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :section_key, :string, null: false
      add :principal_type, :string, null: false
      add :principal_id, :binary_id, null: false
      add :capability, :string, null: false
      add :granted_by, :binary_id
      add :granted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:section_acls, [:section_key, :principal_type, :principal_id, :capability],
      name: :section_acls_unique)
    create index(:section_acls, [:principal_type, :principal_id])
  end
end
