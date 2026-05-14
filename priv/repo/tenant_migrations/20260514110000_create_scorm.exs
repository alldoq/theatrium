defmodule Atrium.Repo.TenantMigrations.CreateScorm do
  use Ecto.Migration

  def change do
    create table(:scorm_packages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :version, :string, null: false, default: "1.2"
      add :launch_url, :string, null: false
      add :manifest_json, :map
      add :storage_path, :string, null: false
      add :byte_size, :bigint
      add :uploaded_by_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    create index(:scorm_packages, [:course_id])

    create table(:scorm_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :package_id, references(:scorm_packages, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :binary_id, null: false
      add :lesson_status, :string, default: "not attempted"
      add :score_raw, :float
      add :score_min, :float
      add :score_max, :float
      add :total_time, :string, default: "0000:00:00.00"
      add :session_time, :string
      add :suspend_data, :text
      add :cmi, :map, default: %{}
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:scorm_attempts, [:package_id, :user_id])
    create index(:scorm_attempts, [:user_id])
  end
end
