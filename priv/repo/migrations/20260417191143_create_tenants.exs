defmodule Atrium.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "provisioning"
      add :theme, :map, null: false, default: %{}
      add :enabled_sections, {:array, :string}, null: false, default: []
      add :allow_local_login, :boolean, null: false, default: true
      add :session_idle_timeout_minutes, :integer, null: false, default: 480
      add :session_absolute_timeout_days, :integer, null: false, default: 30
      add :audit_retention_days, :integer, null: false, default: 2555
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenants, [:slug])
    create index(:tenants, [:status])

    execute(
      "ALTER TABLE tenants ADD CONSTRAINT tenants_status_check CHECK (status IN ('provisioning', 'active', 'suspended', 'decommissioned'))",
      "ALTER TABLE tenants DROP CONSTRAINT tenants_status_check"
    )

    execute(
      "ALTER TABLE tenants ADD CONSTRAINT tenants_slug_format CHECK (slug ~ '^[a-z][a-z0-9_]{1,62}$')",
      "ALTER TABLE tenants DROP CONSTRAINT tenants_slug_format"
    )
  end
end
