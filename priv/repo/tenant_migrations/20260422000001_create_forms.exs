defmodule Atrium.Repo.TenantMigrations.CreateForms do
  use Ecto.Migration

  def change do
    create table(:forms, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :title, :string, null: false
      add :section_key, :string, null: false
      add :subsection_slug, :string, null: true
      add :status, :string, null: false, default: "draft"
      add :current_version, :integer, null: false, default: 1
      add :author_id, :binary_id, null: false
      add :notification_recipients, :jsonb, null: false, default: "[]"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:forms, [:section_key])
    create index(:forms, [:section_key, :subsection_slug])
    create index(:forms, [:author_id])
    create index(:forms, [:status])
  end
end
