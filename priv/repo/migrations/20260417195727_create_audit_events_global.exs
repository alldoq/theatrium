defmodule Atrium.Repo.Migrations.CreateAuditEventsGlobal do
  use Ecto.Migration

  def change do
    create table(:audit_events_global, primary_key: false) do
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

    create index(:audit_events_global, [:actor_id, :occurred_at])
    create index(:audit_events_global, [:resource_type, :resource_id, :occurred_at])
    create index(:audit_events_global, [:action, :occurred_at])
  end
end
