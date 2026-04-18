defmodule Atrium.Repo.TenantMigrations.CreateAuditEvents do
  use Ecto.Migration

  def change do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, :binary_id
      add :actor_type, :string, null: false
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :string
      add :changes, :map, null: false, default: %{}
      add :context, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:audit_events, [:actor_id, :occurred_at])
    create index(:audit_events, [:resource_type, :resource_id, :occurred_at])
    create index(:audit_events, [:action, :occurred_at])
  end
end
