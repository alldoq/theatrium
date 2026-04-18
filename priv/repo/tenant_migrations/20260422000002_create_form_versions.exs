defmodule Atrium.Repo.TenantMigrations.CreateFormVersions do
  use Ecto.Migration

  def change do
    create table(:form_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :form_id, references(:forms, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :fields, :jsonb, null: false, default: "[]"
      add :published_by_id, :binary_id, null: false
      add :published_at, :utc_datetime_usec, null: false
    end

    create index(:form_versions, [:form_id])
    create unique_index(:form_versions, [:form_id, :version])
  end
end
