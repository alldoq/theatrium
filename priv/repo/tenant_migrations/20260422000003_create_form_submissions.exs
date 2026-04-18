defmodule Atrium.Repo.TenantMigrations.CreateFormSubmissions do
  use Ecto.Migration

  def change do
    create table(:form_submissions, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :form_id, references(:forms, type: :binary_id, on_delete: :delete_all), null: false
      add :form_version, :integer, null: false
      add :submitted_by_id, :binary_id, null: false
      add :submitted_at, :utc_datetime_usec, null: false
      add :status, :string, null: false, default: "pending"
      add :field_values, :jsonb, null: false, default: "{}"
      add :file_keys, :jsonb, null: false, default: "[]"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:form_submissions, [:form_id])
    create index(:form_submissions, [:submitted_by_id])
    create index(:form_submissions, [:status])
  end
end
